# NOTICE

## Upstream work

InChI is the work of IUPAC and the InChI Trust. The notice upstream's own
public headers carry reads, at
`INCHI-1-SRC/INCHI_BASE/src/inchi_api.h:1-39` and, identically, at
`INCHI-1-SRC/INCHI_BASE/src/ixa.h:1-39`:

```
 * International Chemical Identifier (InChI)
 * Version 1
 * Software version 1.07
 * April 30, 2024
 *
 * MIT License
 *
 * Copyright (c) 2024 IUPAC and InChI Trust
 ...
 * The InChI library and programs are free software developed under the
 * auspices of the International Union of Pure and Applied Chemistry (IUPAC).
 * Originally developed at NIST.
 * Modifications and additions by IUPAC and the InChI Trust.
 * Some portions of code were developed/changed by external contributors
 * (either contractor or volunteer) which are listed in the file
 * 'External-contributors' included in this distribution.
 *
 * info@inchi-trust.org
```

`LICENSE:3` carries a different copyright line for the same grant, `Copyright
(c) 2024 InChI Project`. That is upstream's own inconsistency between two
upstream files. Both lines ship; neither is harmonised here.

`External-contributors` is named by that notice and lives outside the two
directories this package ships, so a dependent who fetches this package does
not receive it. See "Carried but not shipped" below.

## The grants, and which applies where

**The InChI library is `MIT`.** The text is `LICENSE`, shipped verbatim in
`.paths`, not edited, shortened or restated. The same grant is in the header of
every one of the 100 files among the 105 in the two shipped directories that
carry a notice.

Three files in the shipped set are not simply MIT, and this package does not
claim that they are:

| File | Terms, in the file's own words | What this fork has to do |
|---|---|---|
| `INCHI-1-SRC/INCHI_BASE/src/sha2.c`, `sha2.h` | `sha2.h:7-13`: "This code is free software; you can redistribute it and/or modify it, as a part of the International Chemical Identifier (InChI) software, under the terms of the MIT license … **Note that this licensing is only valid in combination with the InChI software package, for all other cases contact Paul Bakker.**" `sha2.h:4-5` credits `Copyright (C) 2010 Paul Bakker` and says it was originally written 2003-2006 by Christophe Devine | Ship them only as part of InChI. This package does exactly that: the only source among the 105 that includes them is `INCHI-1-SRC/INCHI_BASE/src/ikey_dll.c:60`, and this fork ships no mechanism that extracts them. The condition is recorded here so a later re-sync does not relocate them into a separate crate and call it redistribution |
| `INCHI-1-SRC/INCHI_BASE/src/stb_sprintf.h` | stb_sprintf v1.10, dual-licensed in the file itself: `ALTERNATIVE A - MIT License`, `Copyright (c) 2017 Sean Barrett`, or `ALTERNATIVE B - Public Domain` (`www.unlicense.org`) | Ship it unmodified with both texts where they are. The choice of which alternative applies was upstream's to make and this fork does not restate it |
| `INCHI-1-SRC/INCHI_BASE/src/tbb/tbbmalloc_proxy.h` | `Apache-2.0`, `Copyright (c) 2005-2018 Intel Corporation` (`tbbmalloc_proxy.h:2-19`) | **Discharged by the manifest.** It travels unmodified and the full Apache-2.0 text travels with it — see below |

### The Intel TBB header: travelling with its terms

`INCHI-1-SRC/INCHI_BASE/src/tbb/tbbmalloc_proxy.h` is licensed Apache-2.0, not
MIT, and it is inside `build.zig.zon` `.paths`, so a dependent who fetches this
package receives it. Both halves of that are true now, and only the first was:

1. **It is never compiled and never included.** Nothing among the 105 shipped
   files includes it. `INCHI_BASE/src/mode.h:240` includes a *different* file,
   `../../INCHI_API/tbb/tbbmalloc_proxy_for_inchi.h`, and only under
   `USE_TBB_MALLOC` — shipped commented out at `mode.h:229` — together with
   `_WIN32`. This build compiles the Intel allocator's declaration to nothing.
2. **Its licence text travels with it.** `.paths` ships
   `INCHI-1-SRC/INCHI_API/tbb/LICENSE` — upstream's own copy, the full Apache
   License 2.0 as it sits in the pinned tree, 201 lines including its appendix.
   Nothing was authored for it, and no licence text was copied in from elsewhere
   or from another project: the bytes are the ones upstream ships. Apache-2.0
   §4 is answered against that — §4(a) by the shipped text, §4(b) vacuously,
   because the header is byte-identical to upstream's and there are no changes
   to declare, §4(c) by shipping the file itself with its attribution intact,
   and §4(d) because upstream ships no `NOTICE` text for this work, so there is
   none to propagate. The Intel copyright in the header's own comment is
   retained verbatim.

Apache-2.0 §3 grants a Contributor patent licence for the claims necessarily
infringed by its Contributions alone or with the Work. If **You** institute
patent litigation against any entity, including a cross-claim or counterclaim,
alleging that the Work or an incorporated Contribution infringes a patent,
the patent licences granted to You for that Work terminate on the filing date.
The shipped `INCHI_API/tbb/LICENSE:73-87` retains that clause verbatim;
redistribution does not remove it.

**The gap is closed on both sides.** `.paths` ships
`INCHI-1-SRC/INCHI_API/tbb/LICENSE`, and `UPSTREAM.sha256` now names it as its
109th record, so the licence text travelling in the package is pinned like every
other upstream file it ships. `sha256sum -c UPSTREAM.sha256` read 109 records,
109 `: OK` lines, no failures, exit 0, with
`INCHI-1-SRC/INCHI_API/tbb/LICENSE: OK` among them, on the record as it stood at
the first patch (`local://foundation-expansion-inchi-authorized-patch-integrity-109-364.log`)
and in the `.paths`-filtered copy a dependent received at that time
(`local://foundation-expansion-inchi-current-filtered-package-integrity-388.log`),
109 of 109 in each. Both are history for the record as it now stands, because
each verified an `ichicano.c` line holding a digest this record no longer
names; the current whole-record replay is the driver's to run and to record, and
it is recorded outside this package, in the root ledger's `FORKS.json` under
`cross_test_wave`. The pre-patch receipts — `-240` over 109 records, `-221` and
`-127` over 108 — remain history: they verified an `ichiparm.c` line holding
upstream's bytes, and one of them describes a state before this digest existed.

### An upstream attribution this package does not resolve

`INCHI-1-SRC/INCHI_BASE/src/ikey_dll.c:45-47` says:

```
    Uses truncated SHA-256 function.
    SHA-256 implementation: Copyright (C) Brainspark B.V.,
                            see files sha2.c, sha2.h.
```

while `sha2.h:4-5` says `Copyright (C) 2010 Paul Bakker`, originally
Christophe Devine. Three names, two files. Both notices are upstream's bytes
and both ship. This fork edits neither file and picks neither name; it records
that the disagreement is upstream's, so that a future re-sync does not mistake
one of them for a mistake introduced here.

## MIT obligations, and how this fork meets them

The MIT licence asks for one thing, quoted from the shipped text
(`LICENSE:12-13`):

```
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

* The copyright notice and the permission notice are in `LICENSE`, shipped
  verbatim, and `LICENSE` is in `.paths` and hashed in `UPSTREAM.sha256`.
* They are also in the sources themselves, not only in `LICENSE`: 100 of the
  105 shipped files under the two source directories carry the notice, and the
  two installed public headers — `inchi_api.h` and `ixa.h` — are among them.
  The five that do not are `sha2.c`, `sha2.h`, `tbb/tbbmalloc_proxy.h`,
  `CMakeLists.txt` and `readme.txt`, each accounted for above.
* MIT has no attribution requirement beyond the notice, no source-disclosure
  requirement and no patent grant. There is no patent clause to terminate and
  no NOTICE file to propagate. That is stated here so the absence is not read
  as an omission.

The five files without the notice are not a gap this fork introduced: they
arrived that way and are unmodified.

## What this fork changed

**Two upstream source files are patched, under their own MIT terms.**
`INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` is edited once, for the reproducibility
reason written out in [`UPSTREAM.md`](UPSTREAM.md) § The two patched source files:
the compiler's wall-clock build stamp is out of its usage banner, and an
accidental nested-comment delimiter is out of a disabled block. The patch is
nine inserted lines — a seven-line disclosure comment and two string-literal
macros — plus three changed lines: the two banner arguments in
`HelpCommandLineParms`, and one existing comment line's format string. No
chemistry, no ABI, no allocator, no option, no timeout, no flag, no build mode,
and nothing suppressed.

`INCHI-1-SRC/INCHI_BASE/src/ichicano.c` is edited once, for the portability
reason written out in the same section: its `#include <sys/timeb.h>` is now
below `#include "mode.h"` — the header that defines `COMPILE_ANSI_ONLY` for
every non-Microsoft compiler and for `TARGET_API_LIB` — and inside
`#ifndef COMPILE_ANSI_ONLY`, so the guard is read after the definition it tests.
The patch is two inserted lines and no changed line; the include itself is
moved, not rewritten. Seven `zig cc` probes measured where that header is and is
not on this toolchain: **absent** on `aarch64-macos` and `x86_64-openbsd`, and
**present** on `x86_64-linux-gnu`, `x86_64-linux-musl`, `x86_64-netbsd`,
`wasm32-wasi` and `aarch64-freebsd` — seven targets, not a generalisation about
every cell of a 53-platform matrix. The only two readers of `struct _timeb` and
`_ftime` in the whole file, `InchiTimeGet` and `bInchiTimeIsOver`, sit in the
`#else` arm of this same file's `#ifdef COMPILE_ANSI_ONLY`, so the guard removes
a header nothing in that configuration uses and changes no compiled token in any
other one.

The 53-cell matrix has separately been run over the arrangement this package
ships — every one of its 53 cells exit 0, 20 of them executing the 16-test suite
and 33 compiled only, with no foreign BSD, macOS, Mac Catalyst, Windows or WASI
binary executed in any of them
(`local://foundation-cross-test-final-current-inchi.json`). That is compile and
test coverage of this patch, not a measurement of where a header exists: the
seven targets above are the whole of the latter claim.

MIT permits modification provided the notice travels, and it does: `LICENSE`
and both files' own header comments are unchanged and both shipped, so each
patched compilation unit carries the same grant and the same attribution as
every other one. **Every other upstream source file, header, build file,
licence text and document in the package is unmodified.** Of the record's 109
lines, 108 are upstream records — this fork's bytes for those two paths and
upstream's own for the other 106 — and the 109th is the independent fixture,
which is nobody's but this package's. Upstream's digest for each patched file
is preserved in `UPSTREAM.md` as the baseline each patch is measured against.

**Added by this fork, and offered under no licence at all.** Nobody authorised
this fork to grant its own files to anyone, and the earlier claim that they were
"contributed under MIT" was not true and has been withdrawn. They are
**unassigned**: no term is stated for them, and no term may be inferred from the
absence. That is a statement about these files only — it does not touch, narrow
or re-grant anything upstream ships, whose terms are exactly as recorded above.

| Path | What it is |
|---|---|
| `build.zig`, `build.zig.zon` | the build graph and the package manifest, including `.version = "1.7.5"` and the upstream pin that `build()` refuses to configure without |
| `translate.h` | the translation-unit root `addTranslateC` reads: a macro prelude naming upstream's own `TARGET_API_LIB` and `COMPILE_ANSI_ONLY`, then `#include "inchi_api.h"`, which itself ends with `#include "ixa.h"` (`inchi_api.h:1413`) |
| `zig/root.zig` | the Zig facade |
| `zig/molecules.zig` | the molecule fixtures the test and smoke roots share; **not** part of the published `inchi` module |
| `tests.zig` | the behavioural tests |
| `smoke.zig` | the deterministic smoke program |
| `cross-test.profile.sh` | the settings-only `cross-test` profile this package is measured through: it fixes the build step to `test` and deliberately names no target, no runner and no host path, so the whole published platform matrix stays whole and a cell with no detected runner is reported as build-only. It is Bash that `cross-test` sources, not documentation, and it is in `.paths` because a dependent receives the same gate the tree was measured with |
| `testdata/pubchem_known_answers.tsv` | the independent known answers — see the section below |
| `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig`, `consumer/.gitignore` | a separate package that depends on this one by path, to prove `dep.module("inchi")` resolves from outside |
| `.github/workflows/verify.yml` | this repository's own CI; upstream's `ci.yml`, `release.yml`, `deploy_docs.yml`, `build_matrix.json` and `actions/` are untouched and are not in `.paths` |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md` | the provenance and usage set |
| *(no new grant)* | The withdrawal above applies to every row in this table. Reading a licence into these files from the fact that upstream's are MIT is exactly the error this section exists to prevent |

Edited, three files: **`.gitignore`**, and two upstream C source files,
`INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c`.
Everything above the line `# ---- this fork's build outputs ---` is upstream's,
verbatim and in place — upstream's rules run through
`INCHI-1-SRC/INCHI_API/libinchi/src/build/`, and
none was removed to make room. The fork appended
`.zig-cache/`, `zig-out/`, `consumer/.zig-cache/` and `consumer/zig-out/`, none
of which swallows an upstream rule or a file this fork adds. `.gitignore` is
therefore deliberately **not** in `UPSTREAM.sha256`: it is not byte-identical
to upstream's.

**`INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c`** are the others, and they are the
opposite case: they *are* in `UPSTREAM.sha256`, because `.paths` ships them and
the build compiles them. Leaving either out would have hidden exactly the
divergence the record exists to make loud — the lesson kept as `FORK-NOTES.md`
L15 — so each record line is this fork's bytes and nothing is claimed about a
pristine tree any more. The 109 records still cover the same 109 paths; what
changed is which bytes two of them name.

## The independent fixture, and what it is credited to

`testdata/pubchem_known_answers.tsv` is not upstream's and not this fork's
chemistry. Every field in it was read out of **PubChem's own compound
records**, one CID at a time, through PubChem's PUG REST property endpoint:

```
https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/962/property/InChI,InChIKey,MolecularFormula/JSON
```

The ten compounds it records are PubChem CIDs 962, 297, 702, 241, 750, 5950,
71080, 24602, 62695 and 5287573 — water, methane, ethanol, benzene, glycine,
L-alanine, D-alanine, heavy water, *E*-but-2-ene and *Z*-but-2-ene. Nothing in
the file was produced by, or checked against, the library under test; where the
file and the library disagree, the file is right by construction. That is what
makes it an oracle rather than a snapshot.

PubChem is a service of the U.S. National Library of Medicine. The file is
credited in its own header, and it is hashed in `UPSTREAM.sha256` so that a
later edit to a published expectation is as loud as an edit to a source file.

Upstream's own test material is **not** used and not shipped:
`INCHI-1-TEST/` — upstream's Python and gtest distribution, including its
html report generator, its Compose file and its build scripts — stays in this
repository for provenance and is not in `.paths`, so no test of this package
reads it.

## Cryptographic suitability

Partly, and the part matters. InChI is an identifier, not a keyed primitive:
nothing here signs, authenticates or encrypts anything, and this package adds
no key material, no random source and no constant-time comparison that upstream
does not already have.

It does carry a SHA-256 implementation, `sha2.c`/`sha2.h`, reached through
`ikey_dll.c:60` to compute the two InChIKey extension hashes. This fork makes
no claim about those bytes being side-channel hardened, and none about the
key-hashing step being suitable for password storage. `stb_sprintf.h` is a
formatting library, not a random source. The 27-character InChIKey is a hash of
an identifier for lookup, not a secret.

## See also

* [`UPSTREAM.md`](UPSTREAM.md) — what the pin is, what is compiled, and what
  the integrity record does and does not establish.
* [`UPSTREAM.sha256`](UPSTREAM.sha256) — the integrity record itself.
* [`README.zig.md`](README.zig.md) — how to build, import and call the package.
* [`CHANGELOG.md`](CHANGELOG.md) — numbered fork-only divergences.