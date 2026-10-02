# UPSTREAM.md — what this fork is a fork of

## Upstream

| | |
|---|---|
| Project | InChI, the IUPAC International Chemical Identifier; this fork builds its `libinchi` API library |
| Canonical repository | `https://github.com/IUPAC-InChI/InChI.git` |
| Pinned ref | tag `v1.07.5` |
| Pinned commit | `11a87982bb518f57ac013f0b258c283655e1ea1d` |
| Version of the C library built here | `1.07.5` |
| Licence | `MIT` for InChI itself, with three files in the shipped set under their own terms — see [the licences in this tree](#the-licences-in-this-tree-and-which-file-each-covers) |
| Copyright | `Copyright (c) 2024 IUPAC and InChI Trust` in the sources; `Copyright (c) 2024 InChI Project` in `LICENSE` |

Where each of those comes from, read out of the carried tree:

* The version is `INCHI-1-SRC/INCHI_BASE/src/bcf_s.h:52`, which reads
  `#define CURRENT_VER "1.07.5"`. That string is the software version, and it is
  what the identifier's own version string derives from. `build.zig.zon`
  carries `1.7.5`, because a semantic version cannot hold the leading zero of
  `1.07`; `build.zig:204-209` refuses to configure when that version and this
  pin disagree, so a version bump is a decision someone has to take rather
  than a side effect of a merge. Two other version strings exist upstream and
  neither is the software version: `INCHI_BASE/src/mode.h:258` defines
  `INCHI_VERSION "1"`, which is the version of the **InChI standard** and
  appears in every identifier as the `1S` after the equals sign, and
  `INCHI-1-SRC/INCHI_API/libinchi/src/CMakeLists.txt:3` says
  `project(LibInChI_API VERSION 1.7)`. There is no `inchi_version.h` and no
  `.h.in` anywhere in the tree: upstream generates no version header, and none
  is invented here.
* The licence is `LICENSE`, the MIT License in full, and it is restated in the
  header of every one of the 100 source and header files that carry the MIT
  notice. The same MIT grant appears verbatim in
  `INCHI-1-SRC/INCHI_BASE/src/inchi_api.h:7-27` and `ixa.h:7-27`, the two
  headers a consumer includes.
* The copyright line is not uniform upstream and this fork does not make it
  so. `inchi_api.h:9` and `ixa.h:9` say `Copyright (c) 2024 IUPAC and InChI
  Trust`, followed by the acknowledgement that the code was developed under
  the auspices of IUPAC, originally at NIST, with modifications by IUPAC and
  the InChI Trust (`inchi_api.h:29-37`); `LICENSE:3` says `Copyright (c) 2024
  InChI Project`. Both are upstream's bytes and both travel.
* Upstream describes its own API in `inchi_api.h` and `ixa.h`. The header
  declares 35 public functions in three blocks: `inchi_api.h:835-1146` is the
  `Get*`, `Free*` and `Check*` surface, `inchi_api.h:1311-1393` is the
  `INCHIGEN_*` generator handle API, and `inchi_api.h:1402` is
  `MakeINCHIFromMolfileText`. `ixa.h` adds the IXA handle API, 355 `IXA_`
  declarations of its own.

**Tag signature: not verified here.** No signing key was consulted while this
file was written and no git command was run at all, so nothing here is an
observation of the clone's own state. Treat the commit id and the archive
digest below as the provenance anchors, not as a signature check.

## The licences in this tree, and which file each covers

The InChI library is MIT. Three files inside the shipped set are not, or are
not unconditionally, and saying "the whole package is MIT" would be wrong in
three different ways:

| File | Its own terms | What it is |
|---|---|---|
| `INCHI-1-SRC/INCHI_BASE/src/sha2.c`, `sha2.h` | MIT, **but** `sha2.h:12-13` reads "this licensing is only valid in combination with the InChI software package, for all other cases contact Paul Bakker" | the FIPS 180-2 SHA-256 the InChIKey extension hashes use; `sha2.h:4-5` credits `Copyright (C) 2010 Paul Bakker`, originally written 2003-2006 by Christophe Devine |
| `INCHI-1-SRC/INCHI_BASE/src/stb_sprintf.h` | dual: MIT (`ALTERNATIVE A`, `Copyright (c) 2017 Sean Barrett`) or public domain (`ALTERNATIVE B`, Unlicense) | stb_sprintf 1.10, included by `bcf_s.c`, `ichimak2.c` and `mol_fmt3.c` |
| `INCHI-1-SRC/INCHI_BASE/src/tbb/tbbmalloc_proxy.h` | `Apache-2.0`, `Copyright (c) 2005-2018 Intel Corporation` | the Intel TBB allocator proxy; **carried and never compiled here** — nothing in the shipped set includes it (see below) |

`INCHI-1-SRC/INCHI_BASE/src/ikey_dll.c:45-47` attributes the same SHA-256 to
`Copyright (C) Brainspark B.V., see files sha2.c, sha2.h`, which is a third
attribution for the same two files. That inconsistency is upstream's and is
recorded here rather than resolved; nothing in this fork edits either file.

Of the 105 files in the two shipped directories, 100 carry the MIT notice.
The five that do not are `sha2.c`, `sha2.h`, `tbb/tbbmalloc_proxy.h`,
`CMakeLists.txt` and `readme.txt`. `NOTICE.md` states the obligations that
follow from each.

## Archive receipt

The workspace delivery record `local://foundation-expansion-source-archives.json`
holds a SHA-256 receipt for the deterministic `git archive` stream of the
**full upstream tree** at that commit. For this library it reads, verbatim:

```
55382c70314a01a9d2f3a18f0833a44c352d7332884f614f28cbb1d40c17d5f6  -
```

The trailing `-` is `sha256sum`'s name for standard input: the digest is of
the archive stream as it was piped past the hasher, not of any file in this
repository, and not of the subset this package ships. It is recorded here so a
later re-fetch can be compared against the same bytes. It cannot be checked
against [`UPSTREAM.sha256`](UPSTREAM.sha256) directly — that file holds 109
records, not the whole tree — and this fork does not pretend the two are
comparable.

The companion record `local://foundation-expansion-sources.json` names the same
repository, ref and commit, and records the licence as `MIT`. That is the
summary; the table above is the detail the summary omits.

## Import mechanism

A full clone of the canonical repository, so upstream's Git history is present.
The workspace delivery record states that every fork in this wave keeps the
upstream remote named `upstream`, a local `main`, and complete upstream history.
This fork adds no patch series on top of that history: the Zig package is a set
of new files in new regions. Exactly three files in the tree are edited in
place. One is `.gitignore`, which gains appended ignore entries and is
therefore deliberately outside the integrity record (see
[`NOTICE.md`](NOTICE.md)). The other two are upstream C source files,
`INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c`, each patched once for a stated reason
and nothing else; see
[The two patched source files](#the-two-patched-source-files). Every other
upstream source file, header, build file, licence text and document is
byte-identical to the pin, and none is regenerated.

## What this fork is

A Zig package that compiles upstream's own `libinchi` from the two source
directories in this repository and publishes a Zig facade over the translated
`INCHI_BASE/src/inchi_api.h`. Nothing of the InChI algorithm is reimplemented,
re-derived or reconfigured: no canonicalisation step is restated, and nothing
is downloaded at build time. Two upstream source files are patched. The
`ichiparm.c` patch is four kinds of edit and nothing else: a seven-line
disclosure comment and two
string-literal macros inserted above `HelpCommandLineParms` (nine lines, 2700-2708),
the wall-clock argument rewritten in both mutually exclusive branches of the
usage banner, and one existing comment line's format string corrected. That last
one takes an accidental nested-comment delimiter out of a disabled block; the
argument rewrites take a wall-clock stamp out of a help banner. The
`ichicano.c` patch is two inserted lines and no changed line: one include is
moved below `#include "mode.h"`, which is the header that defines the macro its
guard tests, and wrapped in that guard, whose only two readers in this file are
already behind the same macro. No chemistry,
no ABI, no allocator, no option string and no timeout behaviour is touched by
either. Each patch is written out in full below, against upstream's own digest
for its file, and the first one's scope as observed is quoted from the `363`
diff receipt named below.

### What is compiled, and with which switches

**60 translation units**, which is every `.c` file in the two shipped
directories: 6 in `INCHI-1-SRC/INCHI_API/libinchi/src`, 6 in
`INCHI-1-SRC/INCHI_API/libinchi/src/ixa`, and 48 in
`INCHI-1-SRC/INCHI_BASE/src`. The list is written out file by file in
`build.zig:60-131` rather than globbed, and it was checked against the
directories: the sixty names in `build.zig` and the sixty `.c` files on disk
are the same set, with nothing in one and not the other. A glob would let a
unit enter the archive without a decision.

Those 60 units reach **42 of the 43 headers** in those directories by
`#include`. The one that none of them includes is
`INCHI-1-SRC/INCHI_BASE/src/tbb/tbbmalloc_proxy.h`: `mode.h:240` includes a
different file, `../../INCHI_API/tbb/tbbmalloc_proxy_for_inchi.h`, which lives
outside `build.zig.zon` `.paths` and so is not shipped, and only under
`USE_TBB_MALLOC` — which `mode.h:229` ships commented out — together with
`_WIN32`. It is carried because it is in the directory `.paths` names, and it
is compiled by nothing here.

Two further files sit in those directories without being compiled:
`CMakeLists.txt`, upstream's own build file for this target, and `readme.txt`,
two lines of upstream notes. Both travel because `.paths` names the
directories.

The list is upstream's, read out of
`INCHI-1-SRC/INCHI_API/libinchi/src/CMakeLists.txt:31-135`, with three honest
exceptions. That block also lists `${P_VC}/resource.h` at line 134 and, under
`WIN32 AND MSVC`, `libinchi.rc` and `libinchi.aps` at lines 138-141; none of
those three is shipped or compiled here, and `resource.h` is the header of the
Windows resource script rather than a C dependency, so nothing in this build
reaches it. The rest of the block is the sixty units above plus the headers
they include.

Flags every unit is compiled with:

* `-std=c11` is upstream's own level, from
  `target_compile_features(libinchi_compiler_flags INTERFACE c_std_11)`
  (`src/CMakeLists.txt:6`) and `C_OPTIONS = -std=c11 -O1 -c
  -fno-strict-aliasing` (`libinchi/gcc/makefile:123`). It is pinned rather than
  left to the compiler's default so an upstream source change cannot become a
  build break through a default bump.
* `-fno-strict-aliasing` is upstream's, in both of those places. It is kept
  here for the reason upstream keeps it: the core compiles stb_sprintf v1.10,
  whose formatter reads its arguments with `va_arg` as `stbsp__uint32` and as
  pointers of several different types, and the InChIKey code carries SHA-256
  digests in two `unsigned char[32]` buffers (`ikey_dll.c:126-127`). Those
  accesses are exactly the ones strict aliasing permits a compiler to reorder
  or discard, and the symptom is a wrong InChI string with no diagnostic
  anywhere.
* Upstream also passes `-O1` and `-Wno-all`
  (`src/CMakeLists.txt:11`). The optimisation level here is the build's own
  `-Doptimize` mode rather than a hard-coded `-O1`, and warnings stay enabled
  so that a real defect in a future re-sync is visible instead of silenced.

Macros every unit is compiled with, from
`target_compile_definitions(libinchi PRIVATE ...)`
(`src/CMakeLists.txt:154-158`) and `libinchi/gcc/makefile:129`:

* `TARGET_API_LIB=1` and `COMPILE_ANSI_ONLY=1`. They select the API-library
  build of InChI rather than the stand-alone executable or the `wInChI`
  library build, and they decide which declarations the exported headers
  expand to: `INCHI_API`, `EXPIMP_TEMPLATE` and `INCHI_DECL` are all defined
  from them at `inchi_api.h:691-709`, and they are what stand between a static
  archive and a `__declspec(dllimport)` declaration on Windows.
  `COMPILE_ANSI_ONLY` also selects the timing branch in
  `INCHI_BASE/src/ichicano.c` — the `clock()`/`CLOCKS_PER_SEC` code at lines
  97-326 rather than the `struct _timeb`/`_ftime` code at lines 327-414.
* `fPIC`, also in that CMake list, is deliberately **not** defined here. It is
  inert in the sources, and position-independent code is a property of the
  link, not of this C; this package builds a static archive.

`translate.h` defines the same two macros on the translation's own line, so
the header and the compile cannot drift apart; `-fsys=inchi` generates the
same pair into a wrapper around `<inchi_api.h>` from the same
`core_macros` table (`build.zig:479-501`).

The C core module is created with `.sanitize_c = .off` written out explicitly
at `build.zig:453`. That is an argument this package passes to
`b.createModule`, not an inference about what the toolchain would do by
default, and it is there because the C core's own wraparound and narrowing
arithmetic — `FullMaxClock`/`HalfMaxClock` built from `(clock_t)(-1)` at
`ichicano.c:126-127` — expect the Debug behaviour a C sanitizer changes.

### The IXA backend, and why it is in the list

The six `INCHI-1-SRC/INCHI_API/libinchi/src/ixa/*.c` units are compiled and
their six headers ship. IXA is the "InChI Extensible API": a handle-based
builder — status handle, molecule handle, InChI builder handle, atom ids — that
is a different shape from the struct-and-free `Get*` API in the same library
and lives in its own translation units.

Nothing is dropped for being hard to wrap. The Zig facade does not wrap IXA,
and `zig/root.zig:63-68` says why: `pub const c` is the complete translated
declaration set, so `IXA_STATUS_Create`, `IXA_MOL_*`, `IXA_INCHIBUILDER_*` and
the rest are reachable with upstream's behaviour and none of the facade's
contracts. The build still has to compile the backend, because a consumer that
goes through `c` links against this archive; leaving `ixa/` out would ship a
library whose public header declares a handle API it cannot honour.

### The API surface this facade does not wrap

`pub const c` is also how a caller reaches `MakeINCHIFromMolfileText`, the
`INCHIGEN_*` generator handle family, `GetINCHIEx` and the `GetStructFrom*Ex`
pair — and through the `inchi_InputEx` those two take, the polymer and V3000
extended input — plus the whole 0D-stereo surface. Two of those deserve a
warning rather than a mention:

* `GetINCHIEx` rewrites `*` element names to `Zz` **in place**
  (`inchi_dll.c:330-336`). It is the one wrapped-looking entry point that
  writes through the caller's atom array, which is why `Molecule.atoms` is
  `[]const Atom` and why `GetINCHIEx` is deliberately not wrapped
  (`zig/root.zig:224-231`).
* `inchi_Input.atom` is declared `inchi_Atom *`, not `const inchi_Atom *`. The
  narrow `@constCast` the facade applies to hand the caller's array to C is
  forced by that declaration, and its soundness rests on the fact that the
  entry points the facade does wrap copy every field out before using any of
  it (`inchi_dll.c:252-256`, `inchi_dll.c:1933-1936`) and write none of it
  back. That is a claim about upstream's code, and `zig/root.zig` names the
  line numbers it rests on.

## What is upstream's and is shipped unmodified, and the two files that are not

Everything named in `build.zig.zon` `.paths` that this fork did not write —
**except `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c`**, which are patched on purpose
and written out in [The two patched source files](#the-two-patched-source-files).

| Path | What it is |
|---|---|
| `INCHI-1-SRC/INCHI_BASE/src` | 86 files: the canonicalisation and InChIKey core, the molfile readers and writers, the bundled stb_sprintf 1.10, the SHA-256 implementation, and the two public headers `inchi_api.h` and `ixa.h` that the build installs |
| `INCHI-1-SRC/INCHI_API/libinchi/src` | 20 entries, 19 files: the `Get*`/`Free*`/`Check*` API units, the six IXA units, their headers, and upstream's own `CMakeLists.txt` for the target |
| `LICENSE` | the MIT License text, verbatim |
| `README.md` | upstream's project README, verbatim |
| `INCHI-1-SRC/INCHI_API/tbb/LICENSE` | upstream's own full Apache-2.0 text, shipped so the Intel TBB header that travels inside `INCHI-1-SRC/INCHI_BASE/src/tbb/` travels with its terms, and hashed in `UPSTREAM.sha256` like every other upstream file the package ships |

`.gitignore` is upstream's file too, and it is in this repository but not in
`.paths`; the fork appends to it, so it is deliberately **not** in the
integrity record. See [`NOTICE.md`](NOTICE.md) and `FORK-NOTES.md`.

## The two patched source files

Two upstream files in this package are not upstream's byte for byte:
`INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c`. Each carries one patch against the
pin, on purpose, and each is written out in full below. The `ichiparm.c` patch
landed before the full cross-platform matrix gate existed and is covered by its
own receipts. The `ichicano.c` patch was written twice — the first version put
its guard where upstream had the include, above the header that defines the
macro, and guarded nothing; both versions and the probes that separate them are
under its own heading. The `ichiparm.c` patch has been built, installed and run
since it landed. The `ichicano.c` patch has been compiled in both versions: the
first by the 53-cell matrix and the `2026-10-02` wave, the second — the one
shipped — by the six-target `check` baseline and the stable native wave.

### `ichiparm.c` — the build stamp and the comment

Upstream's digest for the file — the baseline the patch is measured against:

```
eb3516115a1d25776f823de800d1c61cf0161e5bedbecac3511cd21ec0de2478  INCHI-1-SRC/INCHI_BASE/src/ichiparm.c
```

The file as this fork now ships it, which is the line `UPSTREAM.sha256`
carries:

```
74302e26597450060b8341a569f4fd8a07813aadce1f05e9b3507c34980cdd3a  INCHI-1-SRC/INCHI_BASE/src/ichiparm.c
```

110611 upstream bytes became 111263 current bytes. The earlier 111277-byte
patch had digest `54797698e636e2d556520fa1d7ccb995b10d9acbf3c58015cdd2f427e6b1705c`;
only three existing disclosure-comment lines were clarified since it, with
no noncomment byte or source-line count changed. Of the 109 lines, **108 are upstream
records**: 106 byte-identical to the pin, and `ichiparm.c` plus `ichicano.c` the
two exceptions once the second patch is counted. The
109th line, `testdata/pubchem_known_answers.tsv`, is not upstream's at all, so
"every other one of the 109 recorded files is byte-identical to the pin" would
be false by one line. The native tree is these two disclosed single-file
exceptions and not a pristine copy.

**The first deviation is scoped, and the scoping is observed.**
`git diff 11a87982bb518f57ac013f0b258c283655e1ea1d -- INCHI-1-SRC LICENSE`
(`local://foundation-expansion-inchi-authorized-single-native-file-deviation-363.log`,
exit 0, host `gruenau8`, 2026-10-02T00:20:07.911Z to 00:20:13.064Z) prints a
diff over **one** path, `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c`, in three
hunks: the 2597 comment correction, the nine-line insertion at 2699, and the two
argument rewrites. It carries no `--exit-code`, so its exit 0 says the query ran
and nothing more, and it is **not** a pristine proof: it says nothing about the
other paths outside `INCHI-1-SRC` and `LICENSE`. The earlier
`git diff --exit-code … -- INCHI-1-SRC LICENSE` receipt named in
`README.zig.md` (`-267`) was green while the tree was unmodified and is a
statement about the pre-patch tree only.

**Why it exists.** Zig 0.16.0's ReleaseSafe C backend promotes warnings to
errors, and two constructs in this file are refused there. Both are recorded,
with their receipts, in `CHANGELOG.md` §24 and §28.

**The two changes, in full.**

1. **The disabled block comment.** `ichiparm.c:2597` sits inside the
   `/* … */` block running from line 2594 to line 2599, which disables an
   alternative timeout message. Its format string held the two characters `/*`:

   ```
   inchi_ios_eprint( log_file, "Timeout per structure: %lu/*.%03lu sec\n", seconds, milliseconds); -- djb-rwth: ignoring LLVM warning
   ```

   A `/*` inside a block comment is an accidental nested-comment opener, and
   the compiler warns on it. The patch reads `%lu.%03lu`: the `/` is deleted
   and the `*` becomes the `.` the sentence plainly meant. The line is inside a
   comment, is compiled nowhere, and is reachable from no option, path or
   timeout — a comment correction with no effect on any behaviour.
2. **The build stamp.** `ichiparm.c:2712` and `ichiparm.c:2718`, in pre-patch
   numbering, are the two mutually exclusive branches of the usage banner in
   `HelpCommandLineParms`: the `#ifdef TARGET_EXE_USING_API` branch and the
   ordinary one. Both expanded the compiler's build-date and build-time macros,
   so the help text of two builds of these same sources differed and no two
   built artefacts were byte-comparable. Both now pass two string literals,
   defined immediately above the function:

   ```c
   #define INCHI_BUILD_SOURCE_TAG "v1.07.5"
   #define INCHI_BUILD_STAMP_WHEN "(no build timestamp)"
   ```

   The first is the pinned upstream tag; the second says outright that no build
   time is recorded. Neither is a build timestamp, and nothing here claims one.
   **The format string is untouched**: the two replacements land in exactly the
   `%s` and `%-s` conversions the macros filled, so the argument count, order
   and types are as upstream left them — a string literal decays to `char *`,
   and so did both macro expansions. The banner line as observed, from
   `GetINCHI(empty)` on the patched tree built against the installed archive,
   reads
   `Linux 64-bit Build (gcc Clang 21.1.0) of v1.07.5 (no build timestamp)`
   — the platform and compiler wording comes from upstream's own macros and is
   specific to the machine that produced it
   (`…-inchi-patched-installed-banner-smoke-385.log`); the two substituted
   arguments are the pinned tag and the literal no-timestamp string, and neither
   is a build time.

**What did not change.** No chemistry, no canonicalisation step, no ABI, no
allocator, no option string, no timeout value, no default, no compiler flag and
no build mode. The file's own comment above the two `#define`s says so in
the source, for anyone reading the C rather than this document. `ichicano.c` is
patched too, but by the second and entirely separate patch below, which touches
no chemistry either.

**Line numbers move, by nine.** The insertion is nine lines — a seven-line
comment at 2700-2706 and the two `#define`s at 2707-2708. It sits below the
`/****…****/` separator that was already at 2699, so every line of this file
from `HelpCommandLineParms` down is cited nine lines higher here than upstream
cites it, and nothing above the separator moves at all. Checked on the file
itself: `HelpCommandLineParms` 2700 → 2709, `#ifndef TARGET_API_LIB`
2878 → 2887, `OpenFiles` 2880 → 2889. So upstream's 2712 and 2718 are 2721 and
2727, and upstream's 2901, 2910 and 2919 are 2910, 2919 and 2928, while
upstream's 2597 is still 2597. Line numbers elsewhere in this package that cite
this file cite its pre-patch text, and are not restated here.

**The three stamps left alone, and why.** `OpenFiles` prints the same banner at
2910, 2919 and 2928, and all three are inside the `#ifndef TARGET_API_LIB`
block that opens at line 2887 and runs to the end of the file.
The macro is named in `core_macros` at `build.zig:166-169` — `.{ "TARGET_API_LIB",
"1" }` at line 167 — and `build.zig:456` applies it with `addCMacro` to the one
C module created at `build.zig:444`, which all three source groups are then
added to at 457-459. So that block is
preprocessed away in every configuration this package builds —
`-fsys=inchi` compiles no C of this tree at all. Those three sites are
upstream's bytes here. The authorisation named the one expansion ReleaseSafe
refused, and widening a bounded authorisation is not this fork's call.

**Licence.** Upstream's MIT grant covers modification, and its notice is in
`LICENSE` and in this file's own header, both unchanged and both shipped. The
nine lines this fork adds carry no licence of their own; see
[`NOTICE.md`](NOTICE.md).

### `ichicano.c` — the guarded include, placed after `mode.h`

Upstream's digest for the file — the baseline this patch is measured against:

```
5c031a2b441dc08509f75fe22e4b6ecddf285ada625b4a69cf77d2920d42f891  INCHI-1-SRC/INCHI_BASE/src/ichicano.c
```

The file as this fork now ships it, which is the line `UPSTREAM.sha256` carries:

```
9a0998a3a41f62508e755d9411bf3c78b2b7b1ae63edcea7a40c55307130d98b  INCHI-1-SRC/INCHI_BASE/src/ichicano.c
```

107394 bytes became 107427, and 2742 lines became 2744. The patch is two
inserted lines and no changed line. Upstream's `ichicano.c:45-47`:

```c
#include <time.h>
#include <sys/timeb.h>
#include <limits.h>
```

and the file as shipped here, at lines 44-52:

```c
#include <ctype.h>
#include <time.h>
#include <limits.h>

#include "mode.h"
#ifndef COMPILE_ANSI_ONLY
#include <sys/timeb.h>
#endif
#include "ichicano.h"
```

**Where the guard sits is the patch.** `mode.h:197-201` defines
`COMPILE_ANSI_ONLY` itself, for every non-Microsoft compiler and for
`TARGET_API_LIB` and `TARGET_EXE_USING_API`:

```c
#if ( !defined(_MSC_VER) || defined(TARGET_API_LIB) || defined(TARGET_EXE_USING_API))
#ifndef COMPILE_ANSI_ONLY
#define COMPILE_ANSI_ONLY
#endif
#endif
```

The first version of this patch left the guarded include at upstream's own
position 46, and `#include "mode.h"` was still three lines below it, at 51. At
that point in the translation unit the macro was undefined, so
`#ifndef COMPILE_ANSI_ONLY` was true, the include was processed exactly as
upstream left it, and the guard did nothing at all. That is observed, not
inferred: `zig cc -target aarch64-macos -E -P -std=c11
-fno-strict-aliasing -DTARGET_API_LIB=1 ichicano.c` fails with
`'sys/timeb.h' file not found`, and the same command with
`-DCOMPILE_ANSI_ONLY=1` added succeeds, with the command-line definition in
front of the header's own
(`local://foundation-cross-test-inchi-guard.json`; the ANSI run's preprocessed
output is kept at `scratch/inchi-guard-before-ANSI.c`). Moving the block below
`#include "mode.h"` puts the header's definition in scope first, so the guard
finally sees the value this build will compile with.

**Why it exists: an observed failure, and history.** `zig build check` for
`aarch64-macos-none` was red on the tree as it stood upstream, on the receipt
named below. It is **green now, re-run at that same target** —
`Build Summary: 6/6 steps succeeded`, exit 0, on the shipped file
(`local://foundation-cross-test-baseline-inchi-aarch64-macos-none.log`,
2026-10-02T06:22:24Z) — so the red row is kept as the state it was in and not
as the state of this file. `inchi/CHANGELOG.md` §29 quotes its receipt —
`…-authorized-patch-cross-…-367.log` through `…-372.log`, five of the six green
at 6/6 steps and this one exit 1 with
`ichicano.c:46:10: error: 'sys/timeb.h' file not found` and
`Build Summary: 2/6 steps succeeded (1 failed)`. The header is missing on this
compiler for a reason that is readable out of the compiler itself, not a guess:
`std.zig.LibCDirs.detectFromBuilding` (`lib/std/zig/LibCDirs.zig:169-181`) gives
every Darwin-family target — the branch is `target.os.tag.isDarwin()`, which
covers `.maccatalyst` as well as `.macos` — exactly one libc include directory,
`lib/libc/include/any-darwin-any`, and that directory has no `sys/timeb.h`.
`std.zig.Target.Os.Tag.isDarwin` (`lib/std/Target.zig:79-86`) names
`.maccatalyst` and `.macos` in the same arm, so the four Apple cells of the
published matrix — `aarch64-macos`, `x86_64-macos`, `aarch64-maccatalyst` and
`x86_64-maccatalyst` — all take that one directory. The other nine are the
OpenBSD cells: neither `generic-openbsd` nor any of the ten `*-openbsd-*`
architecture directories carries the header.

The header is not absent from every non-Windows libc, and an earlier draft of
this file said so. Seven `zig cc -E -H -include sys/timeb.h -x c /dev/null`
probes settle it (`local://foundation-cross-test-timeb-header-availability.json`,
exit 0 unless noted): present on `x86_64-linux-gnu`, `x86_64-linux-musl`,
`x86_64-netbsd` and `wasm32-wasi`; present on `aarch64-freebsd` together with a
`#warning` that `<sys/timeb.h>` is deprecated; and absent —
`'sys/timeb.h' file not found` — on `aarch64-macos` and `x86_64-openbsd` only.
So the glibc and musl Linux cells and `wasm32-wasi` preprocess the include as it
stands, and the Darwin and OpenBSD cells cannot. The Darwin half of that is the
directory the paragraph above names. Those seven are the only cells measured;
"thirteen of the fifty-three" is a reading of the toolchain's directory list,
not a count anyone ran, and the two measured absence claims are the two above.

**Why this guard and not another.** The guard is exactly the condition the
guarded code is already behind, in this same file. In pre-patch numbering,
`ichicano.c:95` opens `#ifdef COMPILE_ANSI_ONLY`; the `#else` at `ichicano.c:325`
closes that block at `ichicano.c:412`. Both — and only — readers of the header's
declarations sit inside that `#else`: `InchiTimeGet` declares
`struct _timeb timeb;` and calls `_ftime` at pre-patch 332-335, and
`bInchiTimeIsOver` does the same at pre-patch 395-402. Those four lines — 334,
335, 397 and 402 as shipped here — are every occurrence of `struct _timeb` and
`_ftime` in the file. So with
`COMPILE_ANSI_ONLY` defined the header supplies nothing any surviving token
needs, and with it undefined the header is included exactly as upstream left it.
There is no behaviour to preserve across the guard, because the behaviour was
already on the other side of it.

**Upstream's own header already says this.** `ichitime.h:56` — the header that
declares `inchiTime` for the same file — carries
`/*#include <sys/timeb.h>*/`, the same include, commented out, inside its own
`#ifdef COMPILE_ANSI_ONLY` branch. The non-ANSI branch there is a different
struct, two members rather than one, carrying a millisecond field that the ANSI
branch's `struct tagInchiTime` does not (`ichitime.h:69-73` against `:60-62`),
which is the same ABI split the guard above follows. Upstream defines the macro
for the library target in every build definition it ships:
`INCHI_API/libinchi/src/CMakeLists.txt:154-158` and
`INCHI_API/libinchi/gcc/makefile:129`, and this build names both in
`core_macros` (`build.zig:166-169`).

**What did not change.** No declaration, no expression, no macro and no token in
any configuration upstream compiled. With `COMPILE_ANSI_ONLY` undefined the
include is still there, where it was, and the preprocessed output is upstream's;
with it defined the region the guard wraps was already excluded, so the header
supplied nothing and dropping the include is what the macro asks for. No
canonicalisation step, no ABI, no allocator, no option string, no default, no
compiler flag, no build mode, no diagnostic suppressed and no source file
removed. This package passes `COMPILE_ANSI_ONLY=1` on the command line itself,
so for this package's own build the reorder changes no token; what it fixes is
the configuration upstream's header describes and a consumer reaches by
defining only `TARGET_API_LIB`.

**Line numbers move, by two, from line 46 down.** The two inserted lines are
both inside the first fifty, so every line from `#ifdef COMPILE_ANSI_ONLY` to
the end of the file is cited two lines higher here than upstream cites it, and
nothing above line 45 moves. Checked on the file itself: `#ifdef
COMPILE_ANSI_ONLY` 95 → 97, the `#else` 325 → 327, the closing `#endif`
412 → 414, `InchiTimeGet`'s `struct _timeb` 332 → 334 and `bInchiTimeIsOver`'s
395 → 397. The move is confined to lines 45-52, so those are the same numbers
the first version of this patch gave; the guard itself reads at 49-51 where it
read at 46-48 before. Citations to the timing branch and clock constants above
use the shipped post-patch line numbers.

**Licence.** Same as the patch above: upstream's MIT grant covers modification,
the notice is in `LICENSE` and in this file's own header, both unchanged and
both shipped. The two lines this fork adds carry no licence of their own; see
[`NOTICE.md`](NOTICE.md).

**Status: compiled on every build gate this package is measured by.** The
shipped file — the reordered one — is green on the six-target `check` baseline
in **all six** cells of the workspace's 48-cell explicit-target round, exit 0 on
each, `Build Summary: 6/6 steps succeeded` on each, between
`2026-10-02T07:23:30.237Z` and `2026-10-02T07:23:32.431Z`, `complete: true`,
`unrun_cells: []`, including the `aarch64-macos-none` cell that was red before
the patch (`local://foundation-cross-test-final-baseline.json`); green in the
stable native wave in both modes: `test smoke install -Doptimize=Debug`, 16/16,
11/11 steps; `test smoke -Doptimize=ReleaseSafe`, 16/16, 9/9 steps; and the
`consumer` build through `dep.module("inchi")`, 6/6 steps — all exit 0, all on
this arrangement (`local://foundation-cross-test-stable-native.json`); and green
across the full 53-cell `cross-test` matrix **on this arrangement**: run
`20261002-071259-33035-20483`, generated `2026-10-02T07:12:59Z`, harness
`exit_code: 0`, `target_count: 53`, counts `pass 20`, `fail 0`, `build_only 33`,
`partial 0` — 20 cells executing 16 tests each, 33 compiled only with
`reason: runtime_unavailable`, and no foreign BSD, macOS, Mac Catalyst, Windows
or WASI binary executed in any of them
(`local://foundation-cross-test-final-current-inchi.json`). The earlier 53-cell
run, `local://foundation-cross-test-matrix-inchi.json`, compiled the first
placement and is history for this one.

**Two closures are the driver's, and this file states no result for either.**
The first is the whole-record `sha256sum -c UPSTREAM.sha256` replay over the
digest re-derived above: the two integrity receipts named under
[Integrity](#integrity) verify earlier states of that record, and the current
replay is recorded outside this package, in the root ledger's `FORKS.json` under
`cross_test_wave`. The second is the final filtered package round, whose result
and identity live in that ledger's `cross_test_wave.materialized_packages.inchi`
and in `local://foundation-cross-test-package-regression.json`: a hash taken over a copy
of this file cannot be the identity of the package this file is written into.
`zig build -fsys=inchi` is unrun and no result is claimed for it. **No CI was
executed for this patch and no workflow result is reported here.**

## What is carried but is not part of the package

These stay in this repository for provenance and for a re-sync diff. They are
not in `.paths`, the build never reads them, and a dependent that fetches this
package does not receive them:

| Path | What it is |
|---|---|
| `INCHI-1-SRC/INCHI_EXE/`, `INCHI-1-SRC/INCHI_BASE/redundant/`, `INCHI-1-SRC/INCHI_API/demos/`, `INCHI-1-SRC/INCHI_API/bin*/`, `INCHI-1-SRC/INCHI_API/tbb/` | the `inchi-1` executable, its prebuilt binaries, the demo programs, superseded sources and the TBB allocator wrapper upstream's own sources include under a Windows-only flag. **One file of the last directory is now shipped** — `INCHI-1-SRC/INCHI_API/tbb/LICENSE`, listed above; the wrapper itself, its `Windows/` subdirectory and `scalable_allocator.h` are not in `.paths` |
| `INCHI-1-SRC/INCHI_API/libinchi/gcc/`, `.../vc14/` | upstream's gcc makefiles, its version script and its Visual Studio project; the makefile is the source of the `-std=c11`, `-fno-strict-aliasing`, `-DTARGET_API_LIB -DCOMPILE_ANSI_ONLY` and `libinchi` spellings this build quotes |
| `INCHI-1-SRC/readme.txt`, `cmake_build_tool.sh`, `cmake_build_tool.bat` | upstream's notes and its own CMake driver scripts |
| `INCHI-1-DOC/`, `INCHI-1-TEST/` | the manuals, release notes, FAQ and the Python/gtest distribution including the html report generator |
| `CMakeLists.txt`, `Doxyfile` at the repository root | upstream's top-level build and documentation configuration |
| `.github/`, `.devcontainer/`, `.editorconfig`, `.gitattributes`, `.dockerignore` | upstream's CI, editor and container configuration |

Upstream's own CI is left exactly as it arrived and is not retargeted at this
fork's infrastructure. This fork's workflow is `.github/workflows/verify.yml`,
a new file, which is also not in `.paths`.

## Integrity

`UPSTREAM.sha256` holds **109** records: the SHA-256 of every upstream file the
package ships (106 files — the 105 across the two source directories, plus
upstream's own `INCHI-1-SRC/INCHI_API/tbb/LICENSE`), the upstream MIT text,
upstream's README, and the one independent fixture the tests embed. One
`<hex>  <path>` line each, in `sha256sum` format. Check it with:

```
sha256sum -c UPSTREAM.sha256
```

**It was run over all 109 before the first patch was made.** Exit 0, 109 records,
no
failures, with `INCHI-1-SRC/INCHI_API/tbb/LICENSE: OK` among them
(`local://foundation-expansion-inchi-immutable-source-complete-legal-109-240.log`).
That receipt is history for exactly two of its 109 lines: the `ichiparm.c` and
`ichicano.c` digests it verified were upstream's, and
[the patches](#the-two-patched-source-files) have replaced those lines with the
digests of this fork's bytes. The other 107 lines are byte-identical to what
that receipt verified, so it remains the evidence for those and only those.

**The record as of the first patch was covered by two current receipts.**
`sha256sum -c
UPSTREAM.sha256` in this repository (`…-inchi-authorized-patch-integrity-109-364.log`)
read 109 records, 109 `: OK` lines, no failures, exit 0, at
2026-10-02T00:20:14.216Z — 109 of 109, the patched `ichiparm.c` line included.
The same command in the `.paths`-filtered copy the driver materialised from a
current `zig fetch` was green the same way: 109 records, 109 `: OK` lines, exit 0
(`…-inchi-current-filtered-package-integrity-388.log`, `taskset -c 40-47
sha256sum -c UPSTREAM.sha256`, 2026-10-02T00:49:09.694Z to 00:49:11.277Z).
Between them the two receipts answered both halves: the record validated against
the then-patched tree in a clone, and against the bytes a dependent then
received.

**Both are history for the record as it now stands.** The second patch changed
one line of `UPSTREAM.sha256`, and its correction changed that same line again;
neither receipt covers the file as it is written today, because each verified an
`ichicano.c` line holding a digest this record no longer names. No
`sha256sum -c` result is quoted here for the current record. Only the
`ichicano.c` line was re-derived, twice, from the file's own bytes; the other
108 lines are unchanged text in an unchanged order, so they are the same numbers
the two receipts verified. **The current whole-record replay is the driver's to
run and to record**, and it is recorded outside this package, in the workspace
ledger's `cross_test_wave` — so this file carries neither a status for it nor a
digest for the line.

The record covers the manifest again: the Apache-2.0 text the manifest ships
beside the Intel TBB header is hashed like every other upstream file, and no
shipped upstream file is outside the record. The current gate states for the
whole package live in [`README.zig.md`](README.zig.md) § Verification status; this
file does not repeat them.

**The 108-record runs are history.** Two earlier receipts are green over 108
records (`…-immutable-source-including-complete-Apache-license-221.log`,
byte-identical to `…-immutable-source-integrity-127.log`); they predate the
Apache digest, so they describe a record that did not cover the whole package
and are not evidence about the one that does.

Otherwise the path set is exactly the entries of `build.zig.zon` `.paths`
plus the fixture: because the record names only files `.paths` ships, the same
command works in a cloned repository *and* in an unpacked package fetched by a
dependent. **That half was observed against the record as it stood after the
first patch, in both places.**
`local://foundation-expansion-inchi-current-filtered-package-integrity-388.log`
runs `sha256sum -c UPSTREAM.sha256` in the copy materialised from
`zig fetch /vol/fob-vol7/mi19/gertullj/foundation-libs/inchi`
(`…-current-filtered-package-fetch-382.log`, exit 0, hash
`inchi-1.7.5-UwYuz6MpdgByZDArhdKwsbtU40zJ1by58jHDp1PElGg-`) and reads exit 0
with 109 `: OK` lines, `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c: OK` among them. A
consumer built against that same materialised copy is green in turn
(`…-current-filtered-package-consumer-389.log`, exit 0, `consumer ok`), so the
fetched package is not merely hash-valid but usable.

The earlier materialised receipts,
`local://foundation-expansion-inchi-materialized-package-integrity-333.log`,
`local://foundation-expansion-inchi-external-driver-package-fetch-324.log` and
`local://foundation-expansion-inchi-materialized-package-consumer-340.log`, are
all explicitly **pre-patch history**: `-333` read exit 0 with 109 `: OK` lines
at 2026-10-01T23:50:07.598Z, about thirty minutes before the `-364` run over
the patched record at 2026-10-02T00:20:14.216Z — adjacent calendar dates, a
short gap — and a fetched copy is a snapshot that cannot contain a later edit.
None of their `ichiparm.c` lines is carried forward. `-382`, `-388` and `-389`
spoke for the record and the package as of the first patch and are not carried
forward past the second one either, for the same snapshot reason plus the
changed `ichicano.c` line. The `.paths`-filtered copy those receipts describe
was also materialised before `cross-test.profile.sh` entered `.paths`, so the
fetched package they describe is not the package this tree now publishes. The
`#`-prefixed header of the file explains, per path, why anything is excluded.

**The record's own header agrees with its lines.** It states 109 records, names
`INCHI-1-SRC/INCHI_API/tbb/LICENSE` as the one upstream file added for the
Apache-2.0 terms with a line saying why, and excepts that path from the
"deliberately absent" list it shares with `INCHI-1-DOC/`, `INCHI-1-TEST/` and the
rest of `INCHI-1-SRC`. Prose and digests describe the same set. The header also
names `INCHI-1-SRC/INCHI_BASE/src/ichiparm.c` and
`INCHI-1-SRC/INCHI_BASE/src/ichicano.c` as the two of the 105 that this
fork patched, with upstream's digest beside each record's, so a reader who trusts
the prose and a reader who trusts the lines are reading the same set.

**How the digests were produced.** Each file was read as raw bytes with Bun's
`Bun.file(path).arrayBuffer()` and hashed with `crypto.createHash("sha256")`
from `node:crypto`. No shell hashing command and no git command was used to
produce them. The 108 records that are neither `ichiparm.c` nor `ichicano.c`
were written on
2026-10-01, and every one of them was then re-derived from the written file
with the same method and compared against it: 108 re-derived, 0 mismatches, 108
distinct paths. The 109th line, the Apache-2.0 text, was added afterwards and is
covered by the `sha256sum -c` receipt named above. The tree walk also reported
no symlinks and no non-regular entries under the two hashed roots — 105 regular
files and 2 directories — so every record is the digest of that file's own
bytes. The `ichiparm.c` and `ichicano.c` records are the two lines
[the patches](#the-two-patched-source-files) changed, and each was re-derived
from its patched file's own bytes after every other digest had been written. The
second derivation used a plain SHA-256 of the file's bytes and matched the
digest written into the record; that comparison is one file read against one
written line, and it is not a substitute for the whole-record check above.

**What the record establishes.** If it validates, the bytes the build compiles,
the licence texts a dependent receives and the fixture the tests read are the
bytes this record pins, and any later edit to one of those 109 files fails the
check loudly.

**What it does not establish.** It is not a signature, not a Git object id, and
not a re-derivation from commit
`11a87982bb518f57ac013f0b258c283655e1ea1d`: it is a hash of this working tree.
That the tree equals that commit rests on the import and on the archive digest
above, both of which the driver recorded, not on anything computed while
writing this file. Replaying the check against upstream is the driver's job and
needs a re-fetch:

```
git -C <clone> archive --format=tar 11a87982bb518f57ac013f0b258c283655e1ea1d | sha256sum
```

The output must read
`55382c70314a01a9d2f3a18f0833a44c352d7332884f614f28cbb1d40c17d5f6  -`,
and `sha256sum -c UPSTREAM.sha256` must then report 109 records and no
failures. Note what that pair of commands does **not** say: the archive digest
covers the whole upstream tree and the 109 records cover a subset of the files
upstream ships, so the two numbers are expected to differ. What a re-sync
should assert is that every file the record names still hashes to what it says,
which is the second command.

**Status: the current record is not quoted here, and the two receipts above are
its history.** `sha256sum -c UPSTREAM.sha256` read 109 records, 109 `: OK`
lines and no failures at both `-364` (this repository, first-patch tree) and
`-388` (the `.paths`-filtered copy of it). Since the second patch no
whole-record result is quoted in this file, so nothing about the current record
is claimed here as observed. The replay that covers it is the driver's to run
and to record, and it is recorded outside this package, in the workspace
ledger's `cross_test_wave`. What the record still does not establish is stated
immediately above and is not changed by any receipt.

## Synchronising with a new upstream release

1. `git fetch upstream`, check out the new tag, and read
   `INCHI-1-SRC/INCHI_BASE/src/bcf_s.h`'s `CURRENT_VER`; that string, not the
   tag spelling, is the version.
2. Replace the upstream files in place: the two `src` directories, `LICENSE`
   and `README.md`. Do not hand-patch upstream source to make a build problem
   go away. The two exceptions are recorded, measured against upstream's own
   digests and written out in
   [The two patched source files](#the-two-patched-source-files); a re-sync
   either carries them forward deliberately — re-checking both contexts against
   the new release, because both sets of line numbers move — or drops them and
   takes the red cells back. What is not acceptable either way is an unrecorded
   edit.
3. Re-read the licence grant in the new `LICENSE` and in
   `INCHI_BASE/src/inchi_api.h`, and re-check the three files in
   [the licence table](#the-licences-in-this-tree-and-which-file-each-covers):
   a release that moves or relicences `sha2.c`/`sha2.h`, `stb_sprintf.h` or
   `tbb/tbbmalloc_proxy.h` changes what this package may redistribute.
4. Re-read `libinchi/src/CMakeLists.txt` for the compile unit list and for the
   macros and flags, and `libinchi/gcc/makefile` for the same things as the
   non-CMake build sees them. If the unit list moved, `build.zig:60-131` is the
   list that has to move with it, file by file.
5. Regenerate `UPSTREAM.sha256` over the same path set with the same method and
   update the record count in its header comment and in this file.
   **The path set must be read from `.paths`, not remembered**: any upstream
   file a `.paths` entry adds needs a record line, or the record stops covering
   what the package ships. `INCHI-1-SRC/INCHI_API/tbb/LICENSE` is the case in
   point — added to `.paths` to close the Apache-2.0 gap, hashed as the 109th
   line afterwards, with its own header line explaining why it is there. Update
   the header's count and its exclusion list in the same change: a digest list
   whose prose under-counts itself is the one part of a record a reader trusts.
6. Re-check both patches against the new release before carrying either forward:
   `INCHI-1-SRC/INCHI_BASE/src/ichicano.c` and the headers it needs, on each
   platform, and `ichiparm.c`'s two banner branches. A new platform dependency
   shows up in the first before it shows up anywhere else.
7. Bump `.version` in `build.zig.zon` to the new string, update the pin in this
   file and in `README.zig.md`, and add one numbered `CHANGELOG.md` entry.

## See also

* [`NOTICE.md`](NOTICE.md) — attribution, the licence split, the MIT
  obligations that apply, every file this fork adds or edits, and the
  provenance of the independent fixture.
* [`README.zig.md`](README.zig.md) — how to build, import and call the package.
* [`CHANGELOG.md`](CHANGELOG.md) — numbered fork-only divergences.
* [`FORK-NOTES.md`](FORK-NOTES.md) — the problems met while doing this, and
  what was decided.
* [`UPSTREAM.sha256`](UPSTREAM.sha256) — the integrity record itself.