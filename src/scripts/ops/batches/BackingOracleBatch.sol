// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: a failed `require` is meant to abort the whole run with
// its message.
// forge-lint: disable-start(custom-errors)

import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE, BACKING_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BackingOracleBatchScript} from "src/scripts/ops/lib/BackingOracleBatchScript.sol";

/// @title BackingOracleBatch
/// @notice The lifecycle batches of the BackingOracle and its BackingOracleConfigTimelock.
///         Every entry point is declarative: it reads the live state and adds only the calls
///         that are missing, so a second run on a converged state proposes nothing.
///
///         Entry points:
///         - `reEnable` (DAO MS as `backing_admin`): re-enable the oracle and its timelock
///           after a disable, while their grace windows of 7 days are open.
///         - `freezeUpdatesEmergencyMS` (Emergency MS): disable the timelock, which stops the
///           queueing and the execution of backing updates. The oracle keeps serving its
///           backing, and the admin role can still set it directly.
///         - `haltAllEmergencyMS` (Emergency MS): disable the timelock and the oracle. The
///           oracle then serves no backing to its consumers.
///
///         A disabled or Kernel-inactive oracle reports no backing to the
///         YieldRepurchaseFacilityV2: the price gate of the facility closes, so its daily
///         cycles open no markets and keep the purchased OHM accumulated, and its `enable`
///         and `reEnable` revert. A market that is already live stays purchasable until it
///         concludes; the hard stop of the purchases is the disable of the facility
///         (`YieldRepurchaseFacilityV2Batch.stopPurchasesEmergencyMS`).
///
///         The levers have no DAO MS variant: `disable()` is gated to `emergency` and `admin`,
///         and on mainnet the DAO MS holds neither. The disable of the oracle alone is not
///         offered: it differs from `haltAllEmergencyMS` only in leaving the timelock enabled,
///         so that a matured action executes the moment the oracle is re-enabled.
///
///         The first `enable` of both policies and the binding of the timelock as the config
///         operator are admin calls: on mainnet they belong to an OCG proposal. Backing
///         updates run through `BackingOracleConfigTimelockBatch`.
contract BackingOracleBatch is BackingOracleBatchScript {
    // =========== ENTRY POINTS =========== //

    /// @notice Re-enables the oracle and its config timelock after a disable, while their
    ///         grace windows are open (DAO MS as `backing_admin`, or an `admin` holder).
    /// @dev A policy that is enabled, that has never been enabled or whose grace window has
    ///      elapsed is reported and skipped: the last two need the admin `enable` path, which
    ///      on mainnet is an OCG proposal. The oracle is re-enabled first, so that queueing
    ///      and execution, which require the oracle enabled, resume as soon as the timelock is
    ///      re-enabled. The backing and the config operator are kept across the disable.
    ///
    ///      Re-enabling the timelock makes every matured queued action executable by any
    ///      account at once: the run lists the unresolved actions, and the ones that must not
    ///      survive are cancelled first (`BackingOracleConfigTimelockBatch.cancelQueuedAction`
    ///      or `cancelQueuedActionEmergency`).
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The oracle or the timelock is not active in the Kernel, or the oracle does not
    ///        name the timelock as its config operator: the re-enabled pair could neither
    ///        queue nor execute.
    ///      - A re-enable is due and the batch owner holds neither `backing_admin` nor
    ///        `admin`.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function reEnable(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);

        OracleStack memory stack = _oracleStack();

        console2.log(
            "\n=== Re-enable the BackingOracle and its config timelock within the grace window ==="
        );
        _requireOracleWired(stack);

        bool oracleDue = _reEnableDue(stack.oracle, ORACLE_NAME);
        bool timelockDue = _reEnableDue(stack.timelock, ORACLE_TIMELOCK_NAME);
        if (oracleDue || timelockDue) {
            ROLESv1 roles = _roles(stack.kernel);
            require(
                roles.hasRole(_owner, BACKING_ADMIN_ROLE) || roles.hasRole(_owner, ADMIN_ROLE),
                _fail(
                    "the batch owner holds neither backing_admin nor admin, the gate of reEnable(); on mainnet the DAO MS receives backing_admin from the launch proposal of YieldRepurchaseFacilityV2"
                )
            );
        }
        console2.log("");
        if (oracleDue) _planReEnable(stack.oracle, ORACLE_NAME);
        if (timelockDue) _planReEnable(stack.timelock, ORACLE_TIMELOCK_NAME);
        if (!oracleDue && !_oracleServes(stack)) {
            console2.log("The BackingOracle stays disabled.", ORACLE_DOWN_CONSEQUENCE);
        }

        _logUnresolvedQueue(
            IConfigTimelockBatchQueue(stack.timelock),
            ORACLE_TIMELOCK_NAME,
            "Once the oracle and the timelock are enabled, a matured action executes permissionlessly. Cancel the ones that must not survive before this batch lands (BackingOracleConfigTimelockBatch.cancelQueuedAction or cancelQueuedActionEmergency); an action whose window closed meanwhile has expired and must be cancelled and queued again."
        );

        _setPostBatchValidateSelector(this._validateReEnable.selector);

        proposeBatch();
    }

    /// @notice Freezes the backing updates through the timelock: disables the
    ///         BackingOracleConfigTimelock (Emergency MS).
    /// @dev Queueing and execution stop; the queued actions are kept, hold their key and may
    ///      expire. The oracle keeps serving its backing, and the admin role can still call
    ///      `setBacking` directly. Skipped when the timelock is already disabled. Recovery is
    ///      `reEnable` within the grace window of 7 days, or the admin `enable` path
    ///      afterwards. The heart beat validation is skipped: a heart beat does not read the
    ///      timelock.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function freezeUpdatesEmergencyMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        // The batch touches only the timelock, which a heart beat does not read
        _skipHeartbeatValidation = true;

        OracleStack memory stack = _oracleStack();
        _requireOracleDisableAuthority(stack);

        console2.log(
            "\n=== Freeze the backing updates: disable the BackingOracleConfigTimelock ==="
        );
        _planDisable(stack.timelock, ORACLE_TIMELOCK_NAME);
        console2.log(
            "The BackingOracle keeps serving its backing:",
            IBackingOracle(stack.oracle).backing()
        );

        _logHaltedQueue(stack);
        _setPostBatchValidateSelector(this._validateLifecycle.selector);

        proposeBatch();
    }

    /// @notice Halts the oracle pair: disables the BackingOracleConfigTimelock and the
    ///         BackingOracle (Emergency MS).
    /// @dev The oracle then serves no backing: the price gate of the
    ///      YieldRepurchaseFacilityV2 closes, its daily cycles open no markets and keep the
    ///      purchased OHM accumulated, and its `enable` and `reEnable` revert; a market that
    ///      is already live stays purchasable until it concludes. A policy that is already
    ///      disabled is skipped. The stored backing and the config operator are kept.
    ///      Recovery is `reEnable` within the grace window of 7 days, or the admin `enable`
    ///      path afterwards, which sets the backing anew.
    ///
    ///      The heart beat is validated after the batch; `EMERGENCY_SKIP_HEARTBEAT_VALIDATION`
    ///      set to `true` in the environment builds the lever without it, for a Heart that
    ///      fails for a reason the lever does not remove.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The batch owner holds neither `emergency` nor `admin`.
    /// @param useDaoMS_ Ignored; the owner is the Emergency MS.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function haltAllEmergencyMS(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);
        _applyEmergencyHeartbeatOptOut();

        OracleStack memory stack = _oracleStack();
        _requireOracleDisableAuthority(stack);

        console2.log(
            "\n=== Halt the oracle: disable the config timelock and the BackingOracle ==="
        );
        _planDisable(stack.timelock, ORACLE_TIMELOCK_NAME);
        _planDisable(stack.oracle, ORACLE_NAME);
        console2.log(ORACLE_DOWN_CONSEQUENCE);

        _logHaltedQueue(stack);
        _setPostBatchValidateSelector(this._validateLifecycle.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `reEnable`: the re-enabled flags, both policies
    ///         active in the Kernel and the timelock named as the config operator.
    function _validateReEnable() external view {
        console2.log("\nValidating reEnable post-batch state");
        _requireOracleWired(_oracleStack());
        console2.log(
            "  Both policies are active in the Kernel and the timelock is the config operator"
        );
        _requireLifecycle();
    }

    // =========== INTERNAL HELPERS =========== //

    function _requireOracleDisableAuthority(OracleStack memory stack_) internal view {
        _requireDisableAuthority(
            stack_.kernel,
            "on mainnet the Emergency MS holds emergency and the OCG timelock holds admin, and the DAO MS holds neither"
        );
    }

    /// @notice Lists the unresolved queued actions that a disable leaves behind.
    function _logHaltedQueue(OracleStack memory stack_) internal view {
        _logUnresolvedQueue(
            IConfigTimelockBatchQueue(stack_.timelock),
            ORACLE_TIMELOCK_NAME,
            "Their execution is blocked while the timelock or the oracle is disabled, and each keeps the backing key reserved. Before reEnable, cancel the ones that must not survive (BackingOracleConfigTimelockBatch.cancelQueuedAction or cancelQueuedActionEmergency); an action whose window closes meanwhile expires and must be cancelled before a new update can be queued."
        );
    }

    // =========== HOOKS =========== //

    function _batchName() internal pure override returns (string memory name) {
        return "BackingOracleBatch";
    }
}

// forge-lint: disable-end(custom-errors)
