#!/usr/bin/env bash
set -euo pipefail

# Code coverage. Runs under the `coverage` profile, which collapses the build into a single compile
# job and trims the fuzz and invariant budgets. See foundry.toml.
#
# `forge coverage` recompiles the whole project from scratch on every run and keeps nothing in
# `out/`, so this is slow and memory hungry regardless of the filters below. `--threads 1` trades
# wall time for a lower peak.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/repo.sh"

cd_repo_root

COVERAGE_LOG="coverage.log"
LCOV_FILE="lcov.info"

require_command forge "Install Foundry: https://getfoundry.sh"

# `forge coverage` compiles in memory and leaves `out/` untouched, so a test that reads the build
# artifacts sees whatever the last build left there, or nothing at all. No test does: the
# permissioned selectors that the fixtures need come from
# `src/test/lib/generated/ModulePermissions.sol`, which `shell/gen_perms.sh` writes ahead of time.
# The build below is kept commented out because reinstating such a test would need it back.
# echo "Building the artifacts that the AST-based test fixtures read"
# FOUNDRY_PROFILE=coverage forge build --skip test

echo "Running code coverage (log in ${COVERAGE_LOG})"

rm -f "$LCOV_FILE"

# A failing test does not suppress the reports, but a compilation failure leaves nothing to report,
# so the exit status is kept and checked against the tracefile below.
coverage_status=0
FOUNDRY_PROFILE=coverage forge coverage \
    --threads 1 \
    --ir-minimum \
    --report summary --report lcov \
    --exclude-tests \
    --no-match-coverage "^src/(scripts|proposals|interfaces|external)|(^|/)dependencies/" \
    --no-match-path "src/test/{deprecated,external,proposals,sim,mocks,lib}/**" \
    --no-match-test "^invariant_" \
    > "$COVERAGE_LOG" 2>&1 || coverage_status=$?

if [ ! -s "$LCOV_FILE" ]; then
    # Forge can exit zero without writing a tracefile, so this branch fails on its own rather than
    # passing the status through.
    echo "ERROR: no ${LCOV_FILE} produced. Last lines of ${COVERAGE_LOG}:" >&2
    tail -30 "$COVERAGE_LOG" >&2
    exit 1
fi

# The summary table is the point of the run, so surface it even though the rest stays in the log.
sed -n '/^╭/,/^╰/p' "$COVERAGE_LOG" || true

if [ "$coverage_status" -ne 0 ]; then
    echo "WARNING: some tests failed; the reports below cover the run as it happened" >&2
    grep -E '^\[FAIL' "$COVERAGE_LOG" >&2 || true
fi

echo ""
echo "Coverage data: ${LCOV_FILE}. Full log: ${COVERAGE_LOG}"
exit "$coverage_status"
