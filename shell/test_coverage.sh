#!/usr/bin/env bash
set -euo pipefail

# Code coverage. Runs under the `coverage` profile, which collapses the build into a single compile
# job and trims the fuzz and invariant budgets. See foundry.toml.
#
# `forge coverage` recompiles the whole project from scratch on every run and keeps nothing in
# `out/`, so this is slow and memory hungry regardless of the filters below. `--threads 1` trades
# wall time for a lower peak.

cd "$(git rev-parse --show-toplevel 2> /dev/null || pwd)"

COVERAGE_LOG="coverage.log"
GENHTML_LOG="genhtml.log"
LCOV_FILE="lcov.info"
HTML_DIR="coverage"

command -v forge > /dev/null 2>&1 || {
    echo "ERROR: forge not found. Install Foundry: https://getfoundry.sh" >&2
    exit 1
}

command -v genhtml > /dev/null 2>&1 || {
    echo "ERROR: genhtml not found. It ships with lcov:" >&2
    echo "  Debian/Ubuntu/WSL: sudo apt-get install lcov" >&2
    echo "  macOS:             brew install lcov" >&2
    exit 1
}

# Pick the newest tracefile format the installed genhtml can read. An older format is always safe,
# genhtml reads it without a complaint, while a newer one fails outright. Forge accepts any
# MAJOR[.MINOR] without validating it and maps anything below 2.0 to the v1 format and anything from
# 2.2 upwards to the current one, so an unparsed version would quietly change the output instead of
# failing. Parsing stays in the shell to avoid the differences between GNU and BSD grep and awk.
detect_lcov_version() {
    local raw ver major minor
    raw=$(genhtml --version 2>&1 || true) # "genhtml: LCOV version 2.0-1"
    ver=${raw##*version }                 # "2.0-1", or the whole string when absent
    ver=${ver%%-*}                        # "2.0"
    ver=${ver%%[!0-9.]*}                  # drop anything that is not part of a version
    major=${ver%%.*}
    minor=${ver#*.}
    [ "$minor" = "$ver" ] && minor=0
    case "$major" in '' | *[!0-9]*) major=1 ;; esac
    case "$minor" in '' | *[!0-9]*) minor=0 ;; esac

    if [ "$major" -lt 2 ]; then
        echo "1"
    elif [ "$minor" -lt 2 ]; then
        echo "2.0"
    else
        echo "2.2"
    fi
}

# Older Forge releases have no such flag. Their output is the v1 format, which every genhtml reads,
# so dropping the flag is the correct fallback.
LCOV_FLAG=()
if forge coverage --help 2>&1 | grep -q -- '--lcov-version'; then
    LCOV_FLAG=(--lcov-version "$(detect_lcov_version)")
fi

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
    ${LCOV_FLAG[@]+"${LCOV_FLAG[@]}"} \
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
echo "Generating HTML report in ${HTML_DIR}/"

GENHTML=(genhtml "$LCOV_FILE" -o "$HTML_DIR" --branch-coverage --legend --prefix "$(pwd)")

if ! "${GENHTML[@]}" 2> "$GENHTML_LOG"; then
    # genhtml names the category of each complaint in parentheses and accepts the same names in
    # --ignore-errors, so retry with exactly the categories it raised.
    categories=$(grep -oE '\((inconsistent|corrupt|range|source|format|unmapped|empty|unused|mismatch)\)' "$GENHTML_LOG" \
        | tr -d '()' | sort -u | paste -sd, -)
    if [ -z "$categories" ]; then
        echo "ERROR: genhtml failed and raised no recognised category:" >&2
        tail -20 "$GENHTML_LOG" >&2
        exit 1
    fi
    echo "genhtml failed, retrying while ignoring: ${categories}" >&2
    "${GENHTML[@]}" --ignore-errors "$categories"
fi

echo ""
echo "Done. Open ${HTML_DIR}/index.html"
exit "$coverage_status"
