# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
# Shared by the flake and devenv packaging entry points.

{ lib, stdenv, zig, linkage ? "static" }:

let
  # Read the software version from upstream's CURRENT_VER macro.
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

  # Allowlist the source files for the Nix derivation.
  sourceFiles = lib.fileset.unions [
    ./build.zig
    ./build.zig.zon
    ./translate.h
    ./zig
    ./tests.zig
    ./smoke.zig
    # Runtime sources configure the build; tests embed the oracle from testdata.
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

  # Disable Nix's default phases; installPhase runs the Zig build.
  dontConfigure = true;
  dontBuild = true;
  dontSetZigDefaultFlags = true;
  dontAddPrefix = true;
  dontCheck = true;
  # Disable the hook's duplicate test build.
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches under the Nix sandbox's writable TMPDIR.
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"

    # Build ReleaseSafe; Nix indented strings escape shell variable interpolation.
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