# shellcheck shell=bash
# Shared helpers for the LayerZero bridge Anvil deployment harness.
#
# The harness drives the project's real Solidity scripts against a local Anvil
# fork.
# Deploys are signed with a known Anvil dev key; multisig and timelock actions
# are sent from the real on-chain owners through Anvil account impersonation
# (--auto-impersonate)\.

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve the repo root from git.
REPO_ROOT="$(git -C "$HARNESS_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
{ [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/foundry.toml" ]; } || {
  echo "[harness:error] cannot locate the repo root (foundry.toml) from $HARNESS_DIR" >&2
  exit 1
}
BACKUP_DIR="$HARNESS_DIR/.backup"
LOG_DIR="$HARNESS_DIR/logs"

# Tracked files the harness modifies and restores on exit.
ENV_JSON="src/scripts/env.json"
ADDR_JSON="src/proposals/addresses.json"
SUPPLY_ARGS="src/scripts/ops/batches/args/LZBridgeGatewayBatch_initBridgedSupply.json"

# Anvil dev account #0. Its key is public and is used only to sign deploys on
# the fork; the address is funded with anvil_setBalance before deploying.
DEPLOYER_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# 10000 ETH in wei (hex), funded onto every account that pays gas on the fork.
FUND_WEI_HEX="0x21E19E0C9BAB2400000"

# Upstream RPC throttle. A lower compute-units-per-second spreads the fork
# backfill over more time so the provider does not rate-limit the run; the
# retry backoff smooths transient 429s. Override via env to taste.
ANVIL_CUPS="${ANVIL_CUPS:-250}"
ANVIL_BACKOFF_MS="${ANVIL_BACKOFF_MS:-1000}"

# Non-zero stand-in gateway addresses for chains not deployed in a single-fork
# run. setPeer and the activator constructor only store these as data, so any
# distinct non-zero address lets the peer wiring and validation pass.
declare -A PLACEHOLDER_GATEWAY=(
  [mainnet]="0x0000000000000000000000000000000000bEA001"
  [arbitrum]="0x0000000000000000000000000000000000bEA002"
  [optimism]="0x0000000000000000000000000000000000bEA003"
  [base]="0x0000000000000000000000000000000000bEA004"
  [berachain]="0x0000000000000000000000000000000000bEA005"
)

PORT="${PORT:-8545}"
RPC="http://localhost:${PORT}"
ANVIL_PID=""
KEEP_FORK="${KEEP_FORK:-false}"
# When true, the run scripts skip the deploy step and act on the bridge addresses
# already recorded in env.json / addresses.json (the real on-chain deployment)
# instead of deploying a fresh throwaway set onto the fork.
USE_DEPLOYED="${USE_DEPLOYED:-false}"

log()  { printf '\n\033[1;36m[harness]\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;33m==== %s ====\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m[harness:error]\033[0m %s\n' "$*" >&2; exit 1; }

# Export the provider key so Anvil resolves ${ALCHEMY_API_KEY} in the
# foundry.toml RPC aliases (mainnet, arbitrum, ...).
load_dotenv() {
  [ -f "$REPO_ROOT/.env" ] || die ".env not found in $REPO_ROOT (needs ALCHEMY_API_KEY)"
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
  [ -n "${ALCHEMY_API_KEY:-}" ] || die "ALCHEMY_API_KEY is empty after sourcing .env"
}

backup_tracked_files() {
  mkdir -p "$BACKUP_DIR"
  cp "$REPO_ROOT/$ENV_JSON"     "$BACKUP_DIR/env.json.bak"
  cp "$REPO_ROOT/$ADDR_JSON"    "$BACKUP_DIR/addresses.json.bak"
  cp "$REPO_ROOT/$SUPPLY_ARGS"  "$BACKUP_DIR/supply.json.bak"
}

restore_tracked_files() {
  [ -f "$BACKUP_DIR/env.json.bak" ]    && cp "$BACKUP_DIR/env.json.bak"    "$REPO_ROOT/$ENV_JSON"
  [ -f "$BACKUP_DIR/addresses.json.bak" ] && cp "$BACKUP_DIR/addresses.json.bak" "$REPO_ROOT/$ADDR_JSON"
  [ -f "$BACKUP_DIR/supply.json.bak" ] && cp "$BACKUP_DIR/supply.json.bak" "$REPO_ROOT/$SUPPLY_ARGS"
}

# Trap handler. With KEEP_FORK the fork and the populated env/addresses files are
# left in place so further transactions can be sent against $RPC; otherwise the
# fork is stopped and the tracked files are restored.
cleanup() {
  local code=$?
  if [ "$KEEP_FORK" = "true" ]; then
    log "KEEP_FORK set: Anvil (pid ${ANVIL_PID:-?}) left running on $RPC; env/addresses files left modified."
    log "Stop it later with: kill ${ANVIL_PID:-<pid>}"
  else
    [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2>/dev/null || true
    restore_tracked_files
    # Remove the per-deploy record files DeployV3 writes during this run (those
    # newer than the backup taken at startup); pre-existing records are kept.
    [ -d "$BACKUP_DIR" ] && find "$REPO_ROOT/deployments" -maxdepth 1 -name '.*-*.json' \
      -newer "$BACKUP_DIR/env.json.bak" -delete 2>/dev/null || true
    log "Anvil stopped; tracked files restored; fork deploy records removed."
  fi
  exit "$code"
}

start_anvil() {
  local fork_alias="$1"
  mkdir -p "$LOG_DIR"
  log "Starting Anvil fork of '$fork_alias' on $RPC (CUPS=$ANVIL_CUPS, backoff=${ANVIL_BACKOFF_MS}ms)"
  anvil \
    --fork-url "$fork_alias" \
    --port "$PORT" \
    --auto-impersonate \
    --compute-units-per-second "$ANVIL_CUPS" \
    --fork-retry-backoff "$ANVIL_BACKOFF_MS" \
    --timeout 60000 \
    > "$LOG_DIR/anvil-$fork_alias.log" 2>&1 &
  ANVIL_PID=$!
  local i
  for i in $(seq 1 90); do
    if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
      log "Anvil ready at block $(cast block-number --rpc-url "$RPC"), pid $ANVIL_PID"
      return 0
    fi
    kill -0 "$ANVIL_PID" 2>/dev/null || { tail -n 30 "$LOG_DIR/anvil-$fork_alias.log"; die "Anvil exited during startup"; }
    sleep 1
  done
  die "Anvil did not become ready within 90s"
}

fund() { cast rpc --rpc-url "$RPC" anvil_setBalance "$1" "$FUND_WEI_HEX" >/dev/null; }

# env_addr <chain> <dot.path.below.chain>  ->  address or empty
env_addr() { jq -r --arg c "$1" ".current[\$c].$2 // empty" "$REPO_ROOT/$ENV_JSON"; }

# set_env_addr <chain> <dot.path.below.chain> <addr>
set_env_addr() {
  local tmp; tmp="$(mktemp)"
  jq --arg c "$1" --arg a "$3" ".current[\$c].$2 = \$a" "$REPO_ROOT/$ENV_JSON" > "$tmp"
  mv "$tmp" "$REPO_ROOT/$ENV_JSON"
}

# set_registry_addr <name> <addr>   (updates the chainId 1 entry in addresses.json)
set_registry_addr() {
  local tmp; tmp="$(mktemp)"
  jq --arg n "$1" --arg a "$2" '(.[] | select(.name == $n and .chainId == 1)).addr = $a' \
    "$REPO_ROOT/$ADDR_JSON" > "$tmp"
  mv "$tmp" "$REPO_ROOT/$ADDR_JSON"
}

require_addr() {
  case "$1" in
    0x0000000000000000000000000000000000000000|""|null) die "expected a non-zero address for $2, got '$1'";;
  esac
}

# deploy_sequence <sequence-file-relative-to-repo-root>
deploy_sequence() {
  step "Deploy sequence: $1"
  FOUNDRY_PROFILE=deploy forge script src/scripts/deploy/DeployV3.s.sol:DeployV3 \
    --sig "deploy(string)()" "$1" \
    --rpc-url "$RPC" \
    --private-key "$DEPLOYER_KEY" --sender "$DEPLOYER_ADDR" \
    --slow --broadcast -vvv \
    2>&1 | tee "$LOG_DIR/deploy.log"
}

# run_batch <ContractName> <function> <chain> [argsFileRelative]
# Sends the batch from the chain's DAO MS via impersonation. FORK=1 skips the
# Safe client init; USE_ANVIL_FORK=1 routes proposeBatch() to the on-fork
# broadcast path.
run_batch() {
  local contract="$1" fn="$2" chain="$3" argsfile="${4:-}"
  local daoMS; daoMS="$(env_addr "$chain" "olympus.multisig.dao")"
  require_addr "$daoMS" "$chain olympus.multisig.dao"
  fund "$daoMS"
  step "Batch ${contract}.${fn} (chain=$chain, owner=DAO MS $daoMS)"
  FORK=true USE_ANVIL_FORK=true FOUNDRY_PROFILE=multisig forge script \
    "src/scripts/ops/batches/${contract}.sol:${contract}" \
    --sig "${fn}(bool,bool,string,string,bytes)()" true false "$argsfile" "" 0x \
    --rpc-url "$RPC" --sender "$daoMS" --unlocked --slow -vvv --broadcast \
    2>&1 | tee "$LOG_DIR/batch-${contract}-${fn}.log"
}

# cast_send_impersonated <from> <to> <sig> [args...]
cast_send_impersonated() {
  local from="$1" to="$2" sig="$3"; shift 3
  fund "$from"
  cast send "$to" "$sig" "$@" --rpc-url "$RPC" --from "$from" --unlocked >/dev/null
}

# activate_policy <chain> <policyAddr>  -  ActivatePolicy via the Kernel executor.
activate_policy() {
  local kernel exec
  kernel="$(env_addr "$1" "olympus.Kernel")"
  exec="$(cast call "$kernel" "executor()(address)" --rpc-url "$RPC")"
  log "Kernel executeAction(ActivatePolicy, $2) as executor $exec"
  cast_send_impersonated "$exec" "$kernel" "executeAction(uint8,address)" 2 "$2"
}
