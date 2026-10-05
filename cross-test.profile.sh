# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
# See FORK-LICENSE.md for the full grant and the owner authorization behind it.

# cross-test profile for the InChI package.
#
# A settings-only profile. `cross-test` discovers this file at the project root,
# so an unqualified `cross-test` run in this repository reads it and a
# `--no-profile` run ignores it. Every name below is also a `cross-test`
# command-line flag or an environment variable, and the command line wins.
#
# What it deliberately does NOT contain, and why:
#
#   * No `CROSS_MATRIX` and no `TARGETS`. The published 53-platform Zig 0.16.0
#     Tier 1/2 table stays whole. This package has no operating-system refusal
#     of its own, so a cell that does not build is a cell whose C core does not
#     build, and narrowing the matrix here would hide it rather than explain it.
#   * No `cross_build_command`, `cross_artifact`, `cross_run_command` or
#     `cross_count_tests`. This profile selects no runner and names no artifact,
#     so `cross-test` keeps its own native/QEMU/Wine/Wasmtime detection, and a
#     target with no detected runner is reported as build-only and never as a
#     pass.
#   * No `-Doptimize` and no `-Dtarget`. The gate is this package's own `test`
#     step in its own default Debug mode: the harness owns the target, and an
#     added optimisation mode would be a second, differently-shaped gate wearing
#     this matrix's exit code. The two `-D` flags below are named for a
#     different reason and are explained where they are set.
#   * No host path of any kind. Scratch and cache placement is `cross-test`'s
#     own host policy (`lib/host-scratch.sh`), which it sources before it reads
#     any name in this file, and this package resolves nothing from a path it
#     hard-codes. The behavioural tests embed their PubChem fixture with
#     `@embedFile` and touch no filesystem, so they need no scratch directory of
#     their own on any target.
#   * No resource limits. `--jobs`, `--build-jobs`, `--timeout` and
#     `--build-timeout` stay whatever the caller asked for; this package does
#     not know the machine it will be measured on.
#
# The step this matrix runs, stated rather than assumed: `test` is the step that
# `addTest` + `addRunArtifact` makes real, so a foreign target is compiled and
# then either executed by a detected runner or left build-only, and never
# counted as a pass without having run.
CROSS_BUILD_STEP=test

# The configuration, named rather than left to the defaults.
#
# `build.zig` gained two options and both defaults are the ordinary linked,
# static build. Neither default is relied on here, because a cell that silently
# changed kind would still exit zero.
#
#   * `-Dlinkage=static`. The two linkages are not interchangeable over this
#     matrix, and one of them has no answer on some cells at all: WASI has no
#     shared object for a C library to be built into, so `-Dlinkage=dynamic`
#     cannot be the answer for `wasm32-wasi`.
#   * `-Druntime=false`. The linked dispatch, not the generated one. This is the
#     one that would be most tempting to omit, because a linked cell still
#     compiles and still runs the behavioural tests; what it would not be is a
#     runtime cell. The loader's Unix backend calls `dlopen`, which WASI does
#     not have either, so `-Druntime=true` has cells it cannot answer as well.
#
# So the published 53-platform matrix is the static LINKED closure, which every
# cell can satisfy. The other configurations are verified separately and on
# their own terms: the shared artifact with `zig build -Dlinkage=dynamic` plus
# the installed C consumer, and the runtime route with `-Druntime=true`, which
# needs a real provider and is therefore not something a compile-and-run matrix
# cell can stand for. Narrowing the matrix is not what this does — all 53 cells
# stay, and none of them is a cell pretending to be a configuration it is not.
CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)
