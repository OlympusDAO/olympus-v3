# shellcheck shell=bash
# Shared helpers for the CCIP config Anvil deployment harness.
#
# The harness drives the project's real Solidity scripts against a local Anvil
# fork of Ethereum mainnet. Deploys are signed with a known Anvil dev key;
# multisig and timelock actions are sent from the real on-chain owners through
# Anvil account impersonation (--auto-impersonate).

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

PORT="${PORT:-8545}"
RPC="http://localhost:${PORT}"
ANVIL_PID=""
KEEP_FORK="${KEEP_FORK:-false}"
# When true, the run script skips the deploy step and acts on the config
# addresses already recorded in env.json / addresses.json (the real on-chain
# deployment) instead of deploying a fresh throwaway set onto the fork.
USE_DEPLOYED="${USE_DEPLOYED:-false}"

log()  { printf '\n\033[1;36m[harness]\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;33m==== %s ====\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m[harness:error]\033[0m %s\n' "$*" >&2; exit 1; }

# Export the provider key so Anvil resolves ${ALCHEMY_API_KEY} in the
# foundry.toml RPC aliases.
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
  cp "$REPO_ROOT/$ENV_JSON"  "$BACKUP_DIR/env.json.bak"
  cp "$REPO_ROOT/$ADDR_JSON" "$BACKUP_DIR/addresses.json.bak"
}

restore_tracked_files() {
  [ -f "$BACKUP_DIR/env.json.bak" ]       && cp "$BACKUP_DIR/env.json.bak"       "$REPO_ROOT/$ENV_JSON"
  [ -f "$BACKUP_DIR/addresses.json.bak" ] && cp "$BACKUP_DIR/addresses.json.bak" "$REPO_ROOT/$ADDR_JSON"
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
    # The DeployV3 broadcast records are tracked for real deployments (.gitignore allowlist), so
    # the ones written by this fork run are removed as well.
    [ -d "$BACKUP_DIR" ] && find "$REPO_ROOT/broadcast/DeployV3.s.sol" -name 'run-*.json' \
      -newer "$BACKUP_DIR/env.json.bak" -delete 2>/dev/null || true
    log "Anvil stopped; tracked files restored; fork deploy and broadcast records removed."
  fi
  exit "$code"
}

start_anvil() {
  local fork_alias="$1"
  mkdir -p "$LOG_DIR"
  # Fail fast if the port is taken: a new Anvil that cannot bind exits, leaving cast on the stale fork.
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
    die "$RPC is already serving an RPC (port $PORT in use). Stop that process before starting the harness."
  fi
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
    kill -0 "$ANVIL_PID" 2>/dev/null || { tail -n 30 "$LOG_DIR/anvil-$fork_alias.log"; die "Anvil exited during startup"; }
    if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
      log "Anvil ready at block $(cast block-number --rpc-url "$RPC"), pid $ANVIL_PID"
      return 0
    fi
    sleep 1
  done
  die "Anvil did not become ready within 90s"
}

fund() { cast rpc --rpc-url "$RPC" anvil_setBalance "$1" "$FUND_WEI_HEX" >/dev/null; }

# warp <seconds>: advance the fork clock and mine a block.
warp() {
  cast rpc --rpc-url "$RPC" evm_increaseTime "$1" >/dev/null
  cast rpc --rpc-url "$RPC" anvil_mine 0x1 >/dev/null
  log "Warped $1 seconds; block timestamp is now $(cast block latest --field timestamp --rpc-url "$RPC")"
}

# env_addr <chain> <dot.path.below.chain>  ->  value or empty
env_addr() { jq -r --arg c "$1" ".current[\$c].$2 // empty" "$REPO_ROOT/$ENV_JSON"; }

# set_env_value <chain> <dot.path.below.chain> <json-value>
set_env_value() {
  local tmp; tmp="$(mktemp)"
  jq --arg c "$1" --argjson v "$3" ".current[\$c].$2 = \$v" "$REPO_ROOT/$ENV_JSON" > "$tmp"
  mv "$tmp" "$REPO_ROOT/$ENV_JSON"
}

# set_registry_addr <name> <addr>   (updates the chainId 1 entry in addresses.json)
set_registry_addr() {
  local target="$REPO_ROOT/$ADDR_JSON" tmp
  tmp="$(mktemp)"
  jq --arg n "$1" --arg a "$2" '
    if any(.[]; .name == $n and .chainId == 1)
    then map(if .name == $n and .chainId == 1 then .addr = $a else . end)
    else error("no chainId 1 registry entry for " + $n)
    end
  ' "$target" > "$tmp" || { rm -f "$tmp"; die "failed to update $ADDR_JSON for '$1'"; }
  mv "$tmp" "$target"
}

require_addr() {
  case "$1" in
    0x0000000000000000000000000000000000000000|""|null) die "expected a non-zero address for $2, got '$1'";;
  esac
}

# deploy_sequence <sequence-file-relative-to-repo-root>
deploy_sequence() {
  step "Deploy sequence: $1"
  (
    cd "$REPO_ROOT"
    set -o pipefail
    FOUNDRY_PROFILE=deploy forge script src/scripts/deploy/DeployV3.s.sol:DeployV3 \
      --sig "deploy(string)()" "$1" \
      --rpc-url "$RPC" \
      --private-key "$DEPLOYER_KEY" --sender "$DEPLOYER_ADDR" \
      --slow --broadcast -vvv \
      2>&1 | tee "$LOG_DIR/deploy.log"
  ) || die "deploy sequence failed; see $LOG_DIR/deploy.log"
}

# run_batch <ContractName> <function> <owner-key> [argsFileRelative] [logSuffix]
# Sends the batch from the multisig at olympus.multisig.<owner-key> (dao or
# emergency) via impersonation. FORK=true skips the Safe client init;
# USE_ANVIL_FORK=true routes proposeBatch() to the on-fork broadcast path.
# The batch log is tee'd to logs/batch-<Contract>-<fn><logSuffix>.log and the
# path is exported as LAST_BATCH_LOG for the caller's assertions.
run_batch() {
  local contract="$1" fn="$2" ownerKey="$3" argsfile="${4:-}" suffix="${5:-}"
  local owner; owner="$(env_addr mainnet "olympus.multisig.$ownerKey")"
  require_addr "$owner" "mainnet olympus.multisig.$ownerKey"
  fund "$owner"
  LAST_BATCH_LOG="$LOG_DIR/batch-${contract}-${fn}${suffix}.log"
  step "Batch ${contract}.${fn} (owner=$ownerKey MS $owner)"
  (
    cd "$REPO_ROOT"
    set -o pipefail
    FORK=true USE_ANVIL_FORK=true FOUNDRY_PROFILE=multisig forge script \
      "src/scripts/ops/batches/${contract}.sol:${contract}" \
      --sig "${fn}(bool,bool,string,string,bytes)()" true false "$argsfile" "" 0x \
      --rpc-url "$RPC" --sender "$owner" --unlocked --slow -vvv --broadcast \
      2>&1 | tee "$LAST_BATCH_LOG"
  ) || die "batch ${contract}.${fn} failed; see $LAST_BATCH_LOG"
}

# expect_empty_batch <log> <label>: the last batch must have proposed nothing.
expect_empty_batch() {
  if grep -q "No batch targets to execute" "$1"; then
    log "OK: $2 proposed no action (converged)"
  else
    die "$2 was expected to propose nothing; see $1"
  fi
}

# expect_non_empty_batch <log> <label>: the last batch must have proposed something.
expect_non_empty_batch() {
  if grep -q "Batch executed successfully on Anvil fork" "$1"; then
    log "OK: $2 executed on the fork"
  else
    die "$2 was expected to execute actions; see $1"
  fi
}

# cast_send_impersonated <from> <to> <sig> [args...]
cast_send_impersonated() {
  local from="$1" to="$2" sig="$3"; shift 3
  fund "$from"
  cast send "$to" "$sig" "$@" --rpc-url "$RPC" --from "$from" --unlocked >/dev/null
}
