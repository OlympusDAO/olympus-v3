# shellcheck shell=bash
# The rehearsal of the multisig batches of the YieldRepurchaseFacilityV2 stack and of the
# BackingOracle pair, as phases that run.sh calls in order after the deployment. Every entry
# point runs on the fork: with a state change, again on the converged state, and with the
# precondition failures the phase names. lib/common.sh provides the helpers.

SETUP_BATCH="YieldRepurchaseFacilityV2SetupBatch"
YRF_BATCH="YieldRepurchaseFacilityV2Batch"
YRF_TIMELOCK_BATCH="YieldRepurchaseFacilityV2ConfigTimelockBatch"
ORACLE_SETUP_BATCH="BackingOracleSetupBatch"
ORACLE_BATCH="BackingOracleBatch"
ORACLE_TIMELOCK_BATCH="BackingOracleConfigTimelockBatch"

YRF_KEY="olympus.config.YieldRepurchaseFacilityV2"
BACKING_KEY="olympus.config.BackingOracle.backing"
ACTIVATOR_KEY="olympus.proposals.YieldRepurchaseFacilityV2Activator"

# load_stack: the addresses of the deployed stack and of its neighbours, from env.json.
load_stack() {
    KERNEL="$(env_value olympus.Kernel)"
    ORACLE="$(env_value olympus.policies.BackingOracle)"
    ORACLE_TIMELOCK="$(env_value olympus.policies.BackingOracleConfigTimelock)"
    CONFIG="$(env_value olympus.policies.YieldRepurchaseFacilityV2Config)"
    TIMELOCK="$(env_value olympus.policies.YieldRepurchaseFacilityV2ConfigTimelock)"
    FACILITY="$(env_value olympus.policies.YieldRepurchaseFacilityV2)"
    LENS="$(env_value olympus.periphery.YieldRepurchaseFacilityV2Lens)"
    V1="$(env_value olympus.policies.YieldRepurchaseFacility)"
    TREASURY="$(env_value olympus.modules.OlympusTreasury)"
    AUCTIONEER="$(env_value external.bond-protocol.BondFixedTermAuctioneer)"
    ACTIVATOR="$(env_value "$ACTIVATOR_KEY")"
    HEART="$(env_value olympus.policies.OlympusHeart)"
    OCG_TIMELOCK="$(env_value olympus.governance.Timelock)"
    DAO_MS="$(env_value olympus.multisig.dao)"
    USDS="$(env_value external.tokens.USDS)"
    SUSDS="$(env_value external.tokens.sUSDS)"
    USDE="$(env_value external.tokens.USDe)"
    SUSDE="$(env_value external.tokens.sUSDe)"
    WETH="$(env_value external.tokens.WETH)"
    local pair
    for pair in "KERNEL:$KERNEL" "ORACLE:$ORACLE" "ORACLE_TIMELOCK:$ORACLE_TIMELOCK" \
        "CONFIG:$CONFIG" "TIMELOCK:$TIMELOCK" "FACILITY:$FACILITY" "LENS:$LENS" "V1:$V1" \
        "TREASURY:$TREASURY" "AUCTIONEER:$AUCTIONEER" "ACTIVATOR:$ACTIVATOR" "HEART:$HEART" \
        "OCG_TIMELOCK:$OCG_TIMELOCK" "DAO_MS:$DAO_MS" "USDS:$USDS" "SUSDS:$SUSDS" "USDE:$USDE" \
        "SUSDE:$SUSDE" "WETH:$WETH"; do
        require_addr "${pair#*:}" "${pair%%:*}"
    done
}

# replay_proposal <log-suffix>: builds YieldRepurchaseFacilityV2Proposal against the fork, runs
# it through the governor in a snapshot, and sends its actions one by one from the impersonated
# OCG timelock (src/scripts/proposals/executeOnAnvilFork.sh). The log path goes to
# LAST_BATCH_LOG. The deploy profile is the one the harness built with.
replay_proposal() {
    LAST_BATCH_LOG="$LOG_DIR/proposal$1.log"
    (
        cd "$REPO_ROOT" || exit
        set -o pipefail
        RPC_URL="$RPC" FOUNDRY_PROFILE=deploy src/scripts/proposals/executeOnAnvilFork.sh \
            --file src/proposals/YieldRepurchaseFacilityV2Proposal.sol \
            --contract YieldRepurchaseFacilityV2ProposalScript 2>&1 | tee "$LAST_BATCH_LOG"
    )
}

# expect_enabled <true|false> <label:address>...: isEnabled() of each policy.
expect_enabled() {
    local expected="$1" pair
    shift
    for pair in "$@"; do
        expect "${pair%%:*}.isEnabled()" "$(call "${pair#*:}" 'isEnabled()(bool)')" "$expected"
    done
}

# readiness <GREEN|RED> <log-suffix>: runs the readiness report and requires the verdict.
readiness() {
    LAST_BATCH_LOG="$LOG_DIR/readiness-$2.log"
    step "Readiness report (expected $1)"
    (
        cd "$REPO_ROOT" || exit
        set -o pipefail
        FOUNDRY_PROFILE=deploy forge script \
            "./src/scripts/ops/batches/${SETUP_BATCH}.sol:${SETUP_BATCH}" \
            --sig "checkReadiness()" --rpc-url "$RPC" --no-isolate -vvv 2>&1 | tee "$LAST_BATCH_LOG"
    ) || die "the readiness report did not complete; see $LAST_BATCH_LOG"
    grep -q "READINESS RESULT mainnet: $1" "$LAST_BATCH_LOG" ||
        die "the readiness report was expected to be $1; see $LAST_BATCH_LOG"
    log "OK: the readiness report is $1"
}

# next_yield <vault>: the stored next yield of a registered vault, the eleventh member of
# ReserveAsset.
next_yield() {
    cast call "$FACILITY" \
        'getAssetConfig(address)((address,address,address,uint8,bool,bool,bool,uint256,uint256,uint256,uint256,uint256))' \
        "$1" --rpc-url "$RPC" | tr -d '()' | awk -F', ' '{print $11}' | awk '{print $1}'
}

# action_args <function> <id>: an args file that names one action id for a cancellation.
action_args() {
    write_args "$1-$2" "{\"functions\": [{\"name\": \"$1\", \"args\": {\"actionId\": $2}}]}"
}

# ========== 7. KERNEL ACTIVATION ========== #

rehearse_kernel_setup() {
    step "7. Kernel activation (DAO MS as the Kernel executor)"
    # The batches that follow the launch refuse to run before it.
    run_batch_expect_fail "$SETUP_BATCH" deactivateV1 dao "v1.2 is not shut down" "" "-before-launch"
    run_batch_expect_fail "$YRF_TIMELOCK_BATCH" reconcile dao \
        "the configuration policy is bound to the facility" "" "-before-launch"
    # An owner other than the Kernel executor is refused.
    run_batch_expect_fail "$SETUP_BATCH" setupKernel emergency \
        "the batch owner is not the Kernel executor" "" "-not-executor" false

    run_batch "$ORACLE_SETUP_BATCH" setupKernel dao
    expect_non_empty_batch "BackingOracleSetupBatch.setupKernel"
    run_batch "$ORACLE_SETUP_BATCH" setupKernel dao "" "-rerun"
    expect_empty_batch "BackingOracleSetupBatch.setupKernel re-run"

    run_batch "$SETUP_BATCH" setupKernel dao
    expect_non_empty_batch "setupKernel"
    expect_log_line "BackingOracle is already active in the Kernel. Skipping." \
        "setupKernel leaves the oracle pair, activated by the oracle batch, alone"
    run_batch "$SETUP_BATCH" setupKernel dao "" "-rerun"
    expect_empty_batch "setupKernel re-run"

    local pair
    for pair in "oracle:$ORACLE" "oracleTimelock:$ORACLE_TIMELOCK" "config:$CONFIG" \
        "timelock:$TIMELOCK" "facility:$FACILITY"; do
        expect "kernel.isPolicyActive(${pair%%:*})" \
            "$(call "$KERNEL" 'isPolicyActive(address)(bool)' "${pair#*:}")" true
    done
    expect_enabled false "oracle:$ORACLE" "oracleTimelock:$ORACLE_TIMELOCK" "config:$CONFIG" \
        "timelock:$TIMELOCK" "facility:$FACILITY"
}

# ========== 8. READINESS AND THE CALLBACK ========== #

rehearse_readiness() {
    step "8. Readiness report and the market callback authorization"
    readiness RED before-callback
    expect_log_line "[FAIL] the facility is authorized as a market callback" \
        "the report is red on the missing callback authorization"
    expect_log_line "[FAIL] checkPreconditions() of the activator reverts with CallbackNotAuthorized" \
        "the activator names the missing callback authorization"
    [ "$(grep -c '\[FAIL\]' "$LAST_BATCH_LOG")" = "2" ] ||
        die "the readiness report carries other failures; see $LAST_BATCH_LOG"

    # The build of the proposal fails closed on the same precondition.
    step "Negative: the proposal build must fail before the callback authorization"
    if replay_proposal "-before-callback" > /dev/null; then
        die "the proposal build was expected to fail; see $LAST_BATCH_LOG"
    fi
    grep -q "CallbackNotAuthorized" "$LAST_BATCH_LOG" ||
        die "the proposal did not fail on the callback authorization; see $LAST_BATCH_LOG"
    log "OK: the proposal build fails on the missing callback authorization"

    "$HARNESS_DIR/callback-auth.sh" --port "$PORT"
    LAST_BATCH_LOG="$LOG_DIR/batch-${SETUP_BATCH}-setCallbackAuthStatus.log"
    expect_non_empty_batch "setCallbackAuthStatus (the Safe that owns the auctioneer)"
    "$HARNESS_DIR/callback-auth.sh" --port "$PORT"
    expect_empty_batch "setCallbackAuthStatus re-run"

    readiness GREEN after-callback
    expect_log_line "[TODO] verify before the proposal contracts are deployed: $BACKING_KEY" \
        "the report lists the values to verify again"
    expect_log_line "[ OK ] checkPreconditions() of the activator passes" \
        "the report runs the preconditions of the activator"

    # The report as it runs before the activator is deployed: env.json has no key for it.
    # The PRICE section and the activator section fail on its absence, and the PRICE section
    # prints the answer of the USDe/USD feed, which it has no bounds to compare with.
    delete_env_value "$ACTIVATOR_KEY"
    readiness RED without-activator
    expect_log_line "[FAIL] the activator is recorded in env.json, so that the registration parameters of the USDe/USD feed can be read from it" \
        "the PRICE section fails on the missing activator"
    expect_log_line "[INFO] the USDe/USD feed price is " \
        "the PRICE section prints the answer of the USDe/USD feed"
    expect_log_line "[FAIL] the activator is recorded in env.json and advertises IYieldRepurchaseFacilityV2Activator" \
        "the activator section fails on the missing activator"
    [ "$(grep -c '\[FAIL\]' "$LAST_BATCH_LOG")" = "2" ] ||
        die "the readiness report without the activator carries other failures; see $LAST_BATCH_LOG"
    set_env_value "$ACTIVATOR_KEY" "\"$ACTIVATOR\""
}

# ========== 9. LAUNCH ========== #

rehearse_launch() {
    step "9. Launch: replay of YieldRepurchaseFacilityV2Proposal from the OCG timelock"
    local delay v1_epoch v1_next_yield heart_index price role holder pair

    # The cycle state of v1.2 that the launch carries over, read before it.
    v1_epoch="$(call "$V1" 'epoch()(uint48)')"
    v1_next_yield="$(call "$V1" 'nextYield()(uint256)')"
    heart_index="$(call "$HEART" 'getPeriodicTaskIndex(address)(uint256)' "$V1")"
    log "v1.2 before the launch: epoch $v1_epoch, nextYield $v1_next_yield, Heart task index $heart_index"

    # The script first runs the proposal through the governor in a snapshot, where the clock
    # passes the timelock delay: the answers of the feeds are dated ahead of that, so that
    # they are fresh in the snapshot and in the transactions that follow.
    delay="$(call "$OCG_TIMELOCK" 'delay()(uint256)')"
    refresh_price_feeds "$(($(block_timestamp) + delay + 3600))"

    replay_proposal "" || die "the proposal replay failed; see $LAST_BATCH_LOG"
    grep -q "Proposal executed successfully" "$LAST_BATCH_LOG" ||
        die "the proposal replay did not complete; see $LAST_BATCH_LOG"
    # The launch registers the USDe/USD feed in the PRICE module; every answer goes back to
    # the block timestamp.
    refresh_price_feeds

    expect "activator.isActivated()" "$(call "$ACTIVATOR" 'isActivated()(bool)')" true
    expect_enabled true "oracle:$ORACLE" "oracleTimelock:$ORACLE_TIMELOCK" "config:$CONFIG" \
        "timelock:$TIMELOCK" "facility:$FACILITY"
    expect "oracle.backing()" "$(call "$ORACLE" 'backing()(uint256)')" "$(env_value "$BACKING_KEY")"
    expect "config.facility()" "$(call "$CONFIG" 'facility()(address)')" "$FACILITY"
    expect "facility.configurator()" "$(call "$FACILITY" 'configurator()(address)')" "$CONFIG"
    expect "config.configOperator()" "$(call "$CONFIG" 'configOperator()(address)')" "$TIMELOCK"
    expect "oracle.configOperator()" "$(call "$ORACLE" 'configOperator()(address)')" "$ORACLE_TIMELOCK"
    expect "facility.backingVault()" "$(call "$FACILITY" 'backingVault()(address)')" "$SUSDS"
    expect "facility.getVaults() length" \
        "$(cast call "$FACILITY" 'getVaults()(address[])' --rpc-url "$RPC" | tr -d '[] ' | tr ',' '\n' | grep -c .)" 2

    # The weekly cycle of v1.2 continues in the facility.
    expect "v1.2 isShutdown()" "$(call "$V1" 'isShutdown()(bool)')" true
    expect "facility.epoch()" "$(call "$FACILITY" 'epoch()(uint48)')" "$v1_epoch"
    expect "facility.isCycleSeedable()" "$(call "$FACILITY" 'isCycleSeedable()(bool)')" false
    expect "next yield of sUSDS" "$(next_yield "$SUSDS")" "$v1_next_yield"
    expect "USDS balance of v1.2" "$(call "$USDS" 'balanceOf(address)(uint256)' "$V1")" 0
    expect "sUSDS balance of v1.2" "$(call "$SUSDS" 'balanceOf(address)(uint256)' "$V1")" 0
    expect "Heart task index of the facility" \
        "$(call "$HEART" 'getPeriodicTaskIndex(address)(uint256)' "$FACILITY")" "$heart_index"

    price="$(call "$KERNEL" 'getModuleForKeycode(bytes5)(address)' 0x5052494345)"
    expect "PRICE.isAssetApproved(USDe)" "$(call "$price" 'isAssetApproved(address)(bool)' "$USDE")" true

    # Roles: the DAO MS operates the stack, the activator keeps nothing, loop_daddy is gone.
    for role in yrf_admin backing_admin; do
        expect "DAO MS holds $role" "$(has_role "$DAO_MS" "$role")" true
    done
    for role in admin loop_daddy; do
        expect "activator holds $role" "$(has_role "$ACTIVATOR" "$role")" false
    done
    for pair in "DAO MS:$DAO_MS" "OCG timelock:$OCG_TIMELOCK"; do
        holder="${pair#*:}"
        expect "${pair%%:*} holds loop_daddy" "$(has_role "$holder" loop_daddy)" false
    done

    # A second build finds the activator used up.
    step "Negative: the proposal build must fail after the launch"
    if replay_proposal "-after-launch" > /dev/null; then
        die "the proposal build was expected to fail after the launch; see $LAST_BATCH_LOG"
    fi
    grep -q "AlreadyActivated" "$LAST_BATCH_LOG" ||
        die "the second proposal build did not fail on the used activator; see $LAST_BATCH_LOG"
    log "OK: the proposal cannot be built a second time"
}

# ========== 10. DEACTIVATION OF V1.2 ========== #

rehearse_deactivate_v1() {
    step "10. Deactivate YieldRepurchaseFacility v1.2 in the Kernel (DAO MS)"
    run_batch "$SETUP_BATCH" deactivateV1 dao
    expect_non_empty_batch "deactivateV1"
    expect_heartbeat_validated "deactivateV1"
    expect "kernel.isPolicyActive(v1.2)" "$(call "$KERNEL" 'isPolicyActive(address)(bool)' "$V1")" false
    run_batch "$SETUP_BATCH" deactivateV1 dao "" "-rerun"
    expect_empty_batch "deactivateV1 re-run"
}

# ========== 11. RECONCILIATION THROUGH THE CONFIG TIMELOCK ========== #

rehearse_reconcile() {
    step "11. Reconcile the facility through its config timelock (DAO MS as yrf_admin)"
    local delay grace clearinghouse_entry listed_args
    delay="$(call "$TIMELOCK" 'timelockDelay()(uint48)')"

    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-converged"
    expect_empty_batch "reconcile on the state of the launch"
    expect_log_line "No change needed" "reconcile reports the converged state"

    # A field that only the admin role changes stops the run.
    grace="$(env_value "$YRF_KEY.gracePeriod")"
    set_env_value "$YRF_KEY.gracePeriod" "$((grace - 3600))"
    run_batch_expect_fail "$YRF_TIMELOCK_BATCH" reconcile dao \
        "only the admin role changes this field" "" "-admin-field"
    set_env_value "$YRF_KEY.gracePeriod" "$grace"

    # A registry Clearinghouse that env.json does not declare stops the run.
    clearinghouse_entry="$(jq -c '.current.mainnet.olympus.config.YieldRepurchaseFacilityV2.clearinghouses[2]' \
        "$REPO_ROOT/$ENV_JSON")"
    set_env_value "$YRF_KEY.clearinghouses" "$(jq -c \
        '.current.mainnet.olympus.config.YieldRepurchaseFacilityV2.clearinghouses[0:2]' \
        "$REPO_ROOT/$ENV_JSON")"
    run_batch_expect_fail "$YRF_TIMELOCK_BATCH" reconcile dao \
        "of the CHREG registry is not declared in env.json" "" "-undeclared"
    set_env_value "$YRF_KEY.clearinghouses.2" "$clearinghouse_entry"

    # Four changes, each queued as its own action (actions 1 to 4 on a fresh timelock).
    set_env_value "$YRF_KEY.initialDiscount" '"40000000000000000"'
    set_env_value "$YRF_KEY.assets.sUSDe.yieldBuybackShare" '"500000000000000000"'
    set_env_value "$YRF_KEY.clearinghouses.0.included" false
    set_env_value "$YRF_KEY.clearinghouses.1.offset" '"1000000000000000000000"'
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-queue"
    expect_non_empty_batch "reconcile (queue four changes)"
    expect_log_line "Queued: increaseClearinghouseOffset" "reconcile queued the offset increase"
    expect_log_line "Queued: excludeClearinghouse" "reconcile queued the exclusion"
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-queue-rerun"
    expect_empty_batch "reconcile re-run"
    expect_log_line "Already queued as action" "reconcile leaves the pending actions alone"
    run_batch "$YRF_TIMELOCK_BATCH" executeReadyActions dao "" "-early"
    expect_empty_batch "executeReadyActions before the delay"
    expect_log_line "Not ready: executable at" "executeReadyActions reports the delayed actions"

    # env.json takes a pending change back: the run plans nothing for that key and cancels
    # nothing, and its listing reports the action that would still apply the change.
    set_env_value "$YRF_KEY.initialDiscount" "\"$(call "$FACILITY" 'initialDiscount()(uint256)')\""
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-conflict"
    expect_empty_batch "reconcile with a pending action that env.json no longer declares"
    expect_log_line "CONFLICT: sets an initial discount that differs from env.json" \
        "the listing of reconcile reports the conflict"

    # Another value for a pending change: a run of cancellations, then the replacement.
    set_env_value "$YRF_KEY.initialDiscount" '"50000000000000000"'
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-cancel-only"
    expect_non_empty_batch "reconcile (cancellation of the superseded action)"
    expect_log_line "Cancellations only: this run queues nothing" "reconcile holds its cancellation only"
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-requeue"
    expect_non_empty_batch "reconcile (queue the replacement)"

    warp "$((delay + 1))"
    # The listed ids first (the share and the exclusion), then every remaining ready action.
    listed_args="$(write_args execute-listed \
        '{"functions": [{"name": "executeReadyActions", "args": {"actionIds": [2, 3, 3]}}]}')"
    run_batch "$YRF_TIMELOCK_BATCH" executeReadyActions dao "$listed_args" "-listed"
    expect_non_empty_batch "executeReadyActions (listed ids)"
    expect_heartbeat_validated "executeReadyActions"
    expect_log_line "Considering the 2 listed action ids only" "executeReadyActions reads the listed ids"
    run_batch "$YRF_TIMELOCK_BATCH" executeReadyActions dao "" "-rest"
    expect_non_empty_batch "executeReadyActions (the remaining ready actions)"
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-after-execute"
    expect_empty_batch "reconcile after the execution"
    expect "facility.initialDiscount()" "$(call "$FACILITY" 'initialDiscount()(uint256)')" 50000000000000000
    expect "facility.clearinghouseOffset(v1.1)" "$(call "$FACILITY" 'clearinghouseOffset(address)(uint256)' \
        "$(env_value "$YRF_KEY.clearinghouses.1.address")")" 1000000000000000000000
}

# ========== 12. ASSET STATUS AND THE NEXT YIELD CORRECTION ========== #

rehearse_asset_status() {
    step "12. Asset status, next yield correction and cancellations (DAO MS, Emergency MS)"
    local delay stored decrease_args other_args correction_id enable_id
    delay="$(call "$TIMELOCK" 'timelockDelay()(uint48)')"

    # Disable sUSDe through the timelock.
    set_env_value "$YRF_KEY.assets.sUSDe.enabled" false
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-disable-asset"
    expect_non_empty_batch "reconcile (queue disableAsset)"
    expect_log_line "WARNING: disableAsset closes the live bond market" "reconcile warns about disableAsset"
    warp "$((delay + 1))"
    run_batch "$YRF_TIMELOCK_BATCH" executeReadyActions dao "" "-disable-asset"
    expect_non_empty_batch "executeReadyActions (disableAsset)"

    # The imperative correction of the stored next yield, from an args file.
    stored="$(next_yield "$SUSDE")"
    [ "$stored" != "0" ] || die "the stored next yield of sUSDe is zero; the correction needs a non-zero value"
    decrease_args="$(write_args decrease-next-yield "{\"functions\": [{\"name\": \"queueDecreaseNextYield\",
        \"args\": {\"asset\": \"sUSDe\", \"expectedNextYield\": \"$stored\", \"newNextYield\": \"0\"}}]}")"
    run_batch "$YRF_TIMELOCK_BATCH" queueDecreaseNextYield dao "$decrease_args"
    expect_non_empty_batch "queueDecreaseNextYield"
    correction_id="$(($(call "$TIMELOCK" 'nextActionId()(uint64)') - 1))"
    run_batch "$YRF_TIMELOCK_BATCH" queueDecreaseNextYield dao "$decrease_args" "-rerun"
    expect_empty_batch "queueDecreaseNextYield re-run"
    expect_log_line "Already queued as action" "queueDecreaseNextYield leaves its pending action alone"
    other_args="$(write_args decrease-next-yield-other "{\"functions\": [{\"name\": \"queueDecreaseNextYield\",
        \"args\": {\"asset\": \"sUSDe\", \"expectedNextYield\": \"$stored\", \"newNextYield\": \"1\"}}]}")"
    run_batch_expect_fail "$YRF_TIMELOCK_BATCH" queueDecreaseNextYield dao \
        "the next yield domain of the vault is reserved by action" "$other_args" "-other-values"

    # enableAsset needs the next yield domain, which the correction holds: the run stops and
    # does not cancel an action that was queued from an args file.
    set_env_value "$YRF_KEY.assets.sUSDe.enabled" true
    run_batch_expect_fail "$YRF_TIMELOCK_BATCH" reconcile dao \
        "it was queued from an args file, not from env.json" "" "-imperative-holder"

    # The DAO MS cancels its own action by id; a second cancellation is refused.
    run_batch "$YRF_TIMELOCK_BATCH" cancelQueuedAction dao \
        "$(action_args cancelQueuedAction "$correction_id")"
    expect_non_empty_batch "cancelQueuedAction (DAO MS as the proposer)"
    run_batch_expect_fail "$YRF_TIMELOCK_BATCH" cancelQueuedAction dao \
        "the action is already cancelled" "$(action_args cancelQueuedAction "$correction_id")" "-again"

    # enableAsset is queued, cancelled by the Emergency MS, and queued again.
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-enable-asset"
    expect_non_empty_batch "reconcile (queue enableAsset)"
    expect_log_line "WARNING: enableAsset zeroes the stored next yield" "reconcile warns about enableAsset"
    enable_id="$(($(call "$TIMELOCK" 'nextActionId()(uint64)') - 1))"
    run_batch "$YRF_TIMELOCK_BATCH" cancelQueuedActionEmergency emergency \
        "$(action_args cancelQueuedActionEmergency "$enable_id")"
    expect_non_empty_batch "cancelQueuedActionEmergency (Emergency MS)"
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-enable-asset-again"
    expect_non_empty_batch "reconcile (queue enableAsset again)"
    warp "$((delay + 1))"
    run_batch "$YRF_TIMELOCK_BATCH" executeReadyActions dao "" "-enable-asset"
    expect_non_empty_batch "executeReadyActions (enableAsset)"
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-asset-converged"
    expect_empty_batch "reconcile after the asset status round trip"
    expect "next yield of sUSDe after enableAsset" "$(next_yield "$SUSDE")" 0
}

# ========== 13. LIFECYCLE AND EMERGENCY LEVERS OF THE FACILITY ========== #

rehearse_facility_lifecycle() {
    step "13. Step gas limit, rescue, emergency levers and reEnable of the facility stack"
    local rescue_args pool_args

    # The step gas limit, by a direct call.
    set_env_value "$YRF_KEY.stepGasLimit" 2500000
    run_batch "$YRF_TIMELOCK_BATCH" reconcile dao "" "-step-gas-note"
    expect_empty_batch "reconcile with a step gas limit difference"
    expect_log_line "YieldRepurchaseFacilityV2Batch.reconcileStepGasLimit" \
        "reconcile points at the entry point of the step gas limit"
    run_batch "$YRF_BATCH" reconcileStepGasLimit dao
    expect_non_empty_batch "reconcileStepGasLimit"
    expect_heartbeat_validated "reconcileStepGasLimit"
    expect "facility.stepGasLimit()" "$(call "$FACILITY" 'stepGasLimit()(uint32)')" 2500000
    run_batch "$YRF_BATCH" reconcileStepGasLimit dao "" "-rerun"
    expect_empty_batch "reconcileStepGasLimit re-run"

    # Rescue of a token outside the buyback pools: WETH sent to the facility by mistake.
    send_as "$DEPLOYER_ADDR" "$WETH" 'deposit()' --value 1ether
    send_as "$DEPLOYER_ADDR" "$WETH" 'transfer(address,uint256)' "$FACILITY" 1000000000000000000
    rescue_args="$(write_args rescue "{\"functions\": [{\"name\": \"rescue\", \"args\": {\"token\": \"$WETH\"}}]}")"
    run_batch "$YRF_BATCH" rescue dao "$rescue_args"
    expect_non_empty_batch "rescue"
    expect "WETH balance of the facility" "$(call "$WETH" 'balanceOf(address)(uint256)' "$FACILITY")" 0
    run_batch "$YRF_BATCH" rescue dao "$rescue_args" "-rerun"
    expect_empty_batch "rescue re-run"
    pool_args="$(write_args rescue-pool "{\"functions\": [{\"name\": \"rescue\", \"args\": {\"token\": \"$SUSDS\"}}]}")"
    run_batch_expect_fail "$YRF_BATCH" rescue dao "is not rescuable" "$pool_args" "-pool-token"

    # Stop the purchases, return the funds, resume.
    run_batch_expect_fail "$YRF_BATCH" returnFundsToTreasuryEmergencyMS emergency \
        "the facility is enabled, and returnFundsToTreasury runs on a disabled facility only" "" "-enabled"
    run_batch "$YRF_BATCH" stopPurchasesEmergencyMS emergency
    expect_non_empty_batch "stopPurchasesEmergencyMS"
    expect_heartbeat_validated "stopPurchasesEmergencyMS"
    expect_enabled false "facility:$FACILITY"
    expect_enabled true "config:$CONFIG" "timelock:$TIMELOCK"
    run_batch "$YRF_BATCH" stopPurchasesEmergencyMS emergency "" "-rerun"
    expect_empty_batch "stopPurchasesEmergencyMS re-run"

    # The treasury tops the pool up, so that the sweep has something to return on any fork.
    send_as "$TREASURY" "$SUSDS" 'transfer(address,uint256)' "$FACILITY" 1000000000000000000
    # The sweep hands a set amount of gas to every vault step, far above what it uses: the gas
    # limit forge derives from the gas used has to be raised for this one call.
    BATCH_GAS_ESTIMATE_MULTIPLIER=8000 run_batch "$YRF_BATCH" returnFundsToTreasuryEmergencyMS emergency
    expect_non_empty_batch "returnFundsToTreasuryEmergencyMS"
    expect_log_line "Gas that has to be left before every step" "returnFundsToTreasury prints the gas of a step"
    expect "sUSDS balance of the facility" "$(call "$SUSDS" 'balanceOf(address)(uint256)' "$FACILITY")" 0
    run_batch "$YRF_BATCH" returnFundsToTreasuryEmergencyMS emergency "" "-rerun"
    expect_empty_batch "returnFundsToTreasuryEmergencyMS re-run"

    run_batch "$YRF_BATCH" reEnable dao
    expect_non_empty_batch "reEnable (the facility, inside its grace window)"
    expect_heartbeat_validated "reEnable"
    expect_enabled true "facility:$FACILITY"
    run_batch "$YRF_BATCH" reEnable dao "" "-rerun"
    expect_empty_batch "reEnable re-run"

    # Freeze the configuration, resume.
    run_batch "$YRF_BATCH" freezeConfigEmergencyMS emergency
    expect_non_empty_batch "freezeConfigEmergencyMS"
    expect_enabled false "config:$CONFIG" "timelock:$TIMELOCK"
    expect_enabled true "facility:$FACILITY"
    run_batch "$YRF_BATCH" freezeConfigEmergencyMS emergency "" "-rerun"
    expect_empty_batch "freezeConfigEmergencyMS re-run"
    run_batch_expect_fail "$YRF_TIMELOCK_BATCH" reconcile dao \
        "is disabled, and queueing requires it enabled" "" "-frozen"
    run_batch "$YRF_BATCH" reEnable dao "" "-after-freeze"
    expect_non_empty_batch "reEnable (the configuration policy and the config timelock)"
    expect_enabled true "config:$CONFIG" "timelock:$TIMELOCK"

    # Halt everything, with the heart beat validation switched off the way an operator
    # switches it off for a Heart that fails for a reason the lever does not remove; resume.
    EMERGENCY_SKIP_HEARTBEAT_VALIDATION=true run_batch "$YRF_BATCH" haltAllEmergencyMS emergency
    expect_non_empty_batch "haltAllEmergencyMS"
    expect_log_line "EMERGENCY_SKIP_HEARTBEAT_VALIDATION is set" \
        "haltAllEmergencyMS reports that the heart beat is not simulated"
    if grep -q "All heart beats validated successfully" "$LAST_BATCH_LOG"; then
        die "haltAllEmergencyMS validated the heart beat although the validation was switched off; see $LAST_BATCH_LOG"
    fi
    expect_enabled false "config:$CONFIG" "timelock:$TIMELOCK" "facility:$FACILITY"
    run_batch "$YRF_BATCH" haltAllEmergencyMS emergency "" "-rerun"
    expect_empty_batch "haltAllEmergencyMS re-run"
    run_batch "$YRF_BATCH" reEnable dao "" "-after-halt"
    expect_non_empty_batch "reEnable (the three policies)"
    expect_enabled true "config:$CONFIG" "timelock:$TIMELOCK" "facility:$FACILITY"
    run_batch "$YRF_BATCH" reEnable dao "" "-after-halt-rerun"
    expect_empty_batch "reEnable re-run after the halt"
}

# ========== 14. BACKING ORACLE ========== #

rehearse_oracle() {
    step "14. Backing oracle: backing through its timelock, lifecycle and emergency levers"
    local first_id second_id third_id backing unit step_up final too_large

    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-converged"
    expect_empty_batch "reconcileBacking on the state of the launch"

    # The values of the rehearsal are derived from the backing of env.json in units of 1e15,
    # which fit the shell arithmetic: one update moves the backing by at most 10%.
    backing="$(env_value "$BACKING_KEY")"
    unit="${backing%000000000000000}"
    [ "$unit" != "$backing" ] || die "$BACKING_KEY ($backing) is not a multiple of 1e15"
    step_up="$((unit * 105 / 100))000000000000000"
    final="$((unit * 104 / 100))000000000000000"
    too_large="$((unit * 130 / 100))000000000000000"

    # A step beyond the bound of one update stops the run with the bound in the message.
    set_env_value "$BACKING_KEY" "\"$too_large\""
    run_batch_expect_fail "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao \
        "is outside the bound of one update [" "" "-too-large"

    set_env_value "$BACKING_KEY" "\"$step_up\""
    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-queue"
    expect_non_empty_batch "reconcileBacking (queue setBacking)"
    first_id="$(($(call "$ORACLE_TIMELOCK" 'nextActionId()(uint64)') - 1))"
    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-queue-rerun"
    expect_empty_batch "reconcileBacking re-run"
    run_batch "$ORACLE_TIMELOCK_BATCH" executeReadyActions dao "" "-early"
    expect_empty_batch "executeReadyActions of the oracle timelock before the delay"

    # Another value: the pending action holds the one backing key, so the run cancels it.
    set_env_value "$BACKING_KEY" "\"$final\""
    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-cancel-only"
    expect_non_empty_batch "reconcileBacking (cancellation of the superseded action)"
    expect_log_line "Cancellations only: this run queues nothing" "reconcileBacking holds its cancellation only"
    expect "oracle action $first_id is cancelled" "$(cast call "$ORACLE_TIMELOCK" \
        'getQueuedAction(uint64)((address,uint48,uint48,uint48,bool,bool,(address,bytes4,bytes)[]))' \
        "$first_id" --rpc-url "$RPC" | tr -d '()' | awk -F', ' '{print $6}')" true
    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-requeue"
    expect_non_empty_batch "reconcileBacking (queue the replacement)"
    second_id="$(($(call "$ORACLE_TIMELOCK" 'nextActionId()(uint64)') - 1))"

    # Cancellations by id: the DAO MS as the proposer, then the Emergency MS.
    run_batch "$ORACLE_TIMELOCK_BATCH" cancelQueuedAction dao \
        "$(action_args cancelQueuedAction "$second_id")"
    expect_non_empty_batch "cancelQueuedAction of the oracle timelock (DAO MS)"
    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-requeue-2"
    expect_non_empty_batch "reconcileBacking (queue again)"
    third_id="$(($(call "$ORACLE_TIMELOCK" 'nextActionId()(uint64)') - 1))"
    run_batch "$ORACLE_TIMELOCK_BATCH" cancelQueuedActionEmergency emergency \
        "$(action_args cancelQueuedActionEmergency "$third_id")"
    expect_non_empty_batch "cancelQueuedActionEmergency of the oracle timelock (Emergency MS)"
    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-requeue-3"
    expect_non_empty_batch "reconcileBacking (queue for the execution)"

    warp "$(($(call "$ORACLE_TIMELOCK" 'timelockDelay()(uint48)') + 1))"
    run_batch "$ORACLE_TIMELOCK_BATCH" executeReadyActions dao "" "-ready"
    expect_non_empty_batch "executeReadyActions of the oracle timelock"
    expect_heartbeat_validated "executeReadyActions of the oracle timelock"
    expect "oracle.backing()" "$(call "$ORACLE" 'backing()(uint256)')" "$final"
    run_batch "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao "" "-after-execute"
    expect_empty_batch "reconcileBacking after the execution"

    # Freeze the updates, resume.
    run_batch "$ORACLE_BATCH" freezeUpdatesEmergencyMS emergency
    expect_non_empty_batch "freezeUpdatesEmergencyMS"
    expect_enabled false "oracleTimelock:$ORACLE_TIMELOCK"
    expect_enabled true "oracle:$ORACLE"
    run_batch "$ORACLE_BATCH" freezeUpdatesEmergencyMS emergency "" "-rerun"
    expect_empty_batch "freezeUpdatesEmergencyMS re-run"
    run_batch_expect_fail "$ORACLE_TIMELOCK_BATCH" reconcileBacking dao \
        "is disabled, and queueing requires it enabled" "" "-frozen"
    run_batch "$ORACLE_BATCH" reEnable dao
    expect_non_empty_batch "reEnable of the oracle timelock"
    expect_enabled true "oracleTimelock:$ORACLE_TIMELOCK"

    # Halt the oracle: the facility keeps beating with a closed price gate, and its reEnable
    # is refused until the oracle is back.
    run_batch "$ORACLE_BATCH" haltAllEmergencyMS emergency
    expect_non_empty_batch "haltAllEmergencyMS of the oracle"
    expect_heartbeat_validated "haltAllEmergencyMS of the oracle"
    expect_enabled false "oracle:$ORACLE" "oracleTimelock:$ORACLE_TIMELOCK"
    run_batch "$ORACLE_BATCH" haltAllEmergencyMS emergency "" "-rerun"
    expect_empty_batch "haltAllEmergencyMS of the oracle re-run"

    run_batch "$YRF_BATCH" stopPurchasesEmergencyMS emergency "" "-oracle-down"
    expect_non_empty_batch "stopPurchasesEmergencyMS while the oracle is down"
    run_batch_expect_fail "$YRF_BATCH" reEnable dao \
        "re-enable the oracle first with BackingOracleBatch.reEnable" "" "-oracle-down"

    run_batch "$ORACLE_BATCH" reEnable dao "" "-after-halt"
    expect_non_empty_batch "reEnable of the oracle and its timelock"
    expect_enabled true "oracle:$ORACLE" "oracleTimelock:$ORACLE_TIMELOCK"
    run_batch "$ORACLE_BATCH" reEnable dao "" "-after-halt-rerun"
    expect_empty_batch "reEnable of the oracle re-run"
    run_batch "$YRF_BATCH" reEnable dao "" "-oracle-up"
    expect_non_empty_batch "reEnable of the facility once the oracle is back"
    expect_enabled true "facility:$FACILITY"
}

# ========== 15. FINAL STATE ========== #

print_final_state() {
    step "15. State after the rehearsal"
    echo "facility.isEnabled()         = $(call "$FACILITY" 'isEnabled()(bool)')"
    echo "config.isEnabled()           = $(call "$CONFIG" 'isEnabled()(bool)')"
    echo "timelock.isEnabled()         = $(call "$TIMELOCK" 'isEnabled()(bool)')"
    echo "oracle.isEnabled()           = $(call "$ORACLE" 'isEnabled()(bool)')"
    echo "oracleTimelock.isEnabled()   = $(call "$ORACLE_TIMELOCK" 'isEnabled()(bool)')"
    echo "facility.initialDiscount()   = $(call "$FACILITY" 'initialDiscount()(uint256)')"
    echo "facility.maxPricePremium()   = $(call "$FACILITY" 'maxPricePremium()(uint256)')"
    echo "facility.stepGasLimit()      = $(call "$FACILITY" 'stepGasLimit()(uint32)')"
    echo "facility.epoch()             = $(call "$FACILITY" 'epoch()(uint48)')"
    echo "oracle.backing()             = $(call "$ORACLE" 'backing()(uint256)')"
    echo "timelock.nextActionId()      = $(call "$TIMELOCK" 'nextActionId()(uint64)')"
    echo "oracleTimelock.nextActionId()= $(call "$ORACLE_TIMELOCK" 'nextActionId()(uint64)')"
    echo "kernel.isPolicyActive(v1.2)  = $(call "$KERNEL" 'isPolicyActive(address)(bool)' "$V1")"
    echo "DAO MS yrf_admin             = $(has_role "$(env_value olympus.multisig.dao)" yrf_admin)"
    echo "DAO MS backing_admin         = $(has_role "$(env_value olympus.multisig.dao)" backing_admin)"
}
