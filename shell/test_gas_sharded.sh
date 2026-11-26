#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/repo.sh"
cd_repo_root

if (($# == 0)); then
    set -- bridge other
elif (($# != 1)) || [[ "$1" != bridge && "$1" != other ]]; then
    echo "Usage: $0 [bridge|other]" >&2
    exit 2
fi

require_command jq

export FOUNDRY_PROFILE=deploy
export FOUNDRY_GAS_SNAPSHOT_EMIT=true
# Resolve the production dependency closure from the selected test roots.
export FOUNDRY_SRC=src/test

# Assign every test root to one group. Forge still loads the imported closure.
patterns=()
groups=()
for root in src/test/* src/test/{periphery,policies,proposals}/*; do
    case "$root" in
        src/test/periphery | src/test/policies | src/test/proposals) continue ;;
        */bridge | */CCIP* | */LZ*) group=bridge ;;
        *) group=other ;;
    esac
    if [[ -d "$root" ]]; then
        patterns+=("$root/**")
        groups+=("$group")
    elif [[ "$root" == *.sol ]]; then
        patterns+=("$root")
        groups+=("$group")
    fi
done

# Limit compile roots before each test invocation. Execution filters alone
# leave tests under src/ in the compiler graph.
for group in "$@"; do
    exclude=()
    include=()
    for index in "${!patterns[@]}"; do
        if [[ "${groups[$index]}" == "$group" ]]; then
            include+=("${patterns[$index]}")
        else
            exclude+=("${patterns[$index]}")
        fi
    done
    ((${#include[@]} > 0)) || continue
    if ((${#include[@]} == 1)); then
        match_path=${include[0]}
    else
        match_path=$(
            IFS=,
            printf '{%s}' "${include[*]}"
        )
    fi
    # Imported test contracts can still be present in the artifacts.
    export FOUNDRY_SKIP
    FOUNDRY_SKIP=$(jq -cn --args '$ARGS.positional | sort' "${exclude[@]}")
    # Forge prunes cache entries outside the current compile graph.
    export FOUNDRY_OUT="out/gas/$group"
    export FOUNDRY_CACHE_PATH="cache/gas/$group"
    echo "Gas snapshot group: $group"
    pnpm run test:unit --match-path "$match_path"
    pnpm run test:fork --match-path "$match_path"
done
