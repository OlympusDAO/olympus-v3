#!/bin/bash
# SPDX-FileCopyrightText: Contributors to OlympusDAO
# SPDX-License-Identifier: Unlicense

# Do not enable `set -e`: Forge can rewrite gas snapshots before returning a
# failure, so snapshot formatting must still run when a test fails or crashes.
forge test "$@"
test_status=$?

# Forge writes snapshot JSON in a compact format. Normalize it after every
# repository-managed test command so test runs do not leave formatting changes.
pnpm run format:snapshots
format_status=$?

# Preserve a Forge failure as the primary result. A formatting failure should
# fail the command only when the tests themselves passed.
if [ "$test_status" -ne 0 ]; then
    exit "$test_status"
fi

exit "$format_status"
