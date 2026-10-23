# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional

{
  description = "The IUPAC InChI chemical identifier library, built from its own sources with Zig 0.17";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

  outputs = { nixpkgs, ... }:
    let
      forAllSystems = f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed
          (system: f nixpkgs.legacyPackages.${system});

      # Build uses Zig 0.17 APIs.
      tools = pkgs: { zig = pkgs.zig_0_17; };
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
            zig_0_17
            # C translation and libinchi linking require a C toolchain.
            clang
            llvm
            pkg-config
          ];
        };
      });
    };
}