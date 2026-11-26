#!/bin/bash

# Pin the compiler used by repository commands that record snapshots.
compiler_args=()
export FOUNDRY_GAS_SNAPSHOT_EMIT="${FOUNDRY_GAS_SNAPSHOT_EMIT:-false}"
case "$FOUNDRY_GAS_SNAPSHOT_EMIT" in
    true)
        if [[ "${FOUNDRY_PROFILE:-default}" != deploy ]]; then
            echo "Gas snapshot recording requires the Solc deploy profile. Run 'pnpm run test:gas'." >&2
            exit 1
        fi
        if ! compiler=$(forge config --json | jq -er '.solc | strings | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'); then
            echo "Gas snapshot recording requires a pinned Solc release in the deploy profile." >&2
            exit 1
        fi
        compiler_args=(--profile deploy --use "$compiler")
        ;;
    false) ;;
    *)
        echo "FOUNDRY_GAS_SNAPSHOT_EMIT must be true or false." >&2
        exit 1
        ;;
esac

# Do not enable `set -e`: Forge can rewrite gas snapshots before returning a
# failure, so snapshot formatting must still run when a test fails or crashes.
forge test "$@" "${compiler_args[@]}" --gas-snapshot-emit "$FOUNDRY_GAS_SNAPSHOT_EMIT"
test_status=$?

if [[ "$FOUNDRY_GAS_SNAPSHOT_EMIT" == false ]]; then
    exit "$test_status"
fi

# Normalize the compact JSON Forge writes when it records snapshots.
pnpm run format:snapshots
format_status=$?

# Preserve a Forge failure as the primary result. A formatting failure should
# fail the command only when the tests themselves passed.
if [ "$test_status" -ne 0 ]; then
    exit "$test_status"
fi

exit "$format_status"
