# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
#
# Tasks use this checkout and install outputs outside it.

{ pkgs, lib, ... }:

let
  zig = pkgs.zig_0_16;
  inchi = linkage: pkgs.callPackage ./package.nix { inherit zig linkage; };

  # Resolve this checkout independently of the caller's working directory.
  sdkRoot = lib.escapeShellArg (builtins.toString ./.);

  # Stop if changing to the SDK root fails.
  inSdkRoot = "cd ${sdkRoot} || exit 1";

  # Preserve caller cache overrides; otherwise use external paths or stop.
  # Never write caches into the source tree.
  chooseCaches = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        cacheRoot="$XDG_CACHE_HOME"
      elif [ -n "''${TMPDIR:-}" ]; then
        cacheRoot="$TMPDIR"
      else
        echo "inchi: ZIG_LOCAL_CACHE_DIR and ZIG_GLOBAL_CACHE_DIR are unset, and" >&2
        echo "XDG_CACHE_HOME and TMPDIR are unset too, so no Zig cache outside" >&2
        echo "this checkout is known. Export one of them at an approved mount." >&2
        exit 1
      fi
      if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
        ZIG_LOCAL_CACHE_DIR="$cacheRoot/zig-local"
      fi
      if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="$cacheRoot/zig-global"
      fi
      export ZIG_LOCAL_CACHE_DIR ZIG_GLOBAL_CACHE_DIR
    fi
    cacheDir="$ZIG_LOCAL_CACHE_DIR/inchi"
  '';

  # Install outside this checkout, unless INCHI_PREFIX is set.
  choosePrefix = ''
    if [ -n "''${INCHI_PREFIX:-}" ]; then
      prefix="$INCHI_PREFIX"
    else
      prefix="$ZIG_LOCAL_CACHE_DIR/inchi/zig-out"
    fi
  '';
in
{
  packages = with pkgs; [
    zig
    # C translation and libinchi linking require a C toolchain.
    clang
    llvm
    pkg-config
  ];

  outputs = {
    static = inchi "static";
    shared = inchi "dynamic";
    default = inchi "static";
  };

  enterShell = ''
    echo "inchi SDK — Zig $(zig version), building this repository's own sources."
    echo "  sdk:build                        install the bundled libinchi (static)"
    echo "  sdk:build-shared                 the same, shared"
    echo "  sdk:test                         the behavioural suite and the smoke program"
    echo "  sdk:check                        compile-only, six cross targets"
    echo "  sdk:package-static               the packaged static derivation"
    echo "  sdk:package-shared               the packaged shared derivation"
    echo "  every script runs in this SDK's own directory, whatever directory the"
    echo "  caller stood in, and gives the build runner -j8 --summary all with an"
    echo "  explicit --cache-dir under $ZIG_LOCAL_CACHE_DIR, which this file fills"
    echo "  in from $XDG_CACHE_HOME or $TMPDIR and never from the checkout."
    echo "  the two installers put their delivery under $INCHI_PREFIX, else"
    echo "  $ZIG_LOCAL_CACHE_DIR/inchi/zig-out."
  '';

  scripts = {
    # Keep the install prefix outside this checkout.
    "sdk:build" = {
      description = "Build and install the bundled library (static)";
      exec = ''
        ${inSdkRoot}
        ${chooseCaches}
        ${choosePrefix}
        zig build install --cache-dir "$cacheDir" --prefix "$prefix" -j8 --summary all
      '';
    };

    "sdk:build-shared" = {
      description = "Build and install the bundled library as a shared object";
      exec = ''
        ${inSdkRoot}
        ${chooseCaches}
        ${choosePrefix}
        zig build install --cache-dir "$cacheDir" --prefix "$prefix" -Dlinkage=dynamic -j8 --summary all
      '';
    };

    # Tests and checks do not install artifacts.
    "sdk:test" = {
      description = "Run the behavioural suite and the smoke program";
      exec = ''
        ${inSdkRoot}
        ${chooseCaches}
        zig build test smoke --cache-dir "$cacheDir" -j8 --summary all
      '';
    };

    "sdk:check" = {
      description = "Compile-only cross-target check over the six baseline targets";
      exec = ''
        ${inSdkRoot}
        ${chooseCaches}
        zig build check --cache-dir "$cacheDir" -j8 --summary all
      '';
    };

    # Nix tasks use caller's Nix job limits, not Zig's `-j8`.
    "sdk:package-static" = {
      description = "Build the packaged static derivation";
      exec = ''
        ${inSdkRoot}
        devenv build outputs.static
      '';
    };

    "sdk:package-shared" = {
      description = "Build the packaged shared derivation";
      exec = ''
        ${inSdkRoot}
        devenv build outputs.shared
      '';
    };
  };
}