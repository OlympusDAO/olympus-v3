#!/usr/bin/env bash
# Aggregated CCIP rollout readiness report: the submission gate for the CCIP
# Token Pool Config Activation proposal.
#
# Runs CCIPNonEthereumSetupBatch.checkReadiness (read-only) on mainnet and the four
# burn/mint chains, and aggregates a green/red verdict per chain and per outgoing
# lane. The proposal must not be submitted until every chain reports GREEN.
#
# Usage:
#   ./shell/ccip/check_rollout_readiness.sh [--chains "mainnet arbitrum optimism base berachain"] [--env <env-file>]
#
# RPC resolution per chain: the READINESS_RPC_<CHAIN> environment variable (uppercase)
# wins; otherwise the chain uses its foundry.toml RPC alias, which needs
# ALCHEMY_API_KEY from the env file.
#
# Note: forge script needs an out/ directory produced by a full `forge build`; a
# path-scoped build can leave it unable to load the script bytecode.
#
# Deliberately no -e: a failed run on one chain must not stop the sweep, since
# the point is the aggregated verdict over every chain.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CHAINS="mainnet arbitrum optimism base berachain"
ENV_FILE=".env"
while [ $# -gt 0 ]; do
    case "$1" in
        --chains)
            [ $# -ge 2 ] || {
                echo "--chains requires a value" >&2
                exit 2
            }
            CHAINS="$2"
            shift 2
            ;;
        --env)
            [ $# -ge 2 ] || {
                echo "--env requires a value" >&2
                exit 2
            }
            ENV_FILE="$2"
            shift 2
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

LOG_DIR="$(mktemp -d /tmp/ccip-readiness.XXXXXX)"
declare -A VERDICT
OVERALL=0

resolve_rpc() {
    local chain="$1"
    local var="READINESS_RPC_$(echo "$chain" | tr '[:lower:]-' '[:upper:]_')"
    if [ -n "${!var:-}" ]; then
        echo "${!var}"
    else
        echo "$chain"
    fi
}

for chain in $CHAINS; do
    rpc="$(resolve_rpc "$chain")"
    log="$LOG_DIR/$chain.log"
    printf '\n\033[1;33m==== Readiness: %s (%s) ====\033[0m\n' "$chain" "$rpc"
    # The script prints the verdict instead of reverting on a red result (a
    # reverted forge script swallows its own log); a run that crashes before
    # printing a verdict (unreadable env.json, RPC failure) is red as well.
    FOUNDRY_PROFILE=multisig forge script \
        src/scripts/ops/batches/CCIPNonEthereumSetupBatch.sol:CCIPNonEthereumSetupBatch \
        --sig "checkReadiness()" --rpc-url "$rpc" -vv > "$log" 2>&1
    if grep -q "READINESS RESULT $chain: GREEN" "$log"; then
        VERDICT[$chain]="GREEN"
    else
        VERDICT[$chain]="RED"
        OVERALL=1
    fi
    # Show the per-check lines and the chain verdict from the run
    grep -E "\[ OK \]|\[FAIL\]|\[INFO\]|READINESS RESULT" "$log" || {
        echo "no readiness output; the run itself failed:"
        tail -n 20 "$log"
    }
done

printf '\n\033[1;33m==== Readiness summary ====\033[0m\n'
for chain in $CHAINS; do
    v="${VERDICT[$chain]:-RED}"
    if [ "$v" = "GREEN" ]; then
        printf '  \033[1;32m%-10s GREEN\033[0m\n' "$chain"
    else
        printf '  \033[1;31m%-10s RED\033[0m   (see %s)\n' "$chain" "$LOG_DIR/$chain.log"
    fi
done

if [ "$OVERALL" -ne 0 ]; then
    printf '\n\033[1;31mReadiness is RED: do not submit the proposal.\033[0m Logs: %s\n' "$LOG_DIR"
else
    printf '\n\033[1;32mReadiness is GREEN on every checked chain.\033[0m Logs: %s\n' "$LOG_DIR"
fi
exit "$OVERALL"
