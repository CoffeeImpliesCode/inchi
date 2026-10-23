# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional

{
  description = "The IUPAC InChI chemical identifier library, built from its own sources with Zig 0.16";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs = { nixpkgs, ... }:
    let
      forAllSystems = f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed
          (system: f nixpkgs.legacyPackages.${system});

      # Build uses Zig 0.16 APIs.
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
            # C translation and libinchi linking require a C toolchain.
            clang
            llvm
            pkg-config
          ];
        };
      });
    };
}