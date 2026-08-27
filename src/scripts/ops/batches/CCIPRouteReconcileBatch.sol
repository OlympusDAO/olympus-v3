// SPDX-License-Identifier: AGPL-3.0-or-later
// solhint-disable custom-errors
pragma solidity ^0.8.24;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {CCIPConfigLib} from "src/scripts/ops/lib/CCIPConfigLib.sol";

// Contracts
import {Kernel, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title CCIPRouteReconcileBatch
/// @notice Declarative route reconciliation for the CCIP token pool through the
///         CCIPBridgeConfigTimelock. `env.json` is the desired state; the pool is the live
///         state; the batch contains only the typed timelock actions that converge the two.
///
///         Entry points:
///         - `reconcileRoutes` (DAO MS as `bridge_admin`): compare every route declared under
///           `olympus.config.CCIP.routes` with the pool, field by field, and queue the minimal
///           set of `queue*` calls. Pending actions that already carry the same change are
///           left alone; pending actions that hold a needed key with another intent, or that
///           have expired, are cancelled and replaced.
///         - `executeReadyActions` (anyone): execute every queued action whose delay has elapsed
///           and whose execution would succeed; report the others.
///         - `cancelQueuedAction` (DAO MS as proposer) and `cancelQueuedActionEmergency`
///           (Emergency MS): cancel one action by id, which is the only way to release the
///           configuration keys of an expired or stale action.
///
///         Each change is queued as its own action so that a queued action that turned stale
///         does not block the execution of the other queued actions; the reconcile run itself is
///         atomic and fails closed, so an invalid desired route reverts the whole run before
///         anything is queued. The timelock reserves one key per configuration domain and
///         refuses a second unresolved action on the same domain, so at most one remote-pool
///         change and one rate-limit change per route, or one route-identity change, can be
///         queued per run; the remainder is reported as deferred and queued by a later run once
///         the first action has executed.
contract CCIPRouteReconcileBatch is BatchScriptV2 {
    // =========== DATA STRUCTURES =========== //

    /// @notice One typed change to queue on the timelock.
    struct Planned {
        string description;
        bytes4 selector;
        bytes payload;
        bytes queueCall;
        bytes32[] keys;
        bool skipped;
    }

    // =========== STATE =========== //

    Planned[] internal _plan;
    uint64[] internal _cancelledIds;
    uint64[] internal _expectedExecuted;
    uint64 internal _expectedCancelled;

    // =========== ENTRY POINTS =========== //

    /// @notice Queues the timelock actions that converge the pool routes to `env.json`.
    /// @dev    Desired routes are processed in remote chain name order; within a route the
    ///         identity change comes first, then one remote-pool change (additions before
    ///         removals), then the rate limits. A removal is queued only for a route whose entry
    ///         carries `enabled: false`; a live route that `env.json` does not declare is
    ///         reported and left untouched.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    ///         - The config policy, the timelock and the pool are not bound to each other.
    ///         - The config policy does not own the pool or does not name the timelock as its
    ///           config operator.
    ///         - The config policy or the timelock is disabled.
    ///         - The batch owner does not hold `bridge_admin`.
    ///         - A desired route is malformed (see `CCIPConfigLib`).
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function reconcileRoutes(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the config timelock
        _skipHeartbeatValidation = true;

        (
            ICCIPBridgeConfig config,
            ICCIPBridgeConfigTimelock timelock,
            ICCIPTokenPoolAdmin pool
        ) = _contracts();

        console2.log("\n=== Reconcile CCIP routes through the config timelock ===");
        console2.log("CCIPBridgeConfig:", address(config));
        console2.log("CCIPBridgeConfigTimelock:", address(timelock));
        console2.log("Token pool:", address(pool));

        _requireQueueable(config, timelock, pool);

        CCIPConfigLib.DesiredRoute[] memory desired = CCIPConfigLib.desiredRoutes(env, chain);
        uint64[] memory liveSelectors = pool.getSupportedChains();

        _logLiveRoutes(pool, liveSelectors);
        _logDesiredRoutes(desired);

        console2.log("\n--- Plan ---");
        for (uint256 i; i < desired.length; ++i) {
            _planRoute(config, timelock, pool, desired[i]);
        }
        _reportUnmanagedRoutes(desired, liveSelectors);

        console2.log("\n--- Queue ---");
        _planCancellations(config, timelock);
        for (uint256 i; i < _plan.length; ++i) {
            _queuePlanned(timelock, i);
        }
        if (_plan.length == 0) console2.log("No change needed: the pool matches env.json.");

        _setPostBatchValidateSelector(this._validateReconcileRoutes.selector);

        proposeBatch();
    }

    /// @notice Executes every queued action whose delay has elapsed, whose window has not closed
    ///         and whose execution succeeds in a dry run. Anyone may run it.
    /// @dev    Actions that are not ready, expired, or that would revert (for instance with
    ///         `ConfigStateChanged` after the route moved, or `NotEnabled` while a policy is
    ///         disabled) are reported with the reason and left in the queue. An expired or stale
    ///         action keeps its keys until it is cancelled.
    ///
    ///         Reverts if:
    ///         - The args file is not empty.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner; any owner may execute.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function executeReadyActions(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _skipHeartbeatValidation = true;

        ICCIPBridgeConfigTimelock timelock = ICCIPBridgeConfigTimelock(
            _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock")
        );
        uint64 nextActionId = timelock.nextActionId();

        console2.log("\n=== Execute ready CCIP config timelock actions ===");
        console2.log("CCIPBridgeConfigTimelock:", address(timelock));
        console2.log("Block timestamp:", block.timestamp);
        console2.log("Queued actions so far:", nextActionId - 1);

        for (uint64 actionId = 1; actionId < nextActionId; ++actionId) {
            ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(actionId);
            if (action.executed || action.cancelled) continue;

            // The queue timestamps are read by the script at simulation time
            // forge-lint: disable-next-line(block-timestamp)
            if (block.timestamp < action.executableAt) {
                console2.log(
                    "  Action",
                    actionId,
                    "is not ready: executable at",
                    action.executableAt
                );
                continue;
            }
            // forge-lint: disable-next-line(block-timestamp)
            if (block.timestamp > action.expiresAt) {
                console2.log(
                    "  Action",
                    actionId,
                    "has expired: cancel it to release its keys; expired at",
                    action.expiresAt
                );
                continue;
            }

            (bool success, bytes memory revertData) = _dryRunExecute(timelock, actionId);
            if (!success) {
                console2.log(
                    "  Action",
                    actionId,
                    "cannot be executed:",
                    _describeRevert(revertData)
                );
                continue;
            }

            addToBatch(
                address(timelock),
                abi.encodeWithSelector(ITimelockBatchQueue.executeQueuedAction.selector, actionId)
            );
            _expectedExecuted.push(actionId);
            console2.log("  Added: executeQueuedAction(", actionId, ")");
        }

        if (_expectedExecuted.length == 0) console2.log("No action is ready to execute.");

        _setPostBatchValidateSelector(this._validateExecuted.selector);

        proposeBatch();
    }

    /// @notice Cancels one queued action (DAO MS as the proposer of the action, or any `admin` or
    ///         `emergency` holder as owner).
    /// @dev    Args file: `{"functions": [{"name": "cancelQueuedAction", "args": {"actionId": 1}}]}`.
    ///
    ///         Reverts if:
    ///         - The action does not exist, or is already executed or cancelled.
    ///         - The batch owner is neither the proposer nor an `admin` or `emergency` holder.
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

    /// @notice Validates the state after `reconcileRoutes`: every queued change holds its keys
    ///         and every cancelled action is cancelled.
    function _validateReconcileRoutes() external view {
        ICCIPBridgeConfigTimelock timelock = ICCIPBridgeConfigTimelock(
            _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock")
        );
        address config = _envAddressNotZero("olympus.policies.CCIPBridgeConfig");

        console2.log("\nValidating reconcileRoutes post-batch state");
        for (uint256 i; i < _cancelledIds.length; ++i) {
            require(
                timelock.getQueuedAction(_cancelledIds[i]).cancelled,
                string.concat("Action ", vm.toString(_cancelledIds[i]), " is not cancelled")
            );
            console2.log("  Action", _cancelledIds[i], "is cancelled");
        }
        for (uint256 i; i < _plan.length; ++i) {
            Planned memory planned = _plan[i];
            if (planned.skipped) continue;
            for (uint256 k; k < planned.keys.length; ++k) {
                uint64 actionId = timelock.pendingActionId(planned.keys[k]);
                require(
                    actionId != 0,
                    string.concat("No pending action holds the key of: ", planned.description)
                );
                require(
                    _holdsChange(timelock.getQueuedAction(actionId), config, planned),
                    string.concat("The pending action does not carry: ", planned.description)
                );
            }
            console2.log("  Queued:", planned.description);
        }
        console2.log("reconcileRoutes post-batch validation passed");
    }

    /// @notice Validates the state after `executeReadyActions`.
    function _validateExecuted() external view {
        ICCIPBridgeConfigTimelock timelock = ICCIPBridgeConfigTimelock(
            _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock")
        );

        console2.log("\nValidating executeReadyActions post-batch state");
        for (uint256 i; i < _expectedExecuted.length; ++i) {
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
        ICCIPBridgeConfigTimelock timelock = ICCIPBridgeConfigTimelock(
            _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock")
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
        ICCIPBridgeConfig config_,
        ICCIPBridgeConfigTimelock timelock_,
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
                ICCIPBridgeConfig.removeChain.selector,
                abi.encode(selector),
                abi.encodeCall(ICCIPBridgeConfigTimelock.queueRemoveChain, (selector)),
                _routeKeys(timelock_, selector)
            );
            return;
        }

        if (!live.exists) {
            ICCIPTokenPoolAdmin.ChainUpdate memory update = ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: selector,
                remotePoolAddresses: desired_.remotePools,
                remoteTokenAddress: desired_.remoteToken,
                outboundRateLimiterConfig: desired_.outbound,
                inboundRateLimiterConfig: desired_.inbound
            });
            // Surface the config policy's own validation before queueing
            config_.validateAddChain(update);
            _addPlanned(
                string.concat("addChain(", desired_.remoteChain, ")"),
                ICCIPBridgeConfig.addChain.selector,
                abi.encode(update),
                abi.encodeCall(ICCIPBridgeConfigTimelock.queueAddChain, (update)),
                _routeKeys(timelock_, selector)
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
            config_.validateSetRemoteToken(selector, desired_.remoteToken);
            _addPlanned(
                string.concat("setRemoteToken(", desired_.remoteChain, ")"),
                ICCIPBridgeConfig.setRemoteToken.selector,
                abi.encode(selector, desired_.remoteToken),
                abi.encodeCall(
                    ICCIPBridgeConfigTimelock.queueSetRemoteToken,
                    (selector, desired_.remoteToken)
                ),
                _routeKeys(timelock_, selector)
            );
            return;
        }

        if (diff.poolsToAdd.length > 0) {
            console2.log("  Remote pool missing:", vm.toString(diff.poolsToAdd[0]));
            config_.validateAddRemotePool(selector, diff.poolsToAdd[0]);
            _addPlanned(
                string.concat("addRemotePool(", desired_.remoteChain, ")"),
                ICCIPBridgeConfig.addRemotePool.selector,
                abi.encode(selector, diff.poolsToAdd[0]),
                abi.encodeCall(
                    ICCIPBridgeConfigTimelock.queueAddRemotePool,
                    (selector, diff.poolsToAdd[0])
                ),
                _singleKey(timelock_.getRemotePoolsKey(selector))
            );
            _logDeferredPools(diff.poolsToAdd.length - 1, diff.poolsToRemove.length);
        } else if (diff.poolsToRemove.length > 0) {
            console2.log("  Remote pool to remove:", vm.toString(diff.poolsToRemove[0]));
            console2.log(
                "  WARNING: removing a remote pool rejects in-flight messages from that pool."
            );
            config_.validateRemoveRemotePool(selector, diff.poolsToRemove[0]);
            _addPlanned(
                string.concat("removeRemotePool(", desired_.remoteChain, ")"),
                ICCIPBridgeConfig.removeRemotePool.selector,
                abi.encode(selector, diff.poolsToRemove[0]),
                abi.encodeCall(
                    ICCIPBridgeConfigTimelock.queueRemoveRemotePool,
                    (selector, diff.poolsToRemove[0])
                ),
                _singleKey(timelock_.getRemotePoolsKey(selector))
            );
            _logDeferredPools(0, diff.poolsToRemove.length - 1);
        }

        if (diff.limitsDiffer) {
            console2.log("  Rate limits differ: queueing setChainRateLimits.");
            console2.log("    live outbound:   ", CCIPConfigLib.describe(live.outbound));
            console2.log("    desired outbound:", CCIPConfigLib.describe(desired_.outbound));
            console2.log("    live inbound:    ", CCIPConfigLib.describe(live.inbound));
            console2.log("    desired inbound: ", CCIPConfigLib.describe(desired_.inbound));
            config_.validateSetChainRateLimits(selector, desired_.outbound, desired_.inbound);
            _addPlanned(
                string.concat("setChainRateLimits(", desired_.remoteChain, ")"),
                ICCIPBridgeConfig.setChainRateLimits.selector,
                abi.encode(selector, desired_.outbound, desired_.inbound),
                abi.encodeCall(
                    ICCIPBridgeConfigTimelock.queueSetChainRateLimits,
                    (selector, desired_.outbound, desired_.inbound)
                ),
                _singleKey(timelock_.getRateLimitsKey(selector))
            );
        }
    }

    /// @notice Adds a cancellation for every pending action that holds a key of a planned change
    ///         while being expired or carrying another intent, across the whole plan, so that a
    ///         pending action that serves one planned change but blocks another is cancelled and
    ///         both changes are queued afresh.
    function _planCancellations(
        ICCIPBridgeConfig config_,
        ICCIPBridgeConfigTimelock timelock_
    ) internal {
        ROLESv1 roles = _roles();
        for (uint256 i; i < _plan.length; ++i) {
            Planned storage planned = _plan[i];
            for (uint256 k; k < planned.keys.length; ++k) {
                uint64 pendingId = timelock_.pendingActionId(planned.keys[k]);
                if (pendingId == 0 || _isCancelled(pendingId)) continue;

                ITimelockBatchQueue.QueuedAction memory pending = timelock_.getQueuedAction(
                    pendingId
                );
                // The expiry is read by the script at simulation time
                // forge-lint: disable-next-line(block-timestamp)
                bool expired = block.timestamp > pending.expiresAt;
                if (!expired && _holdsChange(pending, address(config_), planned)) continue;

                require(
                    pending.proposer == _owner ||
                        roles.hasRole(_owner, ADMIN_ROLE) ||
                        roles.hasRole(_owner, EMERGENCY_ROLE),
                    string.concat(
                        "CCIPRouteReconcileBatch: action ",
                        vm.toString(pendingId),
                        " holds a key of ",
                        planned.description,
                        " and was proposed by ",
                        vm.toString(pending.proposer),
                        "; only its proposer, admin or emergency can cancel it (see cancelQueuedActionEmergency)"
                    )
                );
                console2.log(
                    expired
                        ? "  Cancelling expired action"
                        : "  Cancelling action with another intent on a needed key:",
                    pendingId,
                    "for",
                    planned.description
                );
                addToBatch(
                    address(timelock_),
                    abi.encodeWithSelector(
                        ITimelockBatchQueue.cancelQueuedAction.selector,
                        pendingId
                    )
                );
                _cancelledIds.push(pendingId);
            }
        }
    }

    /// @notice Queues a planned change unless an unexpired, uncancelled pending action already
    ///         carries it. After `_planCancellations` every remaining holder of a needed key is
    ///         such an action.
    function _queuePlanned(ICCIPBridgeConfigTimelock timelock_, uint256 index_) internal {
        Planned storage planned = _plan[index_];
        console2.log("\n", planned.description);

        for (uint256 k; k < planned.keys.length; ++k) {
            uint64 pendingId = timelock_.pendingActionId(planned.keys[k]);
            if (pendingId == 0 || _isCancelled(pendingId)) continue;

            console2.log(
                "  Already queued as action",
                pendingId,
                "executable at",
                timelock_.getQueuedAction(pendingId).executableAt
            );
            planned.skipped = true;
            return;
        }

        addToBatch(address(timelock_), planned.queueCall);
        console2.log("  Added to the batch");
    }

    function _planCancel(string memory functionName_) internal {
        _skipHeartbeatValidation = true;

        ICCIPBridgeConfigTimelock timelock = ICCIPBridgeConfigTimelock(
            _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock")
        );
        uint64 actionId = uint64(_readBatchArgUint256(functionName_, "actionId"));
        ITimelockBatchQueue.QueuedAction memory action = timelock.getQueuedAction(actionId);

        console2.log("\n=== Cancel CCIP config timelock action", actionId, "===");
        console2.log("Proposer:", action.proposer);
        console2.log("Queued at:", action.queuedAt, "expires at:", action.expiresAt);
        console2.log("Sub-actions:", action.actions.length);
        require(!action.executed, "CCIPRouteReconcileBatch: the action is already executed");
        require(!action.cancelled, "CCIPRouteReconcileBatch: the action is already cancelled");

        ROLESv1 roles = _roles();
        require(
            action.proposer == _owner ||
                roles.hasRole(_owner, ADMIN_ROLE) ||
                roles.hasRole(_owner, EMERGENCY_ROLE),
            "CCIPRouteReconcileBatch: the batch owner is neither the proposer nor admin or emergency"
        );

        addToBatch(
            address(timelock),
            abi.encodeWithSelector(ITimelockBatchQueue.cancelQueuedAction.selector, actionId)
        );
        _expectedCancelled = actionId;
        console2.log("Added: cancelQueuedAction(", actionId, ")");

        _setPostBatchValidateSelector(this._validateCancelled.selector);
    }

    // =========== INTERNAL HELPERS =========== //

    function _contracts()
        internal
        view
        returns (
            ICCIPBridgeConfig config,
            ICCIPBridgeConfigTimelock timelock,
            ICCIPTokenPoolAdmin pool
        )
    {
        config = ICCIPBridgeConfig(_envAddressNotZero("olympus.policies.CCIPBridgeConfig"));
        timelock = ICCIPBridgeConfigTimelock(
            _envAddressNotZero("olympus.policies.CCIPBridgeConfigTimelock")
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
        ICCIPBridgeConfig config_,
        ICCIPBridgeConfigTimelock timelock_,
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
        address configOperator = config_.configOperator();
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
        bytes4 selector_,
        bytes memory payload_,
        bytes memory queueCall_,
        bytes32[] memory keys_
    ) internal {
        _plan.push(
            Planned({
                description: description_,
                selector: selector_,
                payload: payload_,
                queueCall: queueCall_,
                keys: keys_,
                skipped: false
            })
        );
        console2.log("  Planned:", description_);
    }

    function _routeKeys(
        ICCIPBridgeConfigTimelock timelock_,
        uint64 selector_
    ) internal view returns (bytes32[] memory keys) {
        keys = new bytes32[](3);
        keys[0] = timelock_.getRateLimitsKey(selector_);
        keys[1] = timelock_.getRemotePoolsKey(selector_);
        keys[2] = timelock_.getRouteIdentityKey(selector_);
    }

    function _singleKey(bytes32 key_) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = key_;
    }

    /// @notice Returns whether a queued action carries the planned change as one of its
    ///         sub-actions.
    function _holdsChange(
        ITimelockBatchQueue.QueuedAction memory action_,
        address config_,
        Planned memory planned_
    ) internal pure returns (bool holds) {
        bytes32 payloadHash = keccak256(planned_.payload);
        for (uint256 i; i < action_.actions.length; ++i) {
            ITimelockBatchQueue.BatchAction memory sub = action_.actions[i];
            if (
                sub.target == config_ &&
                sub.selector == planned_.selector &&
                keccak256(sub.payload) == payloadHash
            ) return true;
        }
        return false;
    }

    function _isCancelled(uint64 actionId_) internal view returns (bool cancelled) {
        for (uint256 i; i < _cancelledIds.length; ++i) {
            if (_cancelledIds[i] == actionId_) return true;
        }
        return false;
    }

    /// @notice Executes an action inside a state snapshot that is reverted afterwards, to learn
    ///         whether the execution would succeed.
    function _dryRunExecute(
        ICCIPBridgeConfigTimelock timelock_,
        uint64 actionId_
    ) internal returns (bool success, bytes memory revertData) {
        uint256 snapshotId = vm.snapshotState();
        (success, revertData) = address(timelock_).call(
            abi.encodeWithSelector(ITimelockBatchQueue.executeQueuedAction.selector, actionId_)
        );
        vm.revertToStateAndDelete(snapshotId);
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
            ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_NotConfigOperator.selector
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
        for (uint256 i; i < selectors_.length; ++i) {
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
        for (uint256 i; i < routes_.length; ++i) {
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

    function _reportUnmanagedRoutes(
        CCIPConfigLib.DesiredRoute[] memory desired_,
        uint64[] memory liveSelectors_
    ) internal pure {
        for (uint256 i; i < liveSelectors_.length; ++i) {
            bool declared;
            for (uint256 j; j < desired_.length; ++j) {
                if (desired_[j].chainSelector == liveSelectors_[i]) {
                    declared = true;
                    break;
                }
            }
            if (!declared) {
                console2.log(
                    "\nWARNING: live route",
                    liveSelectors_[i],
                    "is not declared in env.json and is left untouched; declare it, or declare it with enabled: false to remove it."
                );
            }
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
