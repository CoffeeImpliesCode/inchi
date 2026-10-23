# SPDX-License-Identifier: LicenseRef-InChI-MIT-Conditional
# See FORK-LICENSE.md for grant terms.

# Settings-only profile; cross-test selects targets and executors.
# Targets without an executor are build-only, not runtime-tested.
CROSS_BUILD_STEP=test

# Matrix uses static linked builds; WASI lacks shared libraries and `dlopen`.
CROSS_BUILD_ARGS=(-Dlinkage=static -Druntime=false)
