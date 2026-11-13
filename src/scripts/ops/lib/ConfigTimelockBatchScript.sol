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
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

// Contracts
import {Kernel, Actions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title ConfigTimelockBatchScript
/// @notice The planning helpers shared by the multisig batches of a policy that is governed
///         through a `ConfigTimelockBatchQueue`: the activation in the Kernel, the lifecycle
///         (`disable` and the grace-window `reEnable`), the queue (listing, execution of ready
///         actions with a dry run, cancellation by id) and the declarative reconciliation of a
///         desired state through queued actions.
/// @dev Every helper reads the live state and adds only the calls that are missing, so a
///      second run on a converged state proposes nothing. A batch names itself through
///      `_batchName` for the messages, describes the sub-actions of its timelock through
///      `_describeSubAction`, and, for a reconciliation, marks the actions that were queued
///      from an args file through `_isImperative` and compares a queued sub-action with the
///      desired state through `_conflict`.
///
///      The reconciliation follows three rules for a configuration key that a planned change
///      needs and an unresolved action holds:
///      - an unexpired holder that carries exactly the planned change is left alone and the
///        change is not queued again;
///      - an unexpired holder that was queued from an args file stops the run: it is not
///        derived from `env.json`, so it is never cancelled on the operator's behalf;
///      - any other holder, and any expired one, is cancelled, and the run then holds its
///        cancellations only: execution is permissionless, so the holder may execute before
///        the batch lands, and the replacements are planned afresh by the next run from the
///        state the cancellations leave.
abstract contract ConfigTimelockBatchScript is BatchScriptV2 {
    using stdJson for string;

    // =========== DATA STRUCTURES =========== //

    /// @notice The status of an unresolved action at a timestamp.
    /// @param Delayed The delay has not elapsed.
    /// @param Executable The delay has elapsed and the execution window is open.
    /// @param Expired The execution window has closed; the action holds its keys until it is
    ///        cancelled.
    enum Status {
        Delayed,
        Executable,
        Expired
    }

    /// @notice One change to queue on a timelock: a single call of the configuration
    ///         destination.
    /// @param description The change, for the logs.
    /// @param action The call of the configuration destination.
    /// @param queueCall The timelock call that queues the change.
    /// @param keys The destination-scoped keys the change reserves.
    /// @param skipped Whether an unexpired pending action already carries the change.
    struct Planned {
        string description;
        ITimelockBatchQueue.BatchAction action;
        bytes queueCall;
        bytes32[] keys;
        bool skipped;
    }

    // =========== CONSTANTS =========== //

    /// @notice The length of an error selector, the head of revert data, in bytes.
    uint256 internal constant SELECTOR_LENGTH = 4;

    /// @notice The length of one ABI word, in bytes.
    uint256 internal constant WORD_LENGTH = 32;

    // =========== STATE =========== //

    /// @notice The changes a reconciliation plans, in planning order.
    Planned[] internal _plan;

    /// @notice The pending actions a reconciliation cancels.
    uint64[] internal _cancelledIds;

    /// @notice The timelock whose queue the post-batch validators read.
    address internal _validatedTimelock;

    /// @notice The actions `_planExecuteReady` expects to be executed afterwards.
    uint64[] internal _expectedExecuted;

    /// @notice The action `_planCancelById` expects to be cancelled afterwards.
    uint64 internal _expectedCancelled;

    /// @notice The policies a batch expects to be disabled afterwards.
    address[] internal _expectedDisabled;

    /// @notice The policies a batch expects to be enabled afterwards.
    address[] internal _expectedEnabled;

    // =========== HOOKS =========== //

    /// @notice The name of the batch contract, the prefix of its failure messages.
    function _batchName() internal pure virtual returns (string memory name);

    /// @notice Formats a sub-action of the timelock for the logs.
    function _describeSubAction(
        ITimelockBatchQueue.BatchAction memory sub_
    ) internal view virtual returns (string memory text);

    /// @notice Returns whether an unresolved action was queued from an args file rather than
    ///         derived from `env.json`. A reconciliation does not cancel such an action while
    ///         it has not expired.
    function _isImperative(
        ITimelockBatchQueue.QueuedAction memory
    ) internal view virtual returns (bool imperative) {
        return false;
    }

    /// @notice Returns the conflict of a queued sub-action with the desired state, or an empty
    ///         string when the desired state does not decide it or the sub-action matches it.
    function _conflict(
        ITimelockBatchQueue.BatchAction memory
    ) internal view virtual returns (string memory verdict) {
        return "";
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after a lifecycle batch: every policy planned for a disable
    ///         is disabled and every policy planned for a re-enable is enabled.
    function _validateLifecycle() external view {
        _requireLifecycle();
    }

    /// @notice Reverts unless every policy planned for a disable is disabled and every policy
    ///         planned for a re-enable is enabled.
    function _requireLifecycle() internal view {
        console2.log("\nValidating the lifecycle post-batch state");
        uint256 disabledLength = _expectedDisabled.length;
        for (uint256 i = 0; i < disabledLength; ++i) {
            require(
                !IEnabler(_expectedDisabled[i]).isEnabled(),
                string.concat("Policy ", vm.toString(_expectedDisabled[i]), " is still enabled")
            );
            console2.log("  Policy", _expectedDisabled[i], "is disabled");
        }
        uint256 enabledLength = _expectedEnabled.length;
        for (uint256 i = 0; i < enabledLength; ++i) {
            require(
                IEnabler(_expectedEnabled[i]).isEnabled(),
                string.concat("Policy ", vm.toString(_expectedEnabled[i]), " is not enabled")
            );
            console2.log("  Policy", _expectedEnabled[i], "is enabled");
        }
        console2.log("Lifecycle post-batch validation passed");
    }

    /// @notice Validates the state after `_planExecuteReady`.
    function _validateExecuted() external view {
        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(_validatedTimelock);

        console2.log("\nValidating the execution post-batch state");
        uint256 length = _expectedExecuted.length;
        for (uint256 i = 0; i < length; ++i) {
            require(
                timelock.getQueuedAction(_expectedExecuted[i]).executed,
                string.concat("Action ", vm.toString(_expectedExecuted[i]), " is not executed")
            );
            console2.log("  Action", _expectedExecuted[i], "is executed");
        }
        console2.log("Execution post-batch validation passed");
    }

    /// @notice Validates the state after `_planCancelById`.
    function _validateCancelled() external view {
        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(_validatedTimelock);

        console2.log("\nValidating the cancellation post-batch state");
        require(
            timelock.getQueuedAction(_expectedCancelled).cancelled,
            string.concat("Action ", vm.toString(_expectedCancelled), " is not cancelled")
        );
        console2.log("  Action", _expectedCancelled, "is cancelled");
        console2.log("Cancellation post-batch validation passed");
    }

    /// @notice Validates the state after `_reconcileQueue`: every cancelled action is
    ///         cancelled, and in a run without cancellations every queued change holds its
    ///         keys.
    function _validateReconcile() external view {
        IConfigTimelockBatchQueue timelock = IConfigTimelockBatchQueue(_validatedTimelock);

        console2.log("\nValidating the reconciliation post-batch state");
        uint256 cancelledLength = _cancelledIds.length;
        for (uint256 i = 0; i < cancelledLength; ++i) {
            require(
                timelock.getQueuedAction(_cancelledIds[i]).cancelled,
                string.concat("Action ", vm.toString(_cancelledIds[i]), " is not cancelled")
            );
            console2.log("  Action", _cancelledIds[i], "is cancelled");
        }
        // A run that cancels queues nothing; the replacements are checked by the next run
        if (cancelledLength > 0) {
            console2.log("  Nothing was queued in this run");
            console2.log("Reconciliation post-batch validation passed");
            return;
        }
        uint256 planLength = _plan.length;
        for (uint256 i = 0; i < planLength; ++i) {
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
        console2.log("Reconciliation post-batch validation passed");
    }

    // =========== KERNEL =========== //

    function _roles(address kernel_) internal view returns (ROLESv1 roles) {
        return ROLESv1(address(Kernel(kernel_).getModuleForKeycode(toKeycode("ROLES"))));
    }

    function _isActive(address kernel_, address policy_) internal view returns (bool active) {
        return Kernel(kernel_).isPolicyActive(Policy(policy_));
    }

    /// @notice Reverts unless the batch owner is the Kernel executor, the only caller of
    ///         `Kernel.executeAction`.
    function _requireKernelExecutor(address kernel_) internal view {
        address executor = Kernel(kernel_).executor();
        require(
            executor == _owner,
            _fail(
                string.concat(
                    "the batch owner is not the Kernel executor ",
                    vm.toString(executor),
                    "; run the batch with the executor as owner"
                )
            )
        );
    }

    /// @notice Reverts unless a policy is active in the Kernel.
    /// @param consequence_ What the inactive policy prevents, for the message.
    function _requireActive(
        address kernel_,
        address policy_,
        string memory name_,
        string memory consequence_
    ) internal view {
        require(
            _isActive(kernel_, policy_),
            _fail(
                string.concat(
                    name_,
                    " is not active in the Kernel, ",
                    consequence_,
                    "; activate it with Kernel.executeAction(ActivatePolicy) from the Kernel executor first"
                )
            )
        );
    }

    /// @notice Adds the activation of a policy unless it is active already.
    /// @return planned True if the activation was added to the batch.
    function _planActivatePolicy(
        address kernel_,
        address policy_,
        string memory name_
    ) internal returns (bool planned) {
        if (_isActive(kernel_, policy_)) {
            console2.log(name_, "is already active in the Kernel. Skipping.");
            return false;
        }
        addToBatch(
            kernel_,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, policy_)
        );
        console2.log(string.concat("Added: Kernel.executeAction(ActivatePolicy, ", name_, ")"));
        return true;
    }

    // =========== LIFECYCLE =========== //

    /// @notice Reverts unless the batch owner holds `emergency` or `admin`, the gate of
    ///         `disable()` of a `PolicyEnablerV2` policy.
    /// @param path_ Who can run the batch instead, for the message.
    function _requireDisableAuthority(address kernel_, string memory path_) internal view {
        ROLESv1 roles = _roles(kernel_);
        require(
            roles.hasRole(_owner, EMERGENCY_ROLE) || roles.hasRole(_owner, ADMIN_ROLE),
            _fail(
                string.concat(
                    "the batch owner holds neither emergency nor admin, the gate of disable(); ",
                    path_
                )
            )
        );
    }

    /// @notice Adds the disable of a policy unless it is disabled already.
    /// @return planned True if the disable was added to the batch.
    function _planDisable(address target_, string memory name_) internal returns (bool planned) {
        if (!IEnabler(target_).isEnabled()) {
            console2.log(name_, "is already disabled. Skipping.");
            return false;
        }
        addToBatch(target_, abi.encodeWithSelector(IEnabler.disable.selector, ""));
        _expectedDisabled.push(target_);
        console2.log(string.concat("Added: ", name_, ".disable()"));
        return true;
    }

    /// @notice Returns whether a policy is disabled inside its re-enable grace window, and
    ///         logs its lifecycle state.
    /// @dev The window is inclusive: `reEnable` reverts once the block timestamp is past
    ///      `lastTransitionAt + gracePeriod`. A policy that was never enabled, or whose
    ///      window has elapsed, needs the admin `enable` path.
    /// @return due True if the policy can be re-enabled by `reEnable`.
    function _reEnableDue(
        address target_,
        string memory name_
    ) internal view returns (bool due) {
        console2.log(string.concat("\n", name_), target_);
        if (IEnabler(target_).isEnabled()) {
            console2.log("  Enabled. Nothing to do.");
            return false;
        }

        uint48 lastTransitionAt = IEnablerV2(target_).lastTransitionAt();
        if (lastTransitionAt == 0) {
            console2.log(
                "  Never enabled: the admin role must call enable (an OCG proposal on mainnet)."
            );
            return false;
        }

        uint256 deadline = uint256(lastTransitionAt) + IGracePeriod(target_).gracePeriod();
        console2.log("  Disabled at", lastTransitionAt, "grace deadline", deadline);
        if (vm.getBlockTimestamp() > deadline) {
            console2.log(
                "  Grace window elapsed: the admin role must call enable (an OCG proposal on mainnet)."
            );
            return false;
        }
        console2.log("  Inside the grace window: reEnable is due.");
        return true;
    }

    /// @notice Adds the re-enable of a policy that `_reEnableDue` reported.
    function _planReEnable(address target_, string memory name_) internal {
        addToBatch(target_, abi.encodeWithSelector(IReEnabler.reEnable.selector));
        _expectedEnabled.push(target_);
        console2.log(string.concat("Added: ", name_, ".reEnable()"));
    }

    /// @notice Honours the opt-out of the heart beat validation for an emergency lever: with
    ///         `EMERGENCY_SKIP_HEARTBEAT_VALIDATION=true` in the environment the lever is
    ///         built without the three simulated beats.
    /// @dev The validation simulates `Heart.beat()` after the batch and reverts the run when a
    ///      beat reverts, whatever the cause. A lever must stay available while the Heart is
    ///      failing for a reason the lever does not remove, hence the opt-out.
    function _applyEmergencyHeartbeatOptOut() internal {
        if (!vm.envOr("EMERGENCY_SKIP_HEARTBEAT_VALIDATION", false)) return;
        _skipHeartbeatValidation = true;
        console2.log(
            "EMERGENCY_SKIP_HEARTBEAT_VALIDATION is set: the heart beat is not simulated after this batch."
        );
    }

    // =========== QUEUE: READING =========== //

    /// @notice Returns the ids of the actions that are neither executed nor cancelled,
    ///         ascending.
    function _unresolvedActionIds(
        IConfigTimelockBatchQueue timelock_
    ) internal view returns (uint64[] memory ids) {
        uint64 nextActionId = timelock_.nextActionId();
        uint64[] memory buffer = new uint64[](nextActionId);
        uint256 count = 0;
        for (uint64 actionId = 1; actionId < nextActionId; ++actionId) {
            ITimelockBatchQueue.QueuedAction memory action = timelock_.getQueuedAction(actionId);
            if (action.executed || action.cancelled) continue;
            buffer[count++] = actionId;
        }
        ids = new uint64[](count);
        for (uint256 i = 0; i < count; ++i) {
            ids[i] = buffer[i];
        }
    }

    /// @notice Returns the status of an unresolved action at a timestamp. The execution
    ///         window is `[executableAt, expiresAt]`, both ends included.
    function _status(
        ITimelockBatchQueue.QueuedAction memory action_,
        uint256 timestamp_
    ) internal pure returns (Status actionStatus) {
        if (timestamp_ < action_.executableAt) return Status.Delayed;
        if (timestamp_ > action_.expiresAt) return Status.Expired;
        return Status.Executable;
    }

    /// @notice Logs an unresolved action: its id, status, proposer and window, then one line
    ///         per sub-action.
    function _logAction(
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction memory action_,
        uint256 timestamp_
    ) internal view {
        Status actionStatus = _status(action_, timestamp_);
        console2.log(
            "  Action",
            actionId_,
            actionStatus == Status.Delayed
                ? "(delayed)"
                : actionStatus == Status.Expired
                    ? "(expired: cancel it to release its keys)"
                    : "(executable)"
        );
        console2.log("    proposer:", action_.proposer);
        console2.log("    executable at:", action_.executableAt, "expires at:", action_.expiresAt);
        for (uint256 i = 0; i < action_.actions.length; ++i) {
            console2.log("    sub-action", i, _describeSubAction(action_.actions[i]));
        }
    }

    /// @notice Lists the unresolved queued actions of a timelock under a note that states what
    ///         the batch leaves them in.
    /// @param note_ The sentence printed when at least one action is unresolved.
    function _logUnresolvedQueue(
        IConfigTimelockBatchQueue timelock_,
        string memory name_,
        string memory note_
    ) internal view {
        uint64[] memory ids = _unresolvedActionIds(timelock_);
        console2.log(
            string.concat("\n--- Unresolved queued actions on ", name_, ":"),
            ids.length,
            "---"
        );
        if (ids.length == 0) return;
        console2.log(note_);
        uint256 timestamp = vm.getBlockTimestamp();
        for (uint256 i = 0; i < ids.length; ++i) {
            _logAction(ids[i], timelock_.getQueuedAction(ids[i]), timestamp);
        }
    }

    /// @notice Returns whether the batch owner may cancel an action: any owner once the action
    ///         has expired, and before that its proposer, by address, `admin` and `emergency`.
    function _mayCancel(
        address kernel_,
        ITimelockBatchQueue.QueuedAction memory action_
    ) internal view returns (bool allowed) {
        if (vm.getBlockTimestamp() > action_.expiresAt) return true;
        if (action_.proposer == _owner) return true;
        ROLESv1 roles = _roles(kernel_);
        return roles.hasRole(_owner, ADMIN_ROLE) || roles.hasRole(_owner, EMERGENCY_ROLE);
    }

    // =========== QUEUE: EXECUTION =========== //

    /// @notice Plans the execution of the queued actions whose delay has elapsed, whose window
    ///         has not closed and whose execution succeeds in a dry run: every such action, or
    ///         only the ids the args entry of `functionName_` lists under `actionIds`.
    /// @dev An action that does not exist, is executed or cancelled, is not ready, has
    ///      expired, or would revert is reported with the reason and left out; an expired or
    ///      stale action keeps its keys until it is cancelled. Each dry run is isolated, while
    ///      the included executions share one transaction: with a multisig owner and more
    ///      than one of them, the Safe multisend is atomic and one reverting execution fails
    ///      all of them.
    function _planExecuteReady(
        IConfigTimelockBatchQueue timelock_,
        string memory name_,
        string memory functionName_
    ) internal {
        uint64 nextActionId = timelock_.nextActionId();

        console2.log(string.concat("\n=== Execute the ready actions of ", name_, " ==="));
        console2.log("Timelock:", address(timelock_));
        console2.log("Block timestamp:", vm.getBlockTimestamp());
        console2.log("Queued actions so far:", nextActionId - 1);

        uint64[] memory candidates = _executionCandidates(timelock_, functionName_);
        for (uint256 i = 0; i < candidates.length; ++i) {
            _considerExecution(timelock_, nextActionId, candidates[i]);
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

        _validatedTimelock = address(timelock_);
        _setPostBatchValidateSelector(this._validateExecuted.selector);
    }

    /// @notice Returns the action ids an execution run considers: the `actionIds` list of the
    ///         args file, without repetitions, or every unresolved action.
    function _executionCandidates(
        IConfigTimelockBatchQueue timelock_,
        string memory functionName_
    ) internal view returns (uint64[] memory ids) {
        string memory path = string.concat(
            ".functions[?(@.name == '",
            functionName_,
            "')].args.actionIds"
        );
        if (bytes(_argsFile).length == 0 || !vm.keyExistsJson(_argsFile, path)) {
            return _unresolvedActionIds(timelock_);
        }

        uint256[] memory listed = _argsFile.readUintArray(path);
        uint64[] memory buffer = new uint64[](listed.length);
        uint256 count = 0;
        for (uint256 i = 0; i < listed.length; ++i) {
            uint64 actionId = SafeCast.encodeUInt64(listed[i]);
            bool repeated = false;
            for (uint256 j = 0; j < count; ++j) {
                if (buffer[j] != actionId) continue;
                repeated = true;
                break;
            }
            if (repeated) {
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

        uint256 timestamp = vm.getBlockTimestamp();
        _logAction(actionId_, action, timestamp);
        Status actionStatus = _status(action, timestamp);
        if (actionStatus == Status.Delayed) {
            console2.log("    Not ready: executable at", action.executableAt);
            return;
        }
        if (actionStatus == Status.Expired) {
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

    /// @notice Executes an action inside a state snapshot that is reverted afterwards, to
    ///         learn whether the execution would succeed.
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
            _fail("the dry run state was not reverted")
        );
    }

    /// @notice Names the error of a failed dry run. Covers the errors of the queue base and
    ///         of the dependency check; a batch adds the errors of its own contracts and
    ///         falls back on this function.
    function _describeRevert(
        bytes memory revertData_
    ) internal view virtual returns (string memory text) {
        if (revertData_.length < SELECTOR_LENGTH) return "empty revert data";
        bytes4 selector = _selectorOf(revertData_);
        if (
            selector ==
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        )
            return
                "ConfigStateChanged (the configuration moved since queueing; cancel the action and reconcile again)";
        if (selector == IEnabler.NotEnabled.selector)
            return "NotEnabled (the timelock or its destination is disabled)";
        if (selector == PolicyDependency.PolicyDependency_NotActive.selector)
            return
                "PolicyDependency_NotActive (the destination of the timelock is not active in the Kernel or is disabled)";
        if (selector == IPolicyAdmin.NotAuthorised.selector)
            return "NotAuthorised (the destination does not accept the timelock as its caller)";
        return string.concat("revert selector ", vm.toString(abi.encodePacked(selector)));
    }

    /// @notice Returns the error selector of revert data of at least four bytes.
    function _selectorOf(bytes memory revertData_) internal pure returns (bytes4 selector) {
        // casting to 'bytes4' is safe because only the error selector is wanted
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(revertData_);
    }

    /// @notice Returns revert data of at least four bytes without its selector: the ABI
    ///         encoding of the error arguments.
    function _withoutSelector(
        bytes memory revertData_
    ) internal pure returns (bytes memory arguments) {
        arguments = new bytes(revertData_.length - SELECTOR_LENGTH);
        for (uint256 i = 0; i < arguments.length; ++i) {
            arguments[i] = revertData_[i + SELECTOR_LENGTH];
        }
    }

    // =========== QUEUE: CANCELLATION =========== //

    /// @notice Plans the cancellation of one action, whose id the args entry of
    ///         `functionName_` carries under `actionId`.
    /// @dev Reverts if:
    ///      - The timelock is not active in the Kernel (a cancellation requires it).
    ///      - The action does not exist, or is already executed or cancelled.
    ///      - The action has not expired and the batch owner is neither its proposer nor an
    ///        `admin` or `emergency` holder.
    function _planCancelById(
        IConfigTimelockBatchQueue timelock_,
        address kernel_,
        string memory name_,
        string memory functionName_
    ) internal {
        uint64 actionId = SafeCast.encodeUInt64(_readBatchArgUint256(functionName_, "actionId"));

        console2.log(string.concat("\n=== Cancel an action of ", name_, " ==="));
        console2.log("Timelock:", address(timelock_));
        console2.log("Action:", actionId);

        _requireActive(kernel_, address(timelock_), name_, "and a cancellation requires it");
        require(
            actionId != 0 && actionId < timelock_.nextActionId(),
            _fail(string.concat("action ", vm.toString(actionId), " does not exist"))
        );
        ITimelockBatchQueue.QueuedAction memory action = timelock_.getQueuedAction(actionId);
        require(!action.executed, _fail("the action is already executed"));
        require(!action.cancelled, _fail("the action is already cancelled"));
        _logAction(actionId, action, vm.getBlockTimestamp());

        require(
            _mayCancel(kernel_, action),
            _fail(
                "the action has not expired and the batch owner is neither its proposer nor an admin or emergency holder"
            )
        );

        addToBatch(
            address(timelock_),
            abi.encodeWithSelector(ITimelockBatchQueue.cancelQueuedAction.selector, actionId)
        );
        _expectedCancelled = actionId;
        console2.log("Added: cancelQueuedAction(", actionId, ")");

        _validatedTimelock = address(timelock_);
        _setPostBatchValidateSelector(this._validateCancelled.selector);
    }

    // =========== RECONCILIATION =========== //

    /// @notice Records a change that the desired state needs.
    function _addPlanned(
        string memory description_,
        ITimelockBatchQueue.BatchAction memory action_,
        bytes memory queueCall_,
        bytes32[] memory keys_
    ) internal {
        Planned storage planned = _plan.push();
        planned.description = description_;
        planned.action = action_;
        planned.queueCall = queueCall_;
        planned.keys = keys_;
        console2.log("  Planned:", description_);
    }

    /// @notice Turns the plan into batch calls: the cancellations of the pending actions that
    ///         stand in its way, or, when there is none, the queue calls of the changes that
    ///         no pending action carries yet. Lists the unresolved queue afterwards.
    /// @param entryPoint_ The entry point to run again after a run of cancellations.
    /// @param converged_ The line printed when the plan is empty.
    function _reconcileQueue(
        IConfigTimelockBatchQueue timelock_,
        address kernel_,
        string memory entryPoint_,
        string memory converged_
    ) internal {
        console2.log("\n--- Queue ---");
        _planCancellations(timelock_, kernel_);
        if (_cancelledIds.length > 0) {
            _logCancelOnlyRun(timelock_, entryPoint_);
        } else {
            uint256 length = _plan.length;
            for (uint256 i = 0; i < length; ++i) {
                _queuePlanned(timelock_, i);
            }
            if (length == 0) console2.log(converged_);
        }
        _logReconciledQueue(timelock_);

        _validatedTimelock = address(timelock_);
        _setPostBatchValidateSelector(this._validateReconcile.selector);
    }

    /// @notice Adds a cancellation for every pending action that holds a key of a planned
    ///         change while being expired or carrying another intent, across the whole plan.
    /// @dev Reverts if:
    ///      - An unexpired holder was queued from an args file (`_isImperative`).
    ///      - The batch owner may not cancel a holder (`_mayCancel`).
    function _planCancellations(IConfigTimelockBatchQueue timelock_, address kernel_) internal {
        uint256 length = _plan.length;
        for (uint256 i = 0; i < length; ++i) {
            Planned storage planned = _plan[i];
            for (uint256 k = 0; k < planned.keys.length; ++k) {
                uint64 pendingId = timelock_.pendingActionId(planned.keys[k]);
                if (pendingId == 0 || _isCancelledByRun(pendingId)) continue;

                ITimelockBatchQueue.QueuedAction memory pending = timelock_.getQueuedAction(
                    pendingId
                );
                bool expired = vm.getBlockTimestamp() > pending.expiresAt;
                if (!expired && _holdsChange(pending, planned)) continue;

                _cancelPending(timelock_, kernel_, pendingId, pending, expired, planned);
            }
        }
    }

    /// @notice Adds the cancellation of a pending action that holds a key of a planned
    ///         change, after checking that the reconciliation may cancel it.
    function _cancelPending(
        IConfigTimelockBatchQueue timelock_,
        address kernel_,
        uint64 pendingId_,
        ITimelockBatchQueue.QueuedAction memory pending_,
        bool expired_,
        Planned storage planned_
    ) internal {
        require(
            expired_ || !_isImperative(pending_),
            _fail(
                string.concat(
                    "action ",
                    vm.toString(pendingId_),
                    " (",
                    _describeSubAction(pending_.actions[0]),
                    ") holds a key of ",
                    planned_.description,
                    "; it was queued from an args file, not from env.json, so it is not cancelled on the operator's behalf: execute it once it is ready, or cancel it by id with cancelQueuedAction, then run again"
                )
            )
        );
        require(
            _mayCancel(kernel_, pending_),
            _fail(
                string.concat(
                    "action ",
                    vm.toString(pendingId_),
                    " holds a key of ",
                    planned_.description,
                    " and was proposed by ",
                    vm.toString(pending_.proposer),
                    "; until it expires only its proposer, admin or emergency can cancel it (see cancelQueuedActionEmergency)"
                )
            )
        );
        console2.log(
            expired_
                ? "  Cancelling expired action"
                : "  Cancelling action with another intent on a needed key:",
            pendingId_,
            "for",
            planned_.description
        );
        addToBatch(
            address(timelock_),
            abi.encodeWithSelector(ITimelockBatchQueue.cancelQueuedAction.selector, pendingId_)
        );
        _cancelledIds.push(pendingId_);
    }

    /// @notice Queues a planned change unless an unexpired, uncancelled pending action already
    ///         carries it. In a run without cancellations every holder of a needed key is such
    ///         an action.
    function _queuePlanned(IConfigTimelockBatchQueue timelock_, uint256 index_) internal {
        Planned storage planned = _plan[index_];
        console2.log("\n", planned.description);

        uint64 pendingId = _pendingHolder(timelock_, planned);
        if (pendingId != 0) {
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

    /// @notice Lists the planned changes of a run that holds cancellations only: the ones an
    ///         uncancelled pending action already carries, and the ones the next run queues.
    function _logCancelOnlyRun(
        IConfigTimelockBatchQueue timelock_,
        string memory entryPoint_
    ) internal view {
        console2.log(
            string.concat(
                "\nCancellations only: this run queues nothing. Run ",
                entryPoint_,
                " again once the cancellations have landed to queue the replacements."
            )
        );
        uint256 length = _plan.length;
        for (uint256 i = 0; i < length; ++i) {
            Planned storage planned = _plan[i];
            uint64 pendingId = _pendingHolder(timelock_, planned);
            if (pendingId != 0) {
                console2.log("  Already queued as action", pendingId, ":", planned.description);
            } else {
                console2.log("  Queued by the next run:", planned.description);
            }
        }
    }

    /// @notice Lists every unresolved queued action after a plan: cancelled by this run,
    ///         carrying a planned change, or outside the plan, with the sub-actions that
    ///         conflict with the desired state where it decides it.
    function _logReconciledQueue(IConfigTimelockBatchQueue timelock_) internal view {
        uint64[] memory ids = _unresolvedActionIds(timelock_);
        console2.log("\n--- Unresolved queued actions:", ids.length, "---");
        uint256 timestamp = vm.getBlockTimestamp();
        for (uint256 i = 0; i < ids.length; ++i) {
            ITimelockBatchQueue.QueuedAction memory action = timelock_.getQueuedAction(ids[i]);
            _logAction(ids[i], action, timestamp);
            if (_isCancelledByRun(ids[i])) {
                console2.log("    Cancelled by this run.");
            } else if (_carriesPlannedChange(action)) {
                console2.log("    Part of this plan: carries a planned change and is left alone.");
            } else {
                console2.log(
                    _status(action, timestamp) == Status.Expired
                        ? "    Not in this plan: expired; holds its keys until it is cancelled (cancelQueuedAction)."
                        : "    Not in this plan: executes once ready unless it is cancelled (cancelQueuedAction)."
                );
                for (uint256 k = 0; k < action.actions.length; ++k) {
                    string memory verdict = _conflict(action.actions[k]);
                    if (bytes(verdict).length == 0) continue;
                    console2.log("    ", _describeSubAction(action.actions[k]), verdict);
                }
            }
        }
    }

    /// @notice Returns the pending action, not cancelled by this run, that holds a key of a
    ///         planned change, or zero when every key is free.
    function _pendingHolder(
        IConfigTimelockBatchQueue timelock_,
        Planned storage planned_
    ) internal view returns (uint64 pendingId) {
        for (uint256 k = 0; k < planned_.keys.length; ++k) {
            pendingId = timelock_.pendingActionId(planned_.keys[k]);
            if (pendingId != 0 && !_isCancelledByRun(pendingId)) return pendingId;
        }
        return 0;
    }

    /// @notice Returns whether a queued action carries a planned change: the one call of the
    ///         change and nothing else. An action that shares a key with a planned change but
    ///         differs in its call holds the key with another intent, since executing it
    ///         would apply a change that is not desired or leave the desired one out.
    function _holdsChange(
        ITimelockBatchQueue.QueuedAction memory action_,
        Planned memory planned_
    ) internal pure returns (bool holds) {
        if (action_.actions.length != 1) return false;
        ITimelockBatchQueue.BatchAction memory sub = action_.actions[0];
        return
            sub.target == planned_.action.target &&
            sub.selector == planned_.action.selector &&
            keccak256(sub.payload) == keccak256(planned_.action.payload);
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

    function _isCancelledByRun(uint64 actionId_) internal view returns (bool cancelled) {
        uint256 length = _cancelledIds.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_cancelledIds[i] == actionId_) return true;
        }
        return false;
    }

    // =========== MESSAGES =========== //

    /// @notice Prefixes a failure message with the name of the batch.
    function _fail(string memory text_) internal pure returns (string memory message) {
        return string.concat(_batchName(), ": ", text_);
    }

    function _singleKey(bytes32 key_) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = key_;
    }
}

// forge-lint: disable-end(calls-loop,custom-errors,require-revert-in-loop)
