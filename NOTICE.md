# NOTICE

## Upstream attribution

InChI Version 1; software version 1.07; April 30, 2024. Copyright (c) 2024 IUPAC and InChI Trust. Developed under IUPAC auspices, originally at NIST; modifications and additions by IUPAC and the InChI Trust. Upstream names external contributors in `External-contributors` and gives `info@inchi-trust.org`. That file is outside the shipped directories.

`LICENSE:3` instead says `Copyright (c) 2024 InChI Project`. Both copyright lines are upstream's and remain in their respective files.

## Grants and scope

The InChI library uses the MIT grant in `LICENSE`, shipped unchanged. Its notice clause reads: "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software." Of the 105 files in the two shipped source directories, 100 carry the InChI notice. The other five are `INCHI-1-SRC/INCHI_BASE/src/sha2.c`, `INCHI-1-SRC/INCHI_BASE/src/sha2.h`, `INCHI-1-SRC/INCHI_BASE/src/tbb/tbbmalloc_proxy.h`, `INCHI-1-SRC/INCHI_API/libinchi/src/CMakeLists.txt` and `INCHI-1-SRC/INCHI_BASE/src/readme.txt`. The installed public headers, `inchi_api.h` and `ixa.h`, carry the notice.

The upstream source headers also require the attribution block to travel. It names IUPAC, the InChI Trust, NIST, external contributors and `info@inchi-trust.org`. The InChI identifier, usage banner and generator status strings identify the software version; the `ichiparm.c` patch replaces the build-date arguments with the pinned tag and `(no build timestamp)` rather than removing the banner.

| Path | Licence and scope |
|---|---|
| `INCHI-1-SRC/INCHI_BASE/src/sha2.c`, `INCHI-1-SRC/INCHI_BASE/src/sha2.h` | MIT applies only in combination with the InChI software package; `sha2.h` says, "Note that this licensing is only valid in combination with the InChI software package, for all other cases contact Paul Bakker." It credits `Copyright (C) 2010 Paul Bakker` and says the code was originally written 2003-2006 by Christophe Devine. |
| `INCHI-1-SRC/INCHI_BASE/src/stb_sprintf.h` | stb_sprintf 1.10; either the file's `ALTERNATIVE A - MIT License` (Copyright (c) 2017 Sean Barrett) or `ALTERNATIVE B - Public Domain` (`www.unlicense.org`). Both texts remain in the file. |
| `INCHI-1-SRC/INCHI_BASE/src/tbb/tbbmalloc_proxy.h` | Apache-2.0, Copyright (c) 2005-2018 Intel Corporation. The header ships unmodified; upstream's full licence text ships at `INCHI-1-SRC/INCHI_API/tbb/LICENSE`. The header is not compiled or included by this package. |

`sha2.c` and `sha2.h` are used only through `ikey_dll.c`. That file attributes the same SHA-256 implementation to Brainspark B.V.; `sha2.h` attributes it to Paul Bakker and Christophe Devine. This upstream discrepancy is unresolved, and neither SHA-256 file is modified here.

The MIT text and all source notices remain unchanged. The two upstream source patches are `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and `INCHI-1-SRC/INCHI_BASE/src/ichicano.c`; both retain their upstream headers and licence scope.

## Fork-authored files

The repository owner authorized `LicenseRef-InChI-MIT-Conditional` for the fork-authored files below. Its full grant is in `FORK-LICENSE.md`; it applies to these files when distributed as part of the InChI software package. It does not alter upstream terms or extend to copies fetched before the grant. No personal or corporate copyright holder is named; the holder line must be supplied before publication.

- Build and package: `build.zig`, `build.zig.zon`, `translate.h`, `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc`.
- Facade and tests: `zig/root.zig`, `zig/molecules.zig`, `tests.zig`, `smoke.zig`, `testdata/pubchem_known_answers.tsv`, `cross-test.profile.sh`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig`, `consumer/.gitignore`.
- Runtime: `runtime/graph.zig`, `runtime/library.zig`, `runtime/load_tests.zig`, `runtime/misuse.zig`, `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h`. The last four are shared loader-core files copied into this package; they are fork-side, not upstream files.
- Documentation: `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md`, `NOTICE.md`, `UPSTREAM.md`, `UPSTREAM.sha256`.
- `.gitignore` contains upstream rules followed by this fork's build-output ignores; it is edited and is not in `.paths` or `UPSTREAM.sha256`. `README.upstream.md` is upstream's README, unchanged and under upstream terms.

`testdata/pubchem_known_answers.tsv` contains values retrieved from PubChem, a service of the U.S. National Library of Medicine, for CIDs 962, 297, 702, 241, 750, 5950, 71080, 24602, 62695 and 5287573. The source query for CID 962 used PubChem PUG REST: `https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/962/property/InChI,InChIKey,MolecularFormula/JSON`. Its header credits PubChem; `UPSTREAM.sha256` records the fixture.

`zig build install` installs `LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md` and both READMEs under `share/doc/inchi/`; the Apache licence copy is at `share/doc/inchi/tbb/LICENSE`.
