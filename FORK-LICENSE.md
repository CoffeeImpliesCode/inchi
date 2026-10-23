# Fork licence

The owner authorized this grant for fork-added or edited files listed in `NOTICE.md`. Upstream's MIT grant covers upstream files only. It changes no upstream terms and excludes pre-grant copies.

## The grant

MIT License

Copyright (c) 2026 the authors of this `inchi` Zig SDK package

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

The MIT text above is upstream's `LICENSE`, verbatim.

## Condition A: InChI attribution

Upstream's acknowledgement at `INCHI-1-SRC/INCHI_BASE/src/inchi_api.h:29-37` and `ixa.h:29-37` names IUPAC, InChI Trust, NIST, `External-contributors`, and `info@inchi-trust.org`, under `Copyright (c) 2024 IUPAC and InChI Trust` (`inchi_api.h:9`). Redistribution must keep that notice with the files and must not strip upstream's copyright line from them. `External-contributors` is outside shipped directories. Package consumers do not receive it.

Version identification is covered: upstream uses `1S` (`mode.h:258`), the `HelpCommandLineParms` banner in `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c`, and `INCHIGEN_*` statuses. The patch replaces `__DATE__` and `__TIME__` with the pinned source tag and `"(no build timestamp)"`.

## Condition B: package coupling

Upstream's SHA-256 condition appears in `INCHI-1-SRC/INCHI_BASE/src/sha2.c:9-13` and `sha2.h:9-13`:

```
 * This code is free software; you can redistribute it and/or
 * modify it, as a part of the International Chemical Identifier (InChI)
 * software, under the terms of the MIT license
 * https://opensource.org/license/mit
 *
 * Note that this licensing is only valid in combination with the InChI
 * software package, for all other cases contact Paul Bakker.
```

Fork additions in `NOTICE.md` may be redistributed and modified **as a part of the InChI software package**, together with the upstream core they build. Paul Bakker's sentence applies only to his files and grants no other permission.

## What this grant does not cover

- **Upstream files.** InChI core: MIT; `sha2`: package coupling; `stb_sprintf.h`: MIT or Unlicense; `tbb/tbbmalloc_proxy.h`: Apache-2.0; `INCHI-1-SRC/INCHI_API/tbb/LICENSE`: upstream.

## SPDX headers

The unregistered identifier `LicenseRef-InChI-MIT-Conditional` covers `build.zig`, `build.zig.zon`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `cross-test.profile.sh`, `.envrc`, and new Zig or C source files.

```c
// SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
```

The same identifier is in C comments in `translate.h` and `runtime/sync.c`, and `runtime/sync.h`'s leading block comment.

These six files have no identifier:

| File | Grant scope |
|---|---|
| `flake.lock` | Fork-authored and covered. |
| `.gitignore`, `consumer/.gitignore` | Both fork-owned and covered. `NOTICE.md` lists the root file. |
| `consumer/build.zig.zon` | Separate package with its own name and fingerprint. `NOTICE.md` lists it. Covered. |
| `zig/molecules.zig` | Covered by this grant. |
| `testdata/pubchem_known_answers.tsv` | Header credits PubChem. Packaging only, not contents. |

Fork-authored files with neither this identifier nor a `NOTICE.md` entry are outside the grant.
