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
#   * No `CROSS_BUILD_ARGS`. The gate is this package's own `test` step in its
#     own default Debug mode: no `-Dtarget`, no `-Doptimize`, no added flags.
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
# The one name set here is the build step, stated rather than assumed: `test` is
# the step that `addTest` + `addRunArtifact` makes real, so a foreign target is
# compiled and then either executed by a detected runner or left build-only,
# and never counted as a pass without having run.
CROSS_BUILD_STEP=test
