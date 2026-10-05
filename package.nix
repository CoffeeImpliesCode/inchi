# package.nix — the one source-only derivation for this SDK.
#
# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
#
# Both entry points use:
#   pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; inherit linkage; }
# `linkage` defaults to "static", the SDK's native policy. One derivation;
# the .static/.shared variants are made by the entry points.

{ lib, stdenv, zig, linkage ? "static" }:

let
  # Upstream defines the software version in one place, bcf_s.h:52
  # `#define CURRENT_VER "1.07.5" /* ... */`. Read it there rather than
  # restating it, so a version bump cannot pass through this file unnoticed.
  # The pattern cannot cross a newline and `builtins.match` has to span the
  # whole string, so it is applied to one line at a time.
  version =
    let
      currentVer = "[^\n]*#define CURRENT_VER \"([^\"]+)\"[^\n]*";
      defining = builtins.filter (line: builtins.match currentVer line != null)
        (lib.splitString "\n" (builtins.readFile ./INCHI-1-SRC/INCHI_BASE/src/bcf_s.h));
    in
    if defining == [ ]
    then throw "package.nix: INCHI-1-SRC/INCHI_BASE/src/bcf_s.h defines no CURRENT_VER; refusing to guess a version"
    else builtins.head (builtins.match currentVer (builtins.head defining));

  validLinkages = [ "static" "dynamic" ];

  # Exactly what `zig build install` reads. Being an allow-list, it also
  # excludes .git, .zig-cache, zig-out, zig-pkg, .devenv*, .direnv and
  # result/result-*, so no local build state reaches the source hash. Bare
  # paths: lib.fileset coerces a path to one file or to a directory's whole
  # closure and exports no `file` or `path` constructor.
  sourceFiles = lib.fileset.unions [
    ./build.zig
    ./build.zig.zon
    ./translate.h
    ./zig
    ./tests.zig
    ./smoke.zig
    # build.zig imports runtime/graph.zig while it configures, and the install
    # step builds runtime/misuse.zig; tests.zig embeds the oracle in testdata/.
    ./runtime
    ./testdata
    ./INCHI-1-SRC/INCHI_BASE/src
    ./INCHI-1-SRC/INCHI_API/libinchi/src
    ./INCHI-1-SRC/INCHI_API/tbb/LICENSE
    ./INCHI-1-SRC/INCHI_API/libinchi/gcc/libinchi.map
    ./LICENSE
    ./NOTICE.md
    ./FORK-LICENSE.md
    ./UPSTREAM.md
    ./FORK-NOTES.md
    ./UPSTREAM.sha256
    ./README.md
    ./README.upstream.md
  ];
in

assert lib.assertMsg (builtins.elem linkage validLinkages)
  "package.nix: linkage must be one of ${lib.concatStringsSep ", " validLinkages}, got ${linkage}";

stdenv.mkDerivation {
  pname = "inchi";
  inherit version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = sourceFiles;
  };

  nativeBuildInputs = [ zig ];

  # Install-only: the SDK's own build graph is the sole builder. dontInstall is
  # deliberately NOT set — it would disable the phase below. The Zig hook's
  # default flags are disabled so `zig build` runs once, with the flags named.
  dontConfigure = true;
  dontBuild = true;
  dontSetZigDefaultFlags = true;
  dontAddPrefix = true;
  dontCheck = true;
  # Without this the Zig setup hook substitutes its own `zig build test` for the
  # check phase, which is a second, differently-flagged build of the same tree.
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Both caches under the Nix-provided TMPDIR: the sandbox has no writable
    # HOME, and nothing is written inside the unpacked source tree.
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"

    # One optimize selection, chosen here: a packaged library is ReleaseSafe.
    # C flags, the source list, header configuration, the native artifact and
    # the .pc all come from build.zig; this file adds none.
    # The job-count expansion below is written with the Nix escape for a
    # literal dollar-brace; a bare one inside a Nix indented string would be
    # parsed as Nix interpolation rather than as shell.
    zig build install \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=ReleaseSafe \
      -Dcpu=baseline \
      -Dlinkage=${linkage} \
      --prefix "$out"

    runHook postInstall
  '';

  meta = {
    description = "IUPAC International Chemical Identifier (InChI) library, built from this package's own sources";
    longDescription = ''
      Builds upstream's libinchi from the INCHI-1-SRC tree this package ships:
      all 60 translation units of the libinchi target including the six-unit
      IXA backend, less two disclosed patches to ichiparm.c and ichicano.c,
      under upstream's own -std=c11 / -fno-strict-aliasing / TARGET_API_LIB /
      COMPILE_ANSI_ONLY configuration. Installs the library, inchi_api.h,
      ixa.h, inchi.pc, bin/misuse, and the licence material under
      share/doc/inchi. InChI itself ships no tools and no runtime data, so
      bin/misuse — fork-authored — is the only executable.
    '';
    homepage = "https://github.com/IUPAC-InChI/InChI";
    # The dominant grant only. Not single-licensed: sha2.c/.h add a coupling
    # condition, stb_sprintf.h is MIT-or-Unlicense, tbb/tbbmalloc_proxy.h is
    # Apache-2.0 and travels uncompiled, and this fork's own files are under
    # LicenseRef-InChI-MIT-Conditional. See $out/share/doc/inchi/NOTICE.md.
    license = lib.licenses.mit;
    licenseFile = "LICENSE";
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

  passthru = {
    inherit linkage;
    licenseInventory = "NOTICE.md";
    forkLicense = "FORK-LICENSE.md";
    upstreamRecord = "UPSTREAM.md";
  };
}