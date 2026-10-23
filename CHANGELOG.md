# Changelog

- The nested consumer forwards user arguments, linkage, system mode and non-default install prefixes; it runs when the target executor is available and builds otherwise.
- `KeyVerdict` preserves native values: `standard = 0`, `non_standard = -1`, `invalid_length = 1`, `invalid_layout = 2`, `invalid_version = 3`.
- Molfile read and generation failures map to `.rejected`; the other named `MolfileStatus` values remain part of the upstream code set.
- Devenv build and install scripts use this package directory, an explicit cache, bounded jobs and an explicit install prefix.
- Atom bond counts outside `0..max_bonds_per_atom` return `TooManyNeighbors` before either atom is modified.
- The package commits and ships `flake.lock` with the nixpkgs input used by the flake.
- `-Druntime=true` (default `false`) loads an explicitly named path or system provider, independent of linkage, with no fallback to a linked copy; it cannot be combined with `-fsys=inchi`.
- Nix exposes static and shared derivations; the default is static, and devenv exposes both outputs lazily.
- The facade documents ownership and matching release functions for output, structure and auxiliary results, plus warning-state semantics.
- The in-tree C build is the default; `-fsys=inchi` uses the installed library and its pkg-config metadata.
- `-Dlinkage=static|dynamic` selects the bundled library form; static is the default.
- `IdentifierVerdict` and `KeyVerdict` are non-exhaustive, so unknown native values are not unreachable cases.
- The option prefix template is copied and its placeholders are replaced at runtime before calling upstream.
- C input structs remain mutable where upstream requires it; borrowed input contents remain const.
- The six borrowed C output strings retain their NUL terminators in the Zig types.
- The two upstream C patches fix a nested-comment delimiter, make the usage banner reproducible and guard `<sys/timeb.h>` after `mode.h` defines `COMPILE_ANSI_ONLY`.
- The package builds and installs upstream's full `libinchi` target, including the six IXA translation units.
- A Zig 0.16 package and `inchi` module expose a facade over upstream InChI 1.07.5.
