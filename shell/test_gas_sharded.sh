#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/repo.sh"
cd_repo_root
require_command jq

export FOUNDRY_PROFILE=deploy
export FOUNDRY_GAS_SNAPSHOT_EMIT=true
# Resolve the production dependency closure from the selected test roots.
export FOUNDRY_SRC=src/test

# Assign every test root to one group. Forge still loads the imported closure.
patterns=()
groups=()
for root in src/test/* src/test/policies/*; do
    case "$root" in
        src/test/policies) continue ;;
        src/test/periphery) group=periphery ;;
        src/test/policies/BurnerLoansCore | src/test/policies/BurnerLoansSeize | src/test/policies/BurnerLoansSeizerTask) group=burner-core ;;
        src/test/policies/BurnerLoans*) group=burner-policies ;;
        src/test/policies/bridge | src/test/policies/price | src/test/policies/utils) group=bridge-price-utils ;;
        src/test/policies/*) group=other-policies ;;
        *) group=other-tests ;;
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
for group in other-tests periphery other-policies bridge-price-utils burner-policies burner-core; do
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
