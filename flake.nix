# flake.nix — portable entry points for this SDK.
#
# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
#
# packages.<system>.static and .shared are two linkages of the one
# package.nix. .default preserves the SDK's native policy, static.
# devShells are tools-only; the SDK is never in a shell's packages.
#
# No builtins.getEnv here: an impure read would force --impure on every
# consumer. The nixpkgs input is pinned twice over instead: by revision in
# inputs.nixpkgs.url below, and by the committed flake.lock beside this file,
# which build.zig.zon lists in .paths so a fetched package carries the pin.
# There is no devenv.lock in this repository; devenv.yaml pins its own input
# by revision.

{
  description = "The IUPAC InChI chemical identifier library, built from its own sources with Zig 0.16";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs = { nixpkgs, ... }:
    let
      forAllSystems = f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed
          (system: f nixpkgs.legacyPackages.${system});

      # zig_0_16 exactly: build.zig calls b.systemIntegrationOption,
      # b.addTranslateC and std.Io.Threaded, none of which exist earlier.
      tools = pkgs: { zig = pkgs.zig_0_16; };
    in
    {
      packages = forAllSystems (pkgs:
        let
          inchi = linkage: pkgs.callPackage ./package.nix {
            inherit linkage;
            zig = (tools pkgs).zig;
          };
        in
        {
          default = inchi "static";
          static = inchi "static";
          shared = inchi "dynamic";
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            zig_0_16
            # addTranslateC drives a C preprocessor and libinchi links libc
            # and libm, so a C toolchain is needed beside the Zig driver.
            clang
            llvm
            pkg-config
          ];
        };
      });
    };
}