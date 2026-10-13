// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: calls in loops are simulated rather than paid for
// on-chain, and a failed `require` is meant to abort the whole run with its message.
// forge-lint: disable-start(calls-loop,custom-errors,require-revert-in-loop)

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {CCIPTokenPoolConfigKeyLib} from "src/policies/utils/CCIPTokenPoolConfigKeyLib.sol";
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";
import {CCIPQueueLib} from "src/scripts/ops/lib/CCIPQueueLib.sol";

// Contracts
import {Kernel, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title CCIPRouteReconcileBatch
/// @notice Declarative route reconciliation for the CCIP token pool through the
///         CCIPTokenPoolConfigTimelock. `env.json` is the desired state; the pool is the live
///         state; the batch contains only the typed timelock actions that converge the two.
///
///         Entry points:
///         - `reconcileRoutes` (DAO MS as `bridge_admin`): compare every route declared under
///           `olympus.config.CCIP.routes` with the pool, field by field, and queue the minimal
///           set of `queue*` calls. Pending actions that already carry the same change are
///           left alone. When a pending action holds a needed key with another intent, or has
///           expired, the run holds its cancellations only and queues nothing: execution is
///           permissionless, so the holder may execute before the batch lands, and the
///           replacements are planned afresh by the next run from the state the cancellations
///           leave. After the plan the run lists every unresolved queued action: cancelled by
///           this run, carrying a planned change, or outside the plan, with the sub-actions that
///           conflict with `env.json` where the desired state decides it.
///         - `executeReadyActions` (anyone): execute every queued action whose delay has elapsed
///           and whose execution would succeed, or only the action ids listed in the args file;
///           report the others.
///         - `cancelQueuedAction` (DAO MS as proposer, or any owner for an expired action) and
///           `cancelQueuedActionEmergency` (Emergency MS): cancel one action by id, which is the
///           only way to release the configuration keys of an expired or stale action.
///
///         Each change is queued as its own action so that a queued action that turned stale
///         does not block the execution of the other queued actions, with one exception: a
///         remote pool change and a rate limit change of one route go out as one ordered batch
///         action, the pool change first, so that the limits of the route cannot be restored
///         while a remote pool that is to go is still accepted. The reconcile run itself is
///         atomic and fails closed, so an invalid desired route reverts the whole run before
///         anything is queued. The timelock reserves one key per configuration domain and
///         refuses a second unresolved action on the same domain, so at most one remote-pool
///         change per route, or one route-identity change, can be queued per run; the remainder
///         is reported as deferred and queued by a later run once the first action has executed,
///         and a rate limit change waits for the last remote pool change of its route: a remote
///         pool change planned on its own cancels a pending rate limit action of the route, so
///         that the limits cannot return before the pool change. A queued batch that already
///         carries the planned remote pool change together with the desired limits is left alone,
///         whether or not the route is named in `restoreContained`.
///
///         The limits of a contained route (`isChainDisabled`) are restored only when the route
///         is named in the `restoreContained` list of the args file; otherwise the route is
///         listed as contained and its limits are left alone, while its remote pool and remote
///         token changes are planned as for any route.
contract CCIPRouteReconcileBatch is BatchScriptV2 {
    using stdJson for string;

    // =========== DATA STRUCTURES =========== //

    /// @notice One change to queue on the timelock: a single config call, or an ordered batch
    ///         of config calls that executes as one action.
    /// @param description The change, for the logs.
    /// @param actions The config calls, in execution order; each targets the config policy.
    /// @param queueCall The timelock call that queues the change.
    /// @param keys The keys the change reserves: the union over its config calls.
    /// @param clearKeys The keys the change does not reserve but whose pending holder the run
    ///        cancels: the rate limits key of a route whose remote pool change is planned
    ///        without its limits.
    /// @param skipped Whether an unexpired pending action already carries the change.
    struct Planned {
        string description;
        ITimelockBatchQueue.BatchAction[] actions;
        bytes queueCall;
        bytes32[] keys;
        bytes32[] clearKeys;
        bool skipped;
    }

    /// @notice The one remote pool change of a route that a run queues.
    /// @param due Whether the route has a remote pool change.
    /// @param name The config function, for the description.
    /// @param call The config call.
    /// @param queueCall The typed timelock call that queues the config call on its own.
    struct PoolChange {
        bool due;
        string name;
        ITimelockBatchQueue.BatchAction call;
        bytes queueCall;
    }

    // =========== STATE =========== //

    Planned[] internal _plan;
    uint64[] internal _cancelledIds;
    uint64[] internal _expectedExecuted;
    uint64 internal _expectedCancelled;

    /// @notice The remote chain names whose contained limits this run restores.
    string[] internal _restoreContained;

    /// @notice The contained routes whose limit restore this run skipped.
    string[] internal _containedSkipped;

    // =========== ENTRY POINTS =========== //

    /// @notice Queues the timelock actions that converge the pool routes to `env.json`, or
    ///         cancels the pending actions that stand in their way.
    /// @dev    Desired routes are processed in remote chain name order; within a route the
    ///         identity change comes first, then one remote-pool change (additions before
    ///         removals) and the rate limits, as one batch action when both are due. A removal
    ///         is queued only for a route whose entry carries `enabled: false`; a live route that
    ///         `env.json` does not declare fails the run, since the declaration must be complete
    ///         before anything is queued.
    ///
    ///         Args file (optional):
    ///         `{"functions": [{"name": "reconcileRoutes", "args": {"restoreContained": ["solana"]}}]}`
    ///         names the contained routes whose approved limits this run restores; without it
    ///         the limits of a contained route are left alone.
    ///
    ///         A run that cancels at least one pending action holds the cancellations only: the
    ///         plan output lists the replacements, and they are queued by the next run once the
    ///         cancellations have landed. A cancellation of an action that executed in between
    ///         reverts with `ITimelockBatchQueue_ActionAlreadyExecuted` and fails the batch; the
    ///         next run plans from the resulting state.
    ///
    ///         The plan describes the pool state only, so the run ends with every unresolved
    ///         queued action: cancelled by this run, carrying a planned change, or outside the
    ///         plan, where a `removeChain` of a route declared enabled, an `addChain` of a route
    ///         not declared or declared disabled, and a payload that differs from the desired
    ///         values of its route are marked as conflicts. An action outside the plan executes
    ///         once ready unless it is cancelled.
    ///
    ///         Reverts if:
    ///         - The config policy, the timelock and the pool are not bound to each other.
    ///         - The config policy does not own the pool or does not name the timelock as its
    ///           config operator.
    ///         - The config policy or the timelock is disabled.
    ///         - The batch owner does not hold `bridge_admin`.
    ///         - A desired route is malformed (see `CCIPConfigLib`).
    ///         - A name in `restoreContained` is not a route declared with `enabled: true`.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (optional; may carry
    ///        "reconcileRoutes.restoreContained").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function reconcileRoutes(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        // The batch touches only the config timelock
        _skipHeartbeatValidation = true;

        (
            ICCIPTokenPoolConfig config,
            ICCIPTokenPoolConfigTimelock timelock,
            ICCIPTokenPoolAdmin pool
        ) = _contracts();

        console2.log("\n=== Reconcile CCIP routes through the config timelock ===");
        console2.log("CCIPTokenPoolConfig:", address(config));
        console2.log("CCIPTokenPoolConfigTimelock:", address(timelock));
        console2.log("Token pool:", address(pool));

        _requireQueueable(config, timelock, pool);

        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, chain);
        uint64[] memory liveSelectors = pool.getSupportedChains();
        _readRestoreContained(desired);

        _logLiveRoutes(pool, liveSelectors);
        _logDesiredRoutes(desired);

        console2.log("\n--- Plan ---");
        for (uint256 i = 0; i < desired.length; ++i) {
            _planRoute(config, IConfigTimelockBatchQueue(address(timelock)), pool, desired[i]);
        }
        _requireRoutesDeclared(desired, liveSelectors);
        _logContainedSkipped();

        console2.log("\n--- Queue ---");
        _planCancellations(timelock);
        if (_cancelledIds.length > 0) {
            _logCancelOnlyRun(timelock);
        } else {
            for (uint256 i = 0; i < _plan.length; ++i) {
                _queuePlanned(timelock, i);
            }
            if (_plan.length == 0) {
                console2.log(
                    _containedSkipped.length == 0
                        ? "No change needed: the pool matches env.json. This describes the pool state only; the unresolved queued actions are listed below."
                        : "No change queued: the pool matches env.json apart from the contained routes listed above, whose limits are restored only for a route named in restoreContained. This describes the pool state only; the unresolved queued actions are listed below."
                );
            }
        }
        _logUnresolvedActions(IConfigTimelockBatchQueue(address(timelock)), desired);

        _setPostBatchValidateSelector(this._validateReconcileRoutes.selector);

        proposeBatch();
    }

    /// @notice Executes the queued actions whose delay has elapsed, whose window has not closed
    ///         and whose execution succeeds in a dry run: every such action, or only the listed
    ///         ones when the args file names them. Anyone may run it.
    /// @dev    Args file (optional):
    ///         `{"functions": [{"name": "executeReadyActions", "args": {"actionIds": [1]}}]}`
    ///         restricts the run to the listed ids. Every considered action is logged with its
    ///         proposer, window and sub-actions. An action that does not exist, is executed or
    ///         cancelled, is not ready, has expired, or would revert (for instance with
    ///         `ConfigStateChanged` after the route moved, or `NotEnabled` while a policy is
    ///         disabled) is reported with the reason and left out; an expired or stale action
    ///         keeps its keys until it is cancelled. Each dry run is isolated, while the included
    ///         executions share one transaction: with a multisig owner and more than one of them,
    ///         the Safe multisend is atomic and one reverting execution fails all of them.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner; any owner may execute.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (optional; may carry
    ///        "executeReadyActions.actionIds").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function executeReadyActions(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _skipHeartbeatValidation = true;

        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(
            _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock")
        );
        uint64 nextActionId = timelock.nextActionId();

        console2.log("\n=== Execute ready CCIP config timelock actions ===");
        console2.log("CCIPTokenPoolConfigTimelock:", address(timelock));
        console2.log("Block timestamp:", block.timestamp);
        console2.log("Queued actions so far:", nextActionId - 1);

        uint64[] memory candidates = _executionCandidates(timelock);
        for (uint256 i = 0; i < candidates.length; ++i) {
            _considerExecution(timelock, nextActionId, candidates[i]);
        }

        if (_expectedExecuted.length == 0) {
            console2.log("No action is ready to execute.");
        } else if (_isMultiSig && _expectedExecuted.length > 1) {
            console2.log(
                "The Safe multisend is atomic: one reverting execution fails all",
                _expectedExecuted.length,
                "executions."
            );
        }

        _setPostBatchValidateSelector(this._validateExecuted.selector);

        proposeBatch();
    }

    /// @notice Cancels one queued action (DAO MS as the proposer of the action, or any `admin` or
    ///         `emergency` holder as owner; any owner once the action has expired).
    /// @dev    Args file: `{"functions": [{"name": "cancelQueuedAction", "args": {"actionId": 1}}]}`.
    ///
    ///         Reverts if:
    ///         - The action does not exist, or is already executed or cancelled.
    ///         - The action has not expired and the batch owner is neither the proposer nor an
    ///           `admin` or `emergency` holder.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (must contain "cancelQueuedAction.actionId").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function cancelQueuedAction(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _planCancel("cancelQueuedAction");
        proposeBatch();
    }

    /// @notice Cancels one queued action with the Emergency MS as owner.
    /// @dev    Same args file as `cancelQueuedAction`, under the function name
    ///         `cancelQueuedActionEmergency`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (must contain "cancelQueuedActionEmergency.actionId").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function cancelQueuedActionEmergency(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    )
        external
        setUpWithEmergencyMS(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_)
    {
        _planCancel("cancelQueuedActionEmergency");
        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `reconcileRoutes`: every cancelled action is cancelled,
    ///         and in a run without cancellations every queued change holds its keys.
    function _validateReconcileRoutes() external view {
        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(
            _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock")
        );

        console2.log("\nValidating reconcileRoutes post-batch state");
        for (uint256 i = 0; i < _cancelledIds.length; ++i) {
            require(
                timelock.getQueuedAction(_cancelledIds[i]).cancelled,
                string.concat("Action ", vm.toString(_cancelledIds[i]), " is not cancelled")
            );
            console2.log("  Action", _cancelledIds[i], "is cancelled");
        }
        // A run that cancels queues nothing; the replacements are checked by the next run
        if (_cancelledIds.length > 0) {
            console2.log("  Nothing was queued in this run");
            console2.log("reconcileRoutes post-batch validation passed");
            return;
        }
        for (uint256 i = 0; i < _plan.length; ++i) {
            Planned memory planned = _plan[i];
            if (planned.skipped) continue;
            for (uint256 k = 0; k < planned.keys.length; ++k) {
                uint64 actionId = timelock.pendingActionId(planned.keys[k]);
                require(
                    actionId != 0,
                    string.concat("No pending action holds the key of: ", planned.description)
                );
                require(
                    _holdsChange(timelock.getQueuedAction(actionId), planned),
                    string.concat("The pending action does not carry: ", planned.description)
                );
            }
            console2.log("  Queued:", planned.description);
        }
        console2.log("reconcileRoutes post-batch validation passed");
    }

    /// @notice Validates the state after `executeReadyActions`.
    function _validateExecuted() external view {
        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(
            _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock")
        );

        console2.log("\nValidating executeReadyActions post-batch state");
        for (uint256 i = 0; i < _expectedExecuted.length; ++i) {
            require(
                timelock.getQueuedAction(_expectedExecuted[i]).executed,
                string.concat("Action ", vm.toString(_expectedExecuted[i]), " is not executed")
            );
            console2.log("  Action", _expectedExecuted[i], "is executed");
        }
        console2.log("executeReadyActions post-batch validation passed");
    }

    /// @notice Validates the state after a cancellation.
    function _validateCancelled() external view {
        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(
            _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock")
        );

        console2.log("\nValidating cancellation post-batch state");
        require(
            timelock.getQueuedAction(_expectedCancelled).cancelled,
            string.concat("Action ", vm.toString(_expectedCancelled), " is not cancelled")
        );
        console2.log("  Action", _expectedCancelled, "is cancelled");
    }

    // =========== PLANNING =========== //

    function _planRoute(
        ICCIPTokenPoolConfig config_,
        IConfigTimelockBatchQueue queue_,
        ICCIPTokenPoolAdmin pool_,
        CCIPConfigLib.DesiredRoute memory desired_
    ) internal {
        uint64 selector = desired_.chainSelector;
        CCIPConfigLib.LiveRoute memory live = CCIPConfigLib.liveRoute(pool_, selector);
        console2.log("\nRoute", desired_.remoteChain, "selector", selector);

        if (!desired_.enabled) {
            if (!live.exists) {
                console2.log("  Declared with enabled=false and not configured. Nothing to do.");
                return;
            }
            console2.log(
                "  WARNING: removing the route rejects in-flight messages from its remote pools."
            );
            // Surface the config policy's own validation before queueing
            config_.validateRemoveChain(selector);
            _addPlanned(
                string.concat("removeChain(", desired_.remoteChain, ")"),
                _single(
                    _configCall(
                        address(config_),
                        ICCIPTokenPoolConfig.removeChain.selector,
                        abi.encode(selector)
                    )
                ),
                abi.encodeCall(ICCIPTokenPoolConfigTimelock.queueRemoveChain, (selector)),
                _routeKeys(address(config_), selector)
            );
            return;
        }

        if (!live.exists) {
            ICCIPTokenPoolAdmin.ChainUpdate memory update = _chainUpdate(desired_);
            // Surface the config policy's own validation before queueing
            config_.validateAddChain(update);
            _addPlanned(
                string.concat("addChain(", desired_.remoteChain, ")"),
                _single(
                    _configCall(
                        address(config_),
                        ICCIPTokenPoolConfig.addChain.selector,
                        abi.encode(update)
                    )
                ),
                abi.encodeCall(ICCIPTokenPoolConfigTimelock.queueAddChain, (update)),
                _routeKeys(address(config_), selector)
            );
            return;
        }

        CCIPConfigLib.RouteDiff memory diff = CCIPConfigLib.diffRoute(desired_, live);
        if (!CCIPConfigLib.hasChanges(diff)) {
            console2.log("  Matches env.json. Nothing to do.");
            return;
        }

        if (diff.remoteTokenDiffers) {
            console2.log("  Remote token differs: queueing setRemoteToken.");
            if (diff.poolsToAdd.length > 0 || diff.poolsToRemove.length > 0 || diff.limitsDiffer) {
                console2.log(
                    "  Deferred: remote pool or rate limit changes of this route are queued by a later run, once setRemoteToken has executed (it reserves every domain of the route)."
                );
            }
            if (diff.limitsDiffer && config_.isChainDisabled(selector)) {
                _noteContained(desired_.remoteChain);
            }
            config_.validateSetRemoteToken(selector, desired_.remoteToken);
            _addPlanned(
                string.concat("setRemoteToken(", desired_.remoteChain, ")"),
                _single(
                    _configCall(
                        address(config_),
                        ICCIPTokenPoolConfig.setRemoteToken.selector,
                        abi.encode(selector, desired_.remoteToken)
                    )
                ),
                abi.encodeCall(
                    ICCIPTokenPoolConfigTimelock.queueSetRemoteToken,
                    (selector, desired_.remoteToken)
                ),
                _routeKeys(address(config_), selector)
            );
            return;
        }

        _planRouteFields(config_, queue_, desired_, live, diff);
    }

    /// @notice Plans the remote pool change and the rate limit change of a live route whose
    ///         identity matches: one remote pool change per run, and the rate limits with it as
    ///         one batch action when both are due. The limits of a contained route are planned
    ///         only when the route is named in `restoreContained`, or when a queued batch already
    ///         carries the planned remote pool change together with them. A remote pool change
    ///         planned without the limits clears the rate limits key of the route.
    function _planRouteFields(
        ICCIPTokenPoolConfig config_,
        IConfigTimelockBatchQueue queue_,
        CCIPConfigLib.DesiredRoute memory desired_,
        CCIPConfigLib.LiveRoute memory live_,
        CCIPConfigLib.RouteDiff memory diff_
    ) internal {
        PoolChange memory poolChange = _planPoolChange(config_, desired_, diff_);
        (bool limitsChange, bool containedSkipped) = _limitsDue(config_, desired_, live_, diff_);
        if (limitsChange && _poolChangeCount(diff_) > 1) {
            console2.log(
                "  Deferred: the rate limit change rides in the batch that queues the last remote pool change of this route."
            );
            limitsChange = false;
        }
        if (
            containedSkipped &&
            poolChange.due &&
            _poolChangeCount(diff_) == 1 &&
            _restoreBatchQueued(queue_, config_, desired_, poolChange.call)
        ) {
            console2.log(
                "  Contained: a queued action already carries this remote pool change together with the limit restore; left alone."
            );
            _containedSkipped.pop();
            limitsChange = true;
        }

        if (poolChange.due && limitsChange) {
            // One action: the remote pool change executes before the limits are written
            ITimelockBatchQueue.BatchAction[]
                memory actions = new ITimelockBatchQueue.BatchAction[](2);
            actions[0] = poolChange.call;
            actions[1] = _rateLimitsCall(config_, desired_);
            _addPlanned(
                string.concat(poolChange.name, " + setChainRateLimits(", desired_.remoteChain, ")"),
                actions,
                abi.encodeCall(ICCIPTokenPoolConfigTimelock.queueBatch, (actions)),
                _twoKeys(
                    CCIPTokenPoolConfigKeyLib.remotePoolsKey(
                        address(config_),
                        desired_.chainSelector
                    ),
                    CCIPTokenPoolConfigKeyLib.rateLimitsKey(
                        address(config_),
                        desired_.chainSelector
                    )
                )
            );
        } else if (poolChange.due) {
            _addPlanned(
                string.concat(poolChange.name, "(", desired_.remoteChain, ")"),
                _single(poolChange.call),
                poolChange.queueCall,
                _singleKey(
                    CCIPTokenPoolConfigKeyLib.remotePoolsKey(
                        address(config_),
                        desired_.chainSelector
                    )
                )
            );
            // The limits of the route wait for its last remote pool change, so a pending rate
            // limit action of the route must not execute first
            _clearKey(
                CCIPTokenPoolConfigKeyLib.rateLimitsKey(address(config_), desired_.chainSelector)
            );
        } else if (limitsChange) {
            _addPlanned(
                string.concat("setChainRateLimits(", desired_.remoteChain, ")"),
                _single(_rateLimitsCall(config_, desired_)),
                abi.encodeCall(
                    ICCIPTokenPoolConfigTimelock.queueSetChainRateLimits,
                    (desired_.chainSelector, desired_.outbound, desired_.inbound)
                ),
                _singleKey(
                    CCIPTokenPoolConfigKeyLib.rateLimitsKey(
                        address(config_),
                        desired_.chainSelector
                    )
                )
            );
        }
    }

    function _poolChangeCount(
        CCIPConfigLib.RouteDiff memory diff_
    ) internal pure returns (uint256 count) {
        return diff_.poolsToAdd.length + diff_.poolsToRemove.length;
    }

    /// @notice Returns whether the unexpired pending holder of the remote pools key of a route
    ///         is exactly the batch of the planned remote pool change followed by the desired
    ///         limits.
    function _restoreBatchQueued(
        IConfigTimelockBatchQueue queue_,
        ICCIPTokenPoolConfig config_,
        CCIPConfigLib.DesiredRoute memory desired_,
        ITimelockBatchQueue.BatchAction memory poolCall_
    ) internal view returns (bool queued) {
        uint64 pendingId = queue_.pendingActionId(
            CCIPTokenPoolConfigKeyLib.remotePoolsKey(address(config_), desired_.chainSelector)
        );
        if (pendingId == 0) return false;
        ITimelockBatchQueue.QueuedAction memory pending = queue_.getQueuedAction(pendingId);
        // The expiry is read by the script at simulation time
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > pending.expiresAt) return false;

        Planned memory probe;
        probe.actions = new ITimelockBatchQueue.BatchAction[](2);
        probe.actions[0] = poolCall_;
        probe.actions[1] = _rateLimitsCall(config_, desired_);
        return _holdsChange(pending, probe);
    }

    /// @notice Plans the one remote pool change of a route that this run queues: the first
    ///         missing pool, else the first pool to remove; the rest is reported as deferred.
    function _planPoolChange(
        ICCIPTokenPoolConfig config_,
        CCIPConfigLib.DesiredRoute memory desired_,
        CCIPConfigLib.RouteDiff memory diff_
    ) internal view returns (PoolChange memory change) {
        uint64 selector = desired_.chainSelector;
        if (diff_.poolsToAdd.length > 0) {
            bytes memory remotePool = diff_.poolsToAdd[0];
            console2.log("  Remote pool missing:", vm.toString(remotePool));
            config_.validateAddRemotePool(selector, remotePool);
            change.due = true;
            change.name = "addRemotePool";
            change.call = _configCall(
                address(config_),
                ICCIPTokenPoolConfig.addRemotePool.selector,
                abi.encode(selector, remotePool)
            );
            change.queueCall = abi.encodeCall(
                ICCIPTokenPoolConfigTimelock.queueAddRemotePool,
                (selector, remotePool)
            );
            _logDeferredPools(diff_.poolsToAdd.length - 1, diff_.poolsToRemove.length);
        } else if (diff_.poolsToRemove.length > 0) {
            bytes memory remotePool = diff_.poolsToRemove[0];
            console2.log("  Remote pool to remove:", vm.toString(remotePool));
            console2.log(
                "  WARNING: removing a remote pool rejects in-flight messages from that pool."
            );
            config_.validateRemoveRemotePool(selector, remotePool);
            change.due = true;
            change.name = "removeRemotePool";
            change.call = _configCall(
                address(config_),
                ICCIPTokenPoolConfig.removeRemotePool.selector,
                abi.encode(selector, remotePool)
            );
            change.queueCall = abi.encodeCall(
                ICCIPTokenPoolConfigTimelock.queueRemoveRemotePool,
                (selector, remotePool)
            );
            _logDeferredPools(0, diff_.poolsToRemove.length - 1);
        }
    }

    /// @notice Returns whether this run plans the rate limits of a route: they differ from
    ///         `env.json`, and the route is either open or named in `restoreContained`. A
    ///         contained route that is not named is listed and its limits are left alone, which
    ///         `containedSkipped` reports.
    function _limitsDue(
        ICCIPTokenPoolConfig config_,
        CCIPConfigLib.DesiredRoute memory desired_,
        CCIPConfigLib.LiveRoute memory live_,
        CCIPConfigLib.RouteDiff memory diff_
    ) internal returns (bool due, bool containedSkipped) {
        if (!diff_.limitsDiffer) return (due, containedSkipped);

        if (config_.isChainDisabled(desired_.chainSelector)) {
            if (!_isRestoreRequested(desired_.remoteChain)) {
                _noteContained(desired_.remoteChain);
                containedSkipped = true;
                return (due, containedSkipped);
            }
            console2.log("  Contained: the approved limits are restored (restoreContained).");
        }

        console2.log("  Rate limits differ.");
        console2.log("    live outbound:   ", CCIPConfigLib.describe(live_.outbound));
        console2.log("    desired outbound:", CCIPConfigLib.describe(desired_.outbound));
        console2.log("    live inbound:    ", CCIPConfigLib.describe(live_.inbound));
        console2.log("    desired inbound: ", CCIPConfigLib.describe(desired_.inbound));
        config_.validateSetChainRateLimits(
            desired_.chainSelector,
            desired_.outbound,
            desired_.inbound
        );
        due = true;
    }

    /// @notice Records a contained route whose limit restore this run skips.
    function _noteContained(string memory remoteChain_) internal {
        console2.log(
            "  Contained: the limit restore is skipped; name the route in restoreContained to queue it."
        );
        _containedSkipped.push(remoteChain_);
    }

    /// @notice Adds a cancellation for every pending action that holds a key of a planned change
    ///         while being expired or carrying another intent, and for every pending holder of a
    ///         key that a planned change clears, across the whole plan, so that a pending action
    ///         that serves one planned change but blocks another is cancelled and both changes
    ///         are queued afresh by the next run.
    function _planCancellations(ICCIPTokenPoolConfigTimelock timelock_) internal {
        IConfigTimelockBatchQueue queue = IConfigTimelockBatchQueue(address(timelock_));
        for (uint256 i = 0; i < _plan.length; ++i) {
            Planned storage planned = _plan[i];
            for (uint256 k = 0; k < planned.keys.length; ++k) {
                uint64 pendingId = queue.pendingActionId(planned.keys[k]);
                if (pendingId == 0 || _isCancelled(pendingId)) continue;

                ITimelockBatchQueue.QueuedAction memory pending = queue.getQueuedAction(pendingId);
                // The expiry is read by the script at simulation time
                // forge-lint: disable-next-line(block-timestamp)
                bool expired = block.timestamp > pending.expiresAt;
                if (!expired && _holdsChange(pending, planned)) continue;

                _cancelPending(
                    timelock_,
                    pendingId,
                    pending.proposer,
                    expired,
                    expired
                        ? "  Cancelling expired action"
                        : "  Cancelling action with another intent on a needed key:",
                    planned.description
                );
            }
            for (uint256 k = 0; k < planned.clearKeys.length; ++k) {
                uint64 pendingId = queue.pendingActionId(planned.clearKeys[k]);
                if (pendingId == 0 || _isCancelled(pendingId)) continue;

                ITimelockBatchQueue.QueuedAction memory pending = queue.getQueuedAction(pendingId);
                _cancelPending(
                    timelock_,
                    pendingId,
                    pending.proposer,
                    // The expiry is read by the script at simulation time
                    // forge-lint: disable-next-line(block-timestamp)
                    block.timestamp > pending.expiresAt,
                    "  Cancelling action whose rate limit change must wait for the last remote pool change of its route:",
                    planned.description
                );
            }
        }
    }

    /// @notice Adds the cancellation of a pending action to the batch, after checking that the
    ///         batch owner may cancel it.
    function _cancelPending(
        ICCIPTokenPoolConfigTimelock timelock_,
        uint64 pendingId_,
        address proposer_,
        bool expired_,
        string memory reason_,
        string memory description_
    ) internal {
        ROLESv1 roles = _roles();
        // An expired action is cancellable by any account; an unexpired one only by its
        // proposer, admin or emergency
        require(
            expired_ ||
                proposer_ == _owner ||
                roles.hasRole(_owner, ADMIN_ROLE) ||
                roles.hasRole(_owner, EMERGENCY_ROLE),
            string.concat(
                "CCIPRouteReconcileBatch: action ",
                vm.toString(pendingId_),
                " holds a key of ",
                description_,
                " and was proposed by ",
                vm.toString(proposer_),
                "; until it expires only its proposer, admin or emergency can cancel it (see cancelQueuedActionEmergency)"
            )
        );
        console2.log(reason_, pendingId_, "for", description_);
        addToBatch(
            address(timelock_),
            abi.encodeWithSelector(ITimelockBatchQueue.cancelQueuedAction.selector, pendingId_)
        );
        _cancelledIds.push(pendingId_);
    }

    /// @notice Queues a planned change unless an unexpired, uncancelled pending action already
    ///         carries it. In a run without cancellations every holder of a needed key is such
    ///         an action.
    function _queuePlanned(ICCIPTokenPoolConfigTimelock timelock_, uint256 index_) internal {
        IConfigTimelockBatchQueue queue = IConfigTimelockBatchQueue(address(timelock_));
        Planned storage planned = _plan[index_];
        console2.log("\n", planned.description);

        uint64 pendingId = _pendingHolder(queue, planned);
        if (pendingId != 0) {
            console2.log(
                "  Already queued as action",
                pendingId,
                "executable at",
                queue.getQueuedAction(pendingId).executableAt
            );
            planned.skipped = true;
            return;
        }

        addToBatch(address(timelock_), planned.queueCall);
        console2.log("  Added to the batch");
    }

    /// @notice Lists the planned changes of a run that holds cancellations only: the ones an
    ///         uncancelled pending action already carries, and the ones the next run queues.
    function _logCancelOnlyRun(ICCIPTokenPoolConfigTimelock timelock_) internal view {
        IConfigTimelockBatchQueue queue = IConfigTimelockBatchQueue(address(timelock_));
        console2.log(
            "\nCancellations only: this run queues nothing. Run reconcileRoutes again once the cancellations have landed to queue the replacements."
        );
        uint256 length = _plan.length;
        for (uint256 i = 0; i < length; ++i) {
            Planned storage planned = _plan[i];
            uint64 pendingId = _pendingHolder(queue, planned);
            if (pendingId != 0) {
                console2.log("  Already queued as action", pendingId, ":", planned.description);
            } else {
                console2.log("  Queued by the next run:", planned.description);
            }
        }
    }

    /// @notice Returns the pending action, not cancelled by this run, that holds a key of a
    ///         planned change, or zero when every key is free.
    function _pendingHolder(
        IConfigTimelockBatchQueue queue_,
        Planned storage planned_
    ) internal view returns (uint64 pendingId) {
        for (uint256 k = 0; k < planned_.keys.length; ++k) {
            pendingId = queue_.pendingActionId(planned_.keys[k]);
            if (pendingId != 0 && !_isCancelled(pendingId)) return pendingId;
        }
        return 0;
    }

    function _planCancel(string memory functionName_) internal {
        _skipHeartbeatValidation = true;

        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(
            _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock")
        );
        uint64 actionId = SafeCast.toUint64(_readBatchArgUint256(functionName_, "actionId"));
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(actionId);

        console2.log("\n=== Cancel CCIP config timelock action", actionId, "===");
        console2.log("Proposer:", action.proposer);
        console2.log("Queued at:", action.queuedAt, "expires at:", action.expiresAt);
        console2.log("Sub-actions:", action.actions.length);
        require(!action.executed, "CCIPRouteReconcileBatch: the action is already executed");
        require(!action.cancelled, "CCIPRouteReconcileBatch: the action is already cancelled");

        // The expiry is read by the script at simulation time
        // forge-lint: disable-next-line(block-timestamp)
        bool expired = block.timestamp > action.expiresAt;
        console2.log("Expired:", expired);
        // An expired action is cancellable by any account; an unexpired one only by its
        // proposer, admin or emergency
        ROLESv1 roles = _roles();
        require(
            expired ||
                action.proposer == _owner ||
                roles.hasRole(_owner, ADMIN_ROLE) ||
                roles.hasRole(_owner, EMERGENCY_ROLE),
            "CCIPRouteReconcileBatch: the action has not expired and the batch owner is neither the proposer nor admin or emergency"
        );

        addToBatch(
            address(timelock),
            abi.encodeWithSelector(ITimelockBatchQueue.cancelQueuedAction.selector, actionId)
        );
        _expectedCancelled = actionId;
        console2.log("Added: cancelQueuedAction(", actionId, ")");

        _setPostBatchValidateSelector(this._validateCancelled.selector);
    }

    // =========== EXECUTION =========== //

    /// @notice Returns the action ids this run considers: the `actionIds` list of the args file,
    ///         or every unresolved action.
    function _executionCandidates(
        IConfigTimelockBatchQueue timelock_
    ) internal view returns (uint64[] memory ids) {
        string memory path = ".functions[?(@.name == 'executeReadyActions')].args.actionIds";
        if (bytes(_argsFile).length == 0 || !vm.keyExistsJson(_argsFile, path)) {
            return CCIPQueueLib.unresolvedActionIds(timelock_);
        }

        uint256[] memory listed = _argsFile.readUintArray(path);
        uint64[] memory buffer = new uint64[](listed.length);
        uint256 count = 0;
        for (uint256 i = 0; i < listed.length; ++i) {
            uint64 actionId = SafeCast.toUint64(listed[i]);
            if (_listed(buffer, count, actionId)) {
                console2.log("  Action", actionId, "is listed more than once; considered once");
                continue;
            }
            buffer[count++] = actionId;
        }
        ids = new uint64[](count);
        for (uint256 i = 0; i < count; ++i) {
            ids[i] = buffer[i];
        }
        console2.log("Considering the", ids.length, "listed action ids only");
    }

    function _listed(
        uint64[] memory ids_,
        uint256 count_,
        uint64 actionId_
    ) internal pure returns (bool listed) {
        for (uint256 i = 0; i < count_; ++i) {
            if (ids_[i] == actionId_) return true;
        }
        return false;
    }

    /// @notice Adds the execution of an action to the batch when it exists, is unresolved, is
    ///         inside its execution window and succeeds in an isolated dry run; reports it and
    ///         leaves it out otherwise.
    function _considerExecution(
        IConfigTimelockBatchQueue timelock_,
        uint64 nextActionId_,
        uint64 actionId_
    ) internal {
        if (actionId_ == 0 || actionId_ >= nextActionId_) {
            console2.log("  Action", actionId_, "does not exist");
            return;
        }
        ITimelockBatchQueue.QueuedAction memory action = timelock_.getQueuedAction(actionId_);
        if (action.executed) {
            console2.log("  Action", actionId_, "is already executed");
            return;
        }
        if (action.cancelled) {
            console2.log("  Action", actionId_, "is cancelled");
            return;
        }

        // The queue timestamps are read by the script at simulation time
        uint256 timestamp = block.timestamp;
        CCIPQueueLib.logAction(actionId_, action, timestamp);
        CCIPQueueLib.Status status = CCIPQueueLib.status(action, timestamp);
        if (status == CCIPQueueLib.Status.Delayed) {
            console2.log("    Not ready: executable at", action.executableAt);
            return;
        }
        if (status == CCIPQueueLib.Status.Expired) {
            console2.log(
                "    Expired: cancel it to release its keys; expired at",
                action.expiresAt
            );
            return;
        }

        (bool success, bytes memory revertData) = _dryRunExecute(timelock_, actionId_);
        if (!success) {
            console2.log("    Cannot be executed:", _describeRevert(revertData));
            return;
        }

        addToBatch(
            address(timelock_),
            abi.encodeWithSelector(ITimelockBatchQueue.executeQueuedAction.selector, actionId_)
        );
        _expectedExecuted.push(actionId_);
        console2.log("    Added: executeQueuedAction(", actionId_, ")");
    }

    // =========== QUEUE LISTING =========== //

    /// @notice Lists every unresolved queued action after the plan: cancelled by this run,
    ///         carrying a planned change, or outside the plan, with the sub-actions that conflict
    ///         with `env.json` where the desired state decides it.
    function _logUnresolvedActions(
        IConfigTimelockBatchQueue queue_,
        CCIPConfigLib.DesiredRoute[] memory desired_
    ) internal view {
        uint64[] memory ids = CCIPQueueLib.unresolvedActionIds(queue_);
        console2.log("\n--- Unresolved queued actions:", ids.length, "---");
        // The queue timestamps are read by the script at simulation time
        uint256 timestamp = block.timestamp;
        for (uint256 i = 0; i < ids.length; ++i) {
            ITimelockBatchQueue.QueuedAction memory action = queue_.getQueuedAction(ids[i]);
            CCIPQueueLib.logAction(ids[i], action, timestamp);
            if (_isCancelled(ids[i])) {
                console2.log("    Cancelled by this run.");
            } else if (_carriesPlannedChange(action)) {
                console2.log("    Part of this plan: carries a planned change and is left alone.");
            } else {
                CCIPQueueLib.Status status = CCIPQueueLib.status(action, timestamp);
                console2.log(
                    status == CCIPQueueLib.Status.Expired
                        ? "    Not in this plan: expired; holds its keys until it is cancelled (cancelQueuedAction)."
                        : "    Not in this plan: executes once ready unless it is cancelled (cancelQueuedAction)."
                );
                _logConflicts(action, desired_);
            }
        }
    }

    function _carriesPlannedChange(
        ITimelockBatchQueue.QueuedAction memory action_
    ) internal view returns (bool carries) {
        uint256 length = _plan.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_holdsChange(action_, _plan[i])) return true;
        }
        return false;
    }

    /// @notice Logs, per sub-action of an action outside the plan, its conflict with the desired
    ///         state of its route, when there is one to report.
    function _logConflicts(
        ITimelockBatchQueue.QueuedAction memory action_,
        CCIPConfigLib.DesiredRoute[] memory desired_
    ) internal pure {
        for (uint256 i = 0; i < action_.actions.length; ++i) {
            string memory verdict = _conflict(action_.actions[i], desired_);
            if (bytes(verdict).length == 0) continue;
            console2.log("    ", CCIPQueueLib.describe(action_.actions[i]), verdict);
        }
    }

    /// @notice Returns the conflict of a sub-action with `env.json`, or an empty string when the
    ///         sub-action matches the desired state of its route.
    function _conflict(
        ITimelockBatchQueue.BatchAction memory sub_,
        CCIPConfigLib.DesiredRoute[] memory desired_
    ) internal pure returns (string memory verdict) {
        (bool isRoute, uint64 chainSelector) = CCIPQueueLib.routeChainSelector(sub_);
        if (!isRoute) return "is not checked: env.json declares no desired allowlist";

        (bool declared, CCIPConfigLib.DesiredRoute memory route) = _desiredRoute(
            desired_,
            chainSelector
        );
        if (!declared) return "CONFLICT: its route is not declared in env.json";

        if (!route.enabled) {
            if (sub_.selector == ICCIPTokenPoolConfig.removeChain.selector) return "";
            return "CONFLICT: its route is declared with enabled: false";
        }
        return _enabledRouteConflict(sub_, route);
    }

    /// @notice Returns the conflict of a sub-action with the desired state of its route, which
    ///         is declared with `enabled: true`, or an empty string when the payload matches it.
    function _enabledRouteConflict(
        ITimelockBatchQueue.BatchAction memory sub_,
        CCIPConfigLib.DesiredRoute memory route_
    ) internal pure returns (string memory verdict) {
        bytes4 selector = sub_.selector;
        uint64 chainSelector = route_.chainSelector;
        if (selector == ICCIPTokenPoolConfig.removeChain.selector) {
            return "CONFLICT: removes a route declared enabled";
        }
        if (selector == ICCIPTokenPoolConfig.addChain.selector) {
            return
                _payloadIs(sub_, abi.encode(_chainUpdate(route_)))
                    ? ""
                    : "CONFLICT: adds the route with values that differ from env.json";
        }
        if (selector == ICCIPTokenPoolConfig.setRemoteToken.selector) {
            return
                _payloadIs(sub_, abi.encode(chainSelector, route_.remoteToken))
                    ? ""
                    : "CONFLICT: sets a remote token that differs from env.json";
        }
        if (selector == ICCIPTokenPoolConfig.setChainRateLimits.selector) {
            return
                _payloadIs(sub_, abi.encode(chainSelector, route_.outbound, route_.inbound))
                    ? ""
                    : "CONFLICT: sets rate limits that differ from env.json";
        }

        (, bytes memory remotePool) = abi.decode(sub_.payload, (uint64, bytes));
        bool declaredPool = CCIPConfigLib.containsBytes(route_.remotePools, remotePool);
        if (selector == ICCIPTokenPoolConfig.addRemotePool.selector) {
            return
                declaredPool ? "" : "CONFLICT: adds a remote pool that env.json does not declare";
        }
        // Only `removeRemotePool` remains among the route sub-actions
        return declaredPool ? "CONFLICT: removes a remote pool that env.json declares" : "";
    }

    function _payloadIs(
        ITimelockBatchQueue.BatchAction memory sub_,
        bytes memory expected_
    ) internal pure returns (bool same) {
        return keccak256(sub_.payload) == keccak256(expected_);
    }

    // The boolean literals are the `declared` element of the returned tuple, not conditions
    // forge-lint: disable-next-item(boolean-cst)
    function _desiredRoute(
        CCIPConfigLib.DesiredRoute[] memory desired_,
        uint64 chainSelector_
    ) internal pure returns (bool declared, CCIPConfigLib.DesiredRoute memory route) {
        for (uint256 i = 0; i < desired_.length; ++i) {
            if (desired_[i].chainSelector == chainSelector_) return (true, desired_[i]);
        }
        return (false, route);
    }

    // =========== INTERNAL HELPERS =========== //

    function _contracts()
        internal
        view
        returns (
            ICCIPTokenPoolConfig config,
            ICCIPTokenPoolConfigTimelock timelock,
            ICCIPTokenPoolAdmin pool
        )
    {
        config = ICCIPTokenPoolConfig(_envAddressNotZero("olympus.policies.CCIPTokenPoolConfig"));
        timelock = ICCIPTokenPoolConfigTimelock(
            _envAddressNotZero("olympus.policies.CCIPTokenPoolConfigTimelock")
        );
        pool = ICCIPTokenPoolAdmin(_envAddressNotZero(CCIPConfigLib.poolKey(chain)));
        require(
            config.pool() == address(pool),
            "CCIPRouteReconcileBatch: the config policy is bound to another pool"
        );
        require(
            timelock.config() == address(config),
            "CCIPRouteReconcileBatch: the timelock is bound to another config policy"
        );
    }

    /// @notice Reverts unless a `queue*` call from the batch owner would be accepted.
    function _requireQueueable(
        ICCIPTokenPoolConfig config_,
        ICCIPTokenPoolConfigTimelock timelock_,
        ICCIPTokenPoolAdmin pool_
    ) internal view {
        address poolOwner = pool_.owner();
        require(
            poolOwner == address(config_),
            string.concat(
                "CCIPRouteReconcileBatch: the pool is owned by ",
                vm.toString(poolOwner),
                ", not by the config policy; complete the handover first"
            )
        );
        address configOperator = IConfigOperator(address(config_)).configOperator();
        require(
            configOperator == address(timelock_),
            string.concat(
                "CCIPRouteReconcileBatch: the config operator is ",
                vm.toString(configOperator),
                ", not the timelock"
            )
        );
        require(
            IEnabler(address(config_)).isEnabled(),
            "CCIPRouteReconcileBatch: the config policy is disabled; queueing requires it enabled"
        );
        require(
            IEnabler(address(timelock_)).isEnabled(),
            "CCIPRouteReconcileBatch: the timelock is disabled; queueing requires it enabled"
        );
        require(
            _roles().hasRole(_owner, BRIDGE_ADMIN_ROLE),
            "CCIPRouteReconcileBatch: the batch owner does not hold bridge_admin"
        );
    }

    function _addPlanned(
        string memory description_,
        ITimelockBatchQueue.BatchAction[] memory actions_,
        bytes memory queueCall_,
        bytes32[] memory keys_
    ) internal {
        Planned storage planned = _plan.push();
        planned.description = description_;
        for (uint256 i = 0; i < actions_.length; ++i) {
            planned.actions.push(actions_[i]);
        }
        planned.queueCall = queueCall_;
        planned.keys = keys_;
        console2.log("  Planned:", description_);
    }

    /// @notice Adds a key that the last planned change clears without reserving it.
    function _clearKey(bytes32 key_) internal {
        _plan[_plan.length - 1].clearKeys.push(key_);
    }

    /// @notice Builds one config call of a planned change.
    function _configCall(
        address config_,
        bytes4 selector_,
        bytes memory payload_
    ) internal pure returns (ITimelockBatchQueue.BatchAction memory call) {
        return
            ITimelockBatchQueue.BatchAction({
                target: config_,
                selector: selector_,
                payload: payload_
            });
    }

    /// @notice Builds the `addChain` update of a desired route.
    function _chainUpdate(
        CCIPConfigLib.DesiredRoute memory desired_
    ) internal pure returns (ICCIPTokenPoolAdmin.ChainUpdate memory update) {
        return
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: desired_.chainSelector,
                remotePoolAddresses: desired_.remotePools,
                remoteTokenAddress: desired_.remoteToken,
                outboundRateLimiterConfig: desired_.outbound,
                inboundRateLimiterConfig: desired_.inbound
            });
    }

    /// @notice Builds the `setChainRateLimits` call of a route from its desired limits.
    function _rateLimitsCall(
        ICCIPTokenPoolConfig config_,
        CCIPConfigLib.DesiredRoute memory desired_
    ) internal pure returns (ITimelockBatchQueue.BatchAction memory call) {
        return
            _configCall(
                address(config_),
                ICCIPTokenPoolConfig.setChainRateLimits.selector,
                abi.encode(desired_.chainSelector, desired_.outbound, desired_.inbound)
            );
    }

    function _single(
        ITimelockBatchQueue.BatchAction memory call_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = call_;
    }

    /// @notice The three reserved keys of a route, in the order the timelock reserves them.
    function _routeKeys(
        address config_,
        uint64 selector_
    ) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](3);
        keys[0] = CCIPTokenPoolConfigKeyLib.rateLimitsKey(config_, selector_);
        keys[1] = CCIPTokenPoolConfigKeyLib.remotePoolsKey(config_, selector_);
        keys[2] = CCIPTokenPoolConfigKeyLib.routeIdentityKey(config_, selector_);
    }

    function _singleKey(bytes32 key_) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = key_;
    }

    function _twoKeys(
        bytes32 first_,
        bytes32 second_
    ) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](2);
        keys[0] = first_;
        keys[1] = second_;
    }

    /// @notice Returns whether a queued action carries a planned change: the same config calls
    ///         in the same order and nothing else. An action that shares a key with a planned
    ///         change but differs in any sub-action holds the key with another intent, since
    ///         executing it would apply a change that is no longer desired or leave one out.
    function _holdsChange(
        ITimelockBatchQueue.QueuedAction memory action_,
        Planned memory planned_
    ) internal pure returns (bool holds) {
        if (action_.actions.length != planned_.actions.length) return false;
        for (uint256 i = 0; i < action_.actions.length; ++i) {
            ITimelockBatchQueue.BatchAction memory sub = action_.actions[i];
            ITimelockBatchQueue.BatchAction memory want = planned_.actions[i];
            if (
                sub.target != want.target ||
                sub.selector != want.selector ||
                keccak256(sub.payload) != keccak256(want.payload)
            ) return false;
        }
        return true;
    }

    /// @notice Reads the optional `restoreContained` list of the args file: the remote chain
    ///         names whose contained limits this run restores. Each name must be a route
    ///         declared with `enabled: true`.
    function _readRestoreContained(CCIPConfigLib.DesiredRoute[] memory desired_) internal {
        if (bytes(_argsFile).length == 0) return;
        string memory path = ".functions[?(@.name == 'reconcileRoutes')].args.restoreContained";
        if (!vm.keyExistsJson(_argsFile, path)) return;

        string[] memory names = _argsFile.readStringArray(path);
        for (uint256 i = 0; i < names.length; ++i) {
            bool declared = false;
            for (uint256 j = 0; j < desired_.length; ++j) {
                if (desired_[j].enabled && _sameString(desired_[j].remoteChain, names[i])) {
                    declared = true;
                    break;
                }
            }
            require(
                declared,
                string.concat(
                    "CCIPRouteReconcileBatch: restoreContained names ",
                    names[i],
                    ", which env.json does not declare as an enabled route"
                )
            );
            _restoreContained.push(names[i]);
            console2.log("Limit restore requested for the contained route:", names[i]);
        }
    }

    function _isRestoreRequested(
        string memory remoteChain_
    ) internal view returns (bool requested) {
        uint256 length = _restoreContained.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_sameString(_restoreContained[i], remoteChain_)) return true;
        }
        return false;
    }

    function _sameString(string memory a_, string memory b_) internal pure returns (bool same) {
        return keccak256(bytes(a_)) == keccak256(bytes(b_));
    }

    function _isCancelled(uint64 actionId_) internal view returns (bool cancelled) {
        uint256 length = _cancelledIds.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_cancelledIds[i] == actionId_) return true;
        }
        return false;
    }

    /// @notice Executes an action inside a state snapshot that is reverted afterwards, to learn
    ///         whether the execution would succeed.
    function _dryRunExecute(
        IConfigTimelockBatchQueue timelock_,
        uint64 actionId_
    ) internal returns (bool success, bytes memory revertData) {
        uint256 snapshotId = vm.snapshotState();
        // A raw call so that the revert data of a failing execution is captured
        // forge-lint: disable-next-item(low-level-calls)
        (success, revertData) = address(timelock_).call(
            abi.encodeWithSelector(ITimelockBatchQueue.executeQueuedAction.selector, actionId_)
        );
        require(
            vm.revertToStateAndDelete(snapshotId),
            "CCIPRouteReconcileBatch: the dry run state was not reverted"
        );
    }

    function _describeRevert(bytes memory revertData_) internal pure returns (string memory text) {
        if (revertData_.length < 4) return "empty revert data";
        // casting to 'bytes4' is safe because only the error selector is wanted
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 selector = bytes4(revertData_);
        if (
            selector ==
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        ) return "ConfigStateChanged (the route moved since queueing; cancel and reconcile again)";
        if (
            selector ==
            ICCIPTokenPoolConfigTimelock.CCIPTokenPoolConfigTimelock_NotConfigOperator.selector
        ) return "NotConfigOperator (the config policy names another config operator)";
        if (selector == IEnabler.NotEnabled.selector)
            return "NotEnabled (the timelock or the config policy is disabled)";
        if (selector == ICCIPTokenPoolAdmin.OnlyCallableByOwner.selector)
            return "OnlyCallableByOwner (the config policy no longer owns the pool)";
        return string.concat("revert selector ", vm.toString(abi.encodePacked(selector)));
    }

    function _roles() internal view returns (ROLESv1 roles) {
        return
            ROLESv1(
                address(
                    Kernel(_envAddressNotZero("olympus.Kernel")).getModuleForKeycode(
                        toKeycode("ROLES")
                    )
                )
            );
    }

    // =========== LOGGING =========== //

    function _logLiveRoutes(ICCIPTokenPoolAdmin pool_, uint64[] memory selectors_) internal view {
        console2.log("\n--- Live routes on the pool:", selectors_.length, "---");
        for (uint256 i = 0; i < selectors_.length; ++i) {
            CCIPConfigLib.LiveRoute memory live = CCIPConfigLib.liveRoute(pool_, selectors_[i]);
            console2.log("Selector", selectors_[i]);
            console2.log("  remote token:", vm.toString(live.remoteToken));
            console2.log("  remote pools:", CCIPConfigLib.describe(live.remotePools));
            console2.log("  outbound:", CCIPConfigLib.describe(live.outbound));
            console2.log("  inbound:", CCIPConfigLib.describe(live.inbound));
        }
    }

    function _logDesiredRoutes(CCIPConfigLib.DesiredRoute[] memory routes_) internal view {
        console2.log("\n--- Desired routes in env.json:", routes_.length, "---");
        for (uint256 i = 0; i < routes_.length; ++i) {
            CCIPConfigLib.DesiredRoute memory route = routes_[i];
            console2.log(route.remoteChain, "selector", route.chainSelector);
            console2.log("  enabled:", route.enabled);
            if (route.enabled) {
                console2.log("  remote token:", vm.toString(route.remoteToken));
                console2.log("  remote pools:", CCIPConfigLib.describe(route.remotePools));
                console2.log("  outbound:", CCIPConfigLib.describe(route.outbound));
                console2.log("  inbound:", CCIPConfigLib.describe(route.inbound));
            }
        }
    }

    /// @notice Reverts if a live route of the pool is not declared in `env.json`: removal is
    ///         never derived from absence, so the declaration must name every live route, either
    ///         with `enabled: true` and its limits or with `enabled: false` to remove it.
    function _requireRoutesDeclared(
        CCIPConfigLib.DesiredRoute[] memory desired_,
        uint64[] memory liveSelectors_
    ) internal view {
        for (uint256 i = 0; i < liveSelectors_.length; ++i) {
            bool declared = false;
            for (uint256 j = 0; j < desired_.length; ++j) {
                if (desired_[j].chainSelector == liveSelectors_[i]) {
                    declared = true;
                    break;
                }
            }
            require(
                declared,
                string.concat(
                    "CCIPRouteReconcileBatch: live route ",
                    vm.toString(liveSelectors_[i]),
                    " is not declared in env.json; declare it with enabled: true and its limits, or with enabled: false to remove it"
                )
            );
        }
    }

    /// @notice Lists the contained routes whose limit restore the run skipped.
    function _logContainedSkipped() internal view {
        uint256 length = _containedSkipped.length;
        if (length == 0) return;
        console2.log("\n--- Contained routes: limit restore skipped ---");
        for (uint256 i = 0; i < length; ++i) {
            console2.log(
                string.concat(
                    "  ",
                    _containedSkipped[i],
                    ": contained; the approved limits of env.json are queued only for a route named in restoreContained"
                )
            );
        }
    }

    function _logDeferredPools(uint256 addsLeft_, uint256 removesLeft_) internal pure {
        if (addsLeft_ == 0 && removesLeft_ == 0) return;
        console2.log(
            "  Deferred: further remote pool changes of this route (",
            addsLeft_,
            "additions,",
            removesLeft_
        );
        console2.log(
            "  removals) are queued by a later run; the remote pools domain admits one unresolved change at a time."
        );
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
