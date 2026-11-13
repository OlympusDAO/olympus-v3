// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: a failed `require` is meant to abort the whole run with
// its message.
// forge-lint: disable-start(custom-errors)

import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {BackingOracleConfigLib} from "src/scripts/ops/lib/BackingOracleConfigLib.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, BACKING_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BackingOracleBatchScript} from "src/scripts/ops/lib/BackingOracleBatchScript.sol";

/// @title BackingOracleConfigTimelockBatch
/// @notice Declarative backing updates of the BackingOracle through its
///         BackingOracleConfigTimelock. `env.json` is the desired state
///         (`olympus.config.BackingOracle.backing`); the oracle is the live state; the batch
///         holds only the timelock call that converges the two.
///
///         Entry points:
///         - `reconcileBacking` (DAO MS as `backing_admin`): queue `setBacking` with the
///           desired value when it differs from the live one. A pending action that already
///           carries the value is left alone. A pending action with another value, or an
///           expired one, holds the one backing key of the timelock: the run then holds its
///           cancellation only, and the next run queues the replacement. The run ends with
///           every unresolved queued action.
///         - `executeReadyActions` (anyone): execute every queued action whose delay of one
///           day has elapsed and whose execution would succeed, or only the action ids listed
///           in the args file; report the others.
///         - `cancelQueuedAction` (DAO MS as the proposer, or any owner for an expired action)
///           and `cancelQueuedActionEmergency` (Emergency MS): cancel one action by id, which
///           is the only way to release the backing key of an expired or stale action.
///
///         One update moves the backing by at most 10% of the live value, which the oracle
///         enforces when the action is queued and again when it executes. A desired value
///         outside that bound stops the run with the bound in the message: the batch computes
///         no intermediate step, so every step is declared in `env.json` and reviewed.
///
///         The backing is the value the YieldRepurchaseFacilityV2 reads for its price gate and
///         for the treasury withdrawal that backs the burn of the purchased OHM: an executed
///         update takes effect at the next heart beat.
contract BackingOracleConfigTimelockBatch is BackingOracleBatchScript {
    // =========== CONSTANTS =========== //

    /// @notice The number of arguments of `BackingOracle_BackingChangeTooLarge`, one word each.
    uint256 internal constant BACKING_CHANGE_ERROR_WORDS = 4;

    // =========== STATE =========== //

    /// @notice The backing of `env.json`, for the conflict check of the queue listing.
    uint256 internal _desiredBacking;

    // =========== ENTRY POINTS =========== //

    /// @notice Queues the backing update that converges the oracle to `env.json`, or cancels
    ///         the pending action that stands in its way (DAO MS as `backing_admin`, or an
    ///         `admin` holder).
    /// @dev The desired value is checked with `validateSetBacking` of the oracle before it is
    ///      planned, so that a rejection carries the error of the oracle; for a value outside
    ///      the bound of one update the message carries the accepted interval.
    ///
    ///      A run that cancels a pending action holds the cancellation only: execution is
    ///      permissionless, so the holder may execute before the batch lands, and the next run
    ///      plans from the resulting state. A cancellation of an action that executed in
    ///      between reverts with `ITimelockBatchQueue_ActionAlreadyExecuted` and fails the
    ///      batch.
    ///
    ///      The heart beat validation is skipped: the batch queues and cancels, and the oracle
    ///      keeps its backing until a queued action executes.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The oracle and the timelock are not bound to each other.
    ///      - The oracle or the timelock is not active in the Kernel or is disabled, or the
    ///        oracle does not name the timelock as its config operator.
    ///      - The batch owner holds neither `backing_admin` nor `admin`.
    ///      - `olympus.config.BackingOracle.backing` is missing or zero.
    ///      - The oracle rejects the desired value (`validateSetBacking`).
    ///      - A pending action holds the backing key with another value and the batch owner
    ///        may not cancel it.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function reconcileBacking(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the queue of the timelock
        _skipHeartbeatValidation = true;

        OracleStack memory stack = _oracleStack();
        uint256 desired = BackingOracleConfigLib.desiredBacking(env, chain);
        uint256 live = IBackingOracle(stack.oracle).backing();
        _desiredBacking = desired;

        console2.log("\n=== Reconcile the backing of the BackingOracle through its timelock ===");
        console2.log("BackingOracle:", stack.oracle);
        console2.log("BackingOracleConfigTimelock:", stack.timelock);
        console2.log("Live backing:   ", live);
        console2.log("Desired backing:", desired);

        _requireQueueable(stack);

        console2.log("\n--- Plan ---");
        if (desired == live) {
            console2.log("  The backing matches env.json. Nothing to do.");
        } else {
            _requireAcceptedBacking(stack.oracle, desired);
            _addPlanned(
                string.concat("setBacking(", vm.toString(desired), ")"),
                ITimelockBatchQueue.BatchAction({
                    target: stack.oracle,
                    selector: IBackingOracle.setBacking.selector,
                    payload: abi.encode(desired)
                }),
                abi.encodeCall(IBackingOracleConfigTimelock.queueSetBacking, (desired)),
                _singleKey(_backingKey(stack.oracle))
            );
        }

        _reconcileQueue(
            IConfigTimelockBatchQueue(stack.timelock),
            stack.kernel,
            "reconcileBacking",
            "No change needed: the backing of the oracle matches env.json. This describes the oracle state only; the unresolved queued actions are listed below."
        );

        proposeBatch();
    }

    /// @notice Executes the queued backing updates whose delay has elapsed, whose window has
    ///         not closed and whose execution succeeds in a dry run: every such action, or
    ///         only the listed ones when the args file names them. Anyone may run it.
    /// @dev Args file (optional):
    ///      `{"functions": [{"name": "executeReadyActions", "args": {"actionIds": [1]}}]}`
    ///      restricts the run to the listed ids. An action that does not exist, is executed or
    ///      cancelled, is not ready, has expired, or would revert (for instance with
    ///      `ConfigStateChanged` after a direct `setBacking`, or with
    ///      `BackingOracle_BackingChangeTooLarge` after the live backing moved) is reported
    ///      with the reason and left out; an expired or stale action keeps the backing key
    ///      until it is cancelled.
    ///
    ///      The heart beat is validated after the batch: the executed backing is the value the
    ///      YieldRepurchaseFacilityV2 reads at its next beat.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner; any owner may execute.
    /// @param argsFile_ Path to the arguments file (optional; may carry
    ///        "executeReadyActions.actionIds").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function executeReadyActions(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        OracleStack memory stack = _oracleStack();
        _planExecuteReady(
            IConfigTimelockBatchQueue(stack.timelock),
            ORACLE_TIMELOCK_NAME,
            "executeReadyActions"
        );
        proposeBatch();
    }

    /// @notice Cancels one queued action (DAO MS as the proposer of the action, or any `admin`
    ///         or `emergency` holder as owner; any owner once the action has expired).
    /// @dev Args file: `{"functions": [{"name": "cancelQueuedAction", "args": {"actionId": 1}}]}`.
    ///      A cancellation is available while the timelock is disabled. The heart beat
    ///      validation is skipped: a cancellation changes nothing that a heart beat reads.
    ///
    ///      Reverts if:
    ///      - The timelock is not active in the Kernel.
    ///      - The action does not exist, or is already executed or cancelled.
    ///      - The action has not expired and the batch owner is neither the proposer nor an
    ///        `admin` or `emergency` holder.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (must contain "cancelQueuedAction.actionId").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function cancelQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _planCancel("cancelQueuedAction");
        proposeBatch();
    }

    /// @notice Cancels one queued action with the Emergency MS as owner.
    /// @dev Same behaviour and args file as `cancelQueuedAction`, under the function name
    ///      `cancelQueuedActionEmergency`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (must contain
    ///        "cancelQueuedActionEmergency.actionId").
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function cancelQueuedActionEmergency(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _planCancel("cancelQueuedActionEmergency");
        proposeBatch();
    }

    // =========== INTERNAL HELPERS =========== //

    function _planCancel(string memory functionName_) internal {
        // A cancellation changes nothing that a heart beat reads
        _skipHeartbeatValidation = true;

        OracleStack memory stack = _oracleStack();
        _planCancelById(
            IConfigTimelockBatchQueue(stack.timelock),
            stack.kernel,
            ORACLE_TIMELOCK_NAME,
            functionName_
        );
    }

    /// @notice Reverts unless a `queueSetBacking` call from the batch owner would pass the
    ///         gates of the timelock.
    function _requireQueueable(OracleStack memory stack_) internal view {
        _requireOracleWired(stack_);
        require(
            IEnabler(stack_.timelock).isEnabled(),
            _fail(
                "the BackingOracleConfigTimelock is disabled, and queueing requires it enabled; re-enable it with BackingOracleBatch.reEnable inside its grace window, or through the admin enable path afterwards"
            )
        );
        require(
            IEnabler(stack_.oracle).isEnabled(),
            _fail(
                "the BackingOracle is disabled, and queueing requires it enabled; re-enable it with BackingOracleBatch.reEnable inside its grace window, or through the admin enable path afterwards"
            )
        );
        ROLESv1 roles = _roles(stack_.kernel);
        require(
            roles.hasRole(_owner, BACKING_ADMIN_ROLE) || roles.hasRole(_owner, ADMIN_ROLE),
            _fail(
                "the batch owner holds neither backing_admin nor admin, the gate of queueSetBacking; on mainnet the DAO MS receives backing_admin from the launch proposal of YieldRepurchaseFacilityV2"
            )
        );
    }

    /// @notice Reverts unless the oracle accepts the desired backing as one update of its live
    ///         value.
    /// @dev The bound of `BackingOracle_BackingChangeTooLarge` arrives in the error data:
    ///      `(currentBacking, newBacking, minBacking, maxBacking)`.
    function _requireAcceptedBacking(address oracle_, uint256 desired_) internal view {
        try IBackingOracle(oracle_).validateSetBacking(desired_) {
            console2.log("  The oracle accepts the desired backing as one update.");
        } catch (bytes memory revertData) {
            if (
                revertData.length == SELECTOR_LENGTH + BACKING_CHANGE_ERROR_WORDS * WORD_LENGTH &&
                _selectorOf(revertData) ==
                IBackingOracle.BackingOracle_BackingChangeTooLarge.selector
            ) {
                (uint256 current, , uint256 minBacking, uint256 maxBacking) = abi.decode(
                    _withoutSelector(revertData),
                    (uint256, uint256, uint256, uint256)
                );
                console2.log("  The desired backing exceeds the bound of one update.");
                console2.log("    live backing:    ", current);
                console2.log("    accepted minimum:", minBacking);
                console2.log("    accepted maximum:", maxBacking);
                revert(
                    _fail(
                        string.concat(
                            "the desired backing ",
                            vm.toString(desired_),
                            " is outside the bound of one update [",
                            vm.toString(minBacking),
                            ", ",
                            vm.toString(maxBacking),
                            "] around the live backing ",
                            vm.toString(current),
                            "; declare an intermediate value inside the bound in env.json, queue and execute it, then declare the next step"
                        )
                    )
                );
            }
            revert(
                _fail(
                    string.concat(
                        "the oracle rejects the desired backing: ",
                        _describeRevert(revertData)
                    )
                )
            );
        }
    }

    // =========== HOOKS =========== //

    function _batchName() internal pure override returns (string memory name) {
        return "BackingOracleConfigTimelockBatch";
    }

    /// @notice A queued `setBacking` conflicts when its value differs from the backing of
    ///         `env.json`.
    function _conflict(
        ITimelockBatchQueue.BatchAction memory sub_
    ) internal view override returns (string memory verdict) {
        if (
            sub_.selector != IBackingOracle.setBacking.selector ||
            sub_.payload.length != WORD_LENGTH
        ) {
            return "is not checked: not a setBacking call";
        }
        return
            abi.decode(sub_.payload, (uint256)) == _desiredBacking
                ? ""
                : "CONFLICT: sets a backing that differs from env.json";
    }
}

// forge-lint: disable-end(custom-errors)
