#!/usr/bin/env bash
# SPDX-FileCopyrightText: Contributors to OlympusDAO
# SPDX-License-Identifier: Unlicense
set -euo pipefail

# Regenerates src/test/lib/generated/ModulePermissions.sol from the compiler AST.
#
# The `permissioned` modifier does not survive compilation into the ABI, so the set of functions a
# module gates is only recoverable from the AST. Reading it here, once, keeps that lookup out of the
# test run: the tests consume a plain `bytes4[]` and need neither `ffi` nor `ast` at runtime.
#
# Pass --check to verify the committed file matches the sources without writing it, which is what CI
# needs to catch a module whose permissioned functions changed without a regeneration.

# `sort` is locale sensitive, so the byte order is pinned to keep --check agreeing across
# machines.
export LC_ALL=C

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/repo.sh"

cd_repo_root

OUT_FILE="src/test/lib/generated/ModulePermissions.sol"
CHECK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            echo "Usage: $0 [--check]" >&2
            exit 1
            ;;
    esac
    shift
done

require_command forge "Install Foundry: https://getfoundry.sh"
require_command jq
require_command pnpm "Install the Node dependencies: pnpm install"

# --ast asks solc for the AST whatever `ast` is set to in foundry.toml, and --skip test is safe
# because a `permissioned` function can only be declared on a module, while no module lives in the
# test tree.
#
# The build goes to its own artifact and cache directories. Sharing them with a normal build makes
# the two invalidate each other on every alternation, because the requested compiler output differs,
# and it would also leave the AST in the `out/` that CI uploads to every test job.
AST_ROOT=".gen-perms"

# The tree is discarded first. Forge keeps the artifact of a contract that a source file no longer
# declares, and that artifact carries the AST of the file as it was, so reading one would regenerate
# every contract of that file from an outdated snapshot.
rm -rf "$AST_ROOT"

echo "Building the artifacts that carry the AST"
FOUNDRY_OUT="${AST_ROOT}/out" FOUNDRY_CACHE_PATH="${AST_ROOT}/cache" \
    forge build --skip test --ast > /dev/null

# One record per contract that declares at least one `permissioned` function, as
# "<source path>|<contract name>|<function name>,...". Sorted by contract name so the output is
# stable across runs. Candidate sources come from the modifier name appearing in the file at all,
# which is a superset that the AST query below then narrows down.
records=$(
    for source in $(grep -rl --include='*.sol' 'permissioned' src | grep -v '^src/test/' | sort); do
        artifact_dir="${AST_ROOT}/out/$(basename "$source")"
        [ -d "$artifact_dir" ] || continue
        # Every artifact of a source shares its AST, and the directory was just rebuilt from
        # scratch. It keeps the run repeatable.
        artifact=$(find "$artifact_dir" -maxdepth 1 -name '*.json' | sort | head -1)
        [ -n "$artifact" ] || continue

        # Only functions declared by the contract itself are listed, matching what the fixtures
        # granted while they read the AST over ffi.
        jq -r --arg source "$source" '
            [.ast.nodes[]
             | select(.nodeType == "ContractDefinition")
             | {name, fns: [.nodes[]
                 | select(.nodeType == "FunctionDefinition" and .kind == "function")
                 | select([.modifiers[] | .modifierName.name == "permissioned"] | any)
                 | .name]}
             | select(.fns | length > 0)]
            | .[] | $source + "|" + .name + "|" + (.fns | join(","))' "$artifact"
    done | sort -t'|' -k2,2
)

[ -n "$records" ] || {
    echo "ERROR: no contract with a permissioned function was found" >&2
    exit 1
}

duplicates=$(cut -d'|' -f2 <<< "$records" | uniq -d)
[ -z "$duplicates" ] || {
    echo "ERROR: contract name declared in more than one source: ${duplicates}" >&2
    exit 1
}

# Emits a NatSpec block wrapped to the prettier print width, continuing at the tag column.
natspec() {
    local indent="$1" tag="$2" text="$3"
    local head continuation limit line word
    head=$(printf '%s/// %-8s' "$indent" "$tag")
    continuation=$(printf '%s///         ' "$indent")
    limit=100

    line="$head"
    for word in $text; do
        if [ "${#line}" -gt "${#head}" ] && [ $((${#line} + 1 + ${#word})) -gt "$limit" ]; then
            echo "${line% }"
            line="$continuation"
        fi
        line="${line}${word} "
    done
    echo "${line% }"
}

# A leading lower-case letter turns the contract name into the accessor name.
to_accessor() {
    printf '%s%s' "$(printf '%s' "${1:0:1}" | tr '[:upper:]' '[:lower:]')" "${1:1}"
}

# Prettier resolves both its configuration and its Solidity plugin from the directory of the file it
# formats, so the draft is written inside the repository.
generated=".gen_perms.$$.sol"
trap 'rm -f "$generated"' EXIT

# REUSE-IgnoreStart
{
    echo "// SPDX-FileCopyrightText: Contributors to OlympusDAO"
    echo "// SPDX-License-Identifier: Unlicense"
    echo "pragma solidity ^0.8.15;"
    echo ""
    echo "// AUTOGENERATED BY shell/gen_perms.sh. DO NOT EDIT."
    echo "// Run \`pnpm run gen:perms\` when a module gains or loses a permissioned function."
    echo ""
    echo "// Contracts"
    sort -t'|' -k1,1 <<< "$records" | while IFS='|' read -r source contract _; do
        echo "import {${contract}} from \"${source}\";"
    done
    echo ""
    natspec "" "@notice" "Selectors of the functions that each module gates with the \`permissioned\` modifier."
    natspec "" "@dev" "The lists are derived from the compiler AST, which is the only compiler output that records the modifier. Pass one to {ModuleTestFixtureGenerator-generateMultiFunctionFixture} to build a fixture policy that holds every permission the module gates."
    echo "library ModulePermissions {"

    first=1
    while IFS='|' read -r _ contract fns; do
        [ "$first" -eq 1 ] || echo ""
        first=0

        accessor=$(to_accessor "$contract")
        count=$(tr ',' '\n' <<< "$fns" | grep -c .)

        natspec "    " "@notice" "Selectors that {${contract}} gates with the \`permissioned\` modifier."
        natspec "    " "@return" "selectors The selectors, in the order the contract declares them."
        echo "    function ${accessor}() internal pure returns (bytes4[] memory selectors) {"
        echo "        selectors = new bytes4[](${count});"
        index=0
        while IFS= read -r fn; do
            [ -n "$fn" ] || continue
            echo "        selectors[${index}] = ${contract}.${fn}.selector;"
            index=$((index + 1))
        done < <(tr ',' '\n' <<< "$fns")
        echo "    }"
    done <<< "$records"

    echo "}"
} > "$generated"
# REUSE-IgnoreEnd

# The committed file has to match what prettier produces, or `pnpm run lint` and --check disagree.
# A failure here stops the run.
pnpm exec prettier --cache --cache-strategy content --write "$generated" > /dev/null

contracts=$(cut -d'|' -f2 <<< "$records" | wc -l | tr -d ' ')
selectors=$(cut -d'|' -f3 <<< "$records" | tr ',' '\n' | grep -c .)

if [ "$CHECK" -eq 1 ]; then
    if ! diff -u "$OUT_FILE" "$generated"; then
        echo "ERROR: ${OUT_FILE} is out of date. Run 'pnpm run gen:perms'." >&2
        exit 1
    fi
    echo "OK: ${OUT_FILE} matches the sources (${contracts} contracts, ${selectors} selectors)"
    exit 0
fi

mkdir -p "$(dirname "$OUT_FILE")"
cp "$generated" "$OUT_FILE"
echo "Wrote ${OUT_FILE} (${contracts} contracts, ${selectors} selectors)"
