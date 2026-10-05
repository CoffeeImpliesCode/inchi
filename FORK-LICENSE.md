# FORK-LICENSE.md — the grant for this fork's own files

`NOTICE.md` is the per-file inventory: which files are upstream's, which are
this fork's, and which term covers each. This file is the grant for the second
group only.

## Authorization

Upstream's MIT grant reaches upstream's files and nothing else; it does not
license a line this fork wrote. Until the repository owner authorized a term,
this fork stated none for its own files and `NOTICE.md` recorded them as
**unassigned**; the earlier claim that they were "contributed under MIT" was
withdrawn. The owner has since authorized a licence for the fork-authored
additions, chosen per project and matching this project's primary upstream
terms.

The authorization covers the files this fork adds and edits, listed in
[`NOTICE.md`](NOTICE.md) § What this fork changed. It does not change any
upstream term, and it does not reach back: a copy fetched before this grant
existed carries no term for these files, and none is claimed for it.

## SPDX identifier

```
LicenseRef-InChI-MIT-Conditional
```

`LicenseRef-` is SPDX's mechanism for a licence with no published short name.
It is used rather than `MIT` because **the InChI grant is not bare MIT**, and a
scanner that finds `MIT` stops at the permission grant and misses the two
conditions below. This identifier is defined in full by the text under it; it is
not a registered SPDX identifier and nothing here claims it is.

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

The permission and warranty text above is upstream's `LICENSE`, verbatim.

### Condition A — the InChI attribution notice travels

Upstream's own files carry an acknowledgement block beyond the standard MIT
notice clause, at `INCHI-1-SRC/INCHI_BASE/src/inchi_api.h:29-37` and
identically at `ixa.h:29-37`, naming IUPAC, the InChI Trust, NIST, the
external contributors listed in `External-contributors`, and
`info@inchi-trust.org`, under `Copyright (c) 2024 IUPAC and InChI Trust`
(`inchi_api.h:9`). Redistribution must keep that notice with the files and must
not strip upstream's copyright line from them. `External-contributors` is named
by the notice and lives outside the shipped directories, so a dependent who
fetches this package does not receive it.

This condition also governs the version banner. Upstream identifies the
software in the identifier itself (`1S`, from `mode.h:258`) and in the usage
banner `HelpCommandLineParms` prints from
`INCHI-1-SRC/INCHI_BASE/src/ichiparm.c`, with the same identification in the
`INCHIGEN_*` status strings. That is why the authorised `ichiparm.c` patch
replaces `__DATE__`/`__TIME__` with the **pinned source tag** and a literal
`"(no build timestamp)"` rather than removing the banner: reproducibility and
identification agree, and deleting it would satisfy one at the other's cost.
The patch record is in [`UPSTREAM.md`](UPSTREAM.md) § `ichiparm.c`.

### Condition B — these files travel with the InChI software package

Upstream states the same coupling for its own SHA-256 implementation at
`INCHI-1-SRC/INCHI_BASE/src/sha2.c:9-13` and `sha2.h:9-13`:

```
 * This code is free software; you can redistribute it and/or
 * modify it, as a part of the International Chemical Identifier (InChI)
 * software, under the terms of the MIT license
 * https://opensource.org/license/mit
 *
 * Note that this licensing is only valid in combination with the InChI
 * software package, for all other cases contact Paul Bakker.
```

The owner applies the same coupling to this fork's additions: the files listed
in [`NOTICE.md`](NOTICE.md) § What this fork changed may be redistributed and
modified **as a part of the InChI software package**, together with the
upstream core they build. The sentence naming Paul Bakker belongs to his
files and is not restated here as a permission about anything else.

## What the grant does not cover

* **Upstream's work.** Nothing here changes an upstream term. The MIT grant on
  the core, the `sha2` condition, `stb_sprintf.h`'s dual MIT/Unlicense choice,
  the Apache-2.0 on `tbb/tbbmalloc_proxy.h` and the shipped
  `INCHI-1-SRC/INCHI_API/tbb/LICENSE` are as [`NOTICE.md`](NOTICE.md) records
  them.
* **A copyright identity.** The line above says a holder exists and names none,
  because **no personal or corporate identity was supplied and none is invented
  here**. Before publication the owner substitutes the holder's own line. That
  is a publication step; nothing is blocked on it while the package is local.
* **The independent fixture.** `testdata/pubchem_known_answers.tsv` is credited
  to PubChem in its own header and recorded in [`NOTICE.md`](NOTICE.md). The
  grant below covers its packaging only.

## The header on newly authored files

`build.zig`, `build.zig.zon`, `package.nix`, `flake.nix`, `devenv.nix`,
`devenv.yaml`, `cross-test.profile.sh`, `.envrc` and each new Zig and C source
file carry:

```
// SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
```

`translate.h` and `runtime/sync.c` carry the same identifier in a C comment,
and `runtime/sync.h` in its leading block comment, because that is the only
comment syntax those file types have.

**Six files this package claims carry no identifier**, and are claimed here
rather than left in a hole. Two cannot, because their format has no comment
syntax; four are omissions, recorded rather than silently unclaimed:

| File | Why it carries no identifier |
|---|---|
| `flake.lock` | **format, not omission.** JSON with no comment syntax, and an extra key would break the lock schema. It is a fork-authored file and it is under this grant |
| `.gitignore`, `consumer/.gitignore` | **format, not omission.** git reads one pattern per line and there is nowhere to put a comment that does not change what upstream's own 31 rules mean. Both are fork-owned files, `NOTICE.md` § What this fork changed accounts for the root one, and both are under this grant |
| `consumer/build.zig.zon` | **omission.** It could carry the `//` line that `build.zig.zon:1` carries; this one has none. It is a separate package with its own name and fingerprint, listed in `NOTICE.md`, and it is under this grant |
| `zig/molecules.zig` | **omission.** Zig does have the comment syntax. Its first line is a doc comment saying what the file is and that it is deliberately not part of the published module, and no SPDX line follows. It is under this grant |
| `testdata/pubchem_known_answers.tsv` | **omission.** It is the independent fixture, credited in its own header to PubChem, a service of the U.S. National Library of Medicine, with the CIDs the answers were read from. This grant covers its **packaging** only, never its content — see below |

So the header is the rule and this table is the exception list, not the other
way round: a fork-authored file that carries neither the identifier nor an
entry in [`NOTICE.md`](NOTICE.md) is one this package does not claim under this
grant.

## See also

* [`NOTICE.md`](NOTICE.md) — the per-file inventory and every per-file exception.
* [`UPSTREAM.md`](UPSTREAM.md) — the pin, the integrity record, the two patches.
* [`README.md`](README.md) — current deviations, current matrix, consumption.