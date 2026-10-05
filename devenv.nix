# devenv.nix — the canonical development shell for this SDK.
#
# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
#
# packages carries tools only. outputs.static and outputs.shared are the two
# linkages of the same package.nix, called lazily, so entering the shell does
# not build the SDK:
#   devenv build outputs.static
#   devenv build outputs.shared
# Inside the shell, the scripts below compile this repository's own sources.
# Every one of them finds this SDK itself, so the caller's working directory
# does not matter, and the two that install write their delivery outside this
# checkout.

{ pkgs, lib, ... }:

let
  zig = pkgs.zig_0_16;
  inchi = linkage: pkgs.callPackage ./package.nix { inherit zig linkage; };

  # This SDK's own directory, quoted once for a shell. `./.` in an expression is
  # relative to the file that contains it, so it is this SDK and not whichever
  # directory the caller happened to be standing in; `lib.escapeShellArg` so a
  # checkout whose path carries a space or a quote still reaches the shell as a
  # single argument. `builtins.toString`, and not an interpolated `${./.}`:
  # interpolating the path itself asks Nix for the store copy of this whole tree,
  # and that copy is read-only and is not the working tree `UPSTREAM.sha256` and
  # the driver's source digest describe.
  sdkRoot = lib.escapeShellArg (builtins.toString ./.);

  # The first line of every script body, so no two of them can drift on it. The
  # `exit 1` matters: a body that carried on after a failed `cd` would build in,
  # or check, whatever directory it happened to be standing in.
  inSdkRoot = "cd ${sdkRoot} || exit 1";

  # The Zig caches, named by the bodies rather than by `enterShell`, because
  # `devenv tasks run --mode single <name>` reaches a body without the shell
  # hooks and this fill has to happen before the compiler starts. A caller that
  # exported either variable keeps it: this never unsets and never overwrites
  # one. When one is missing, the root is `$XDG_CACHE_HOME`, else `$TMPDIR`,
  # else nothing at all — the body names what is missing and stops rather than
  # choosing a location of its own, and never falls back to this checkout's own
  # `.zig-cache`.
  #
  # `cacheDir` is this SDK's own cache directory under the local root, named
  # `inchi` the way box2d names its own; the global cache is the root's
  # `zig-global`, because it is shared by every SDK on the mount and is not this
  # file's to name per SDK. `--cache-dir` carries `cacheDir`, and the exported
  # variables carry the rest, so no flag is written twice.
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

  # Where the two installing scripts install. `zig build install`'s own default
  # is `zig-out` beside the build root, and the build root here is this checkout,
  # which is the working tree `UPSTREAM.sha256` and the driver's source digest
  # cover. A caller's own prefix wins: `INCHI_PREFIX` when one was exported,
  # else `$ZIG_LOCAL_CACHE_DIR/inchi/zig-out` — and `chooseCaches` above has
  # already filled and exported that variable, or stopped the body, so there is
  # no second resolution order here and no `zig-out` fallback.
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
    # addTranslateC drives a C preprocessor and libinchi links libc and libm.
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

  # Real commands under one `sdk` namespace, no bare task keys. Each entry is
  # one `{ exec = ...; }`: devenv's `scripts` option takes a flat attribute set
  # of scripts, so these cannot nest under a `sdk` attribute.
  scripts = {
    # The default step of this build graph is the install step, so this is the
    # one script that writes a delivery: the archive, both public headers, the
    # generated `inchi.pc`, `bin/misuse` and the licence material under
    # `share/doc/inchi/`. It says where that delivery goes rather than taking
    # `zig build`'s own `zig-out`, which in this package is inside this checkout.
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

    # Neither step installs anything, so neither takes a prefix: `build.zig`
    # hangs the smoke program's compile step under the install step
    # (`build.zig:671`) and never the reverse (`build.zig:662`, `build.zig:675`),
    # which means a `--prefix` here would be a flag that changes nothing.
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

    # `devenv build` reads the project it is standing in, so these two need the
    # same first line as the rest; they are Nix builds, and the job count for
    # one of those is the caller's `--max-jobs`/`--cores`, not `-j8` on a
    # `zig build` that this file never runs.
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