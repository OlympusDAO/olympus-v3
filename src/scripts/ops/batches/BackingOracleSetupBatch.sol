// SPDX-License-Identifier: Unlicense
// solhint-disable custom-errors
pragma solidity ^0.8.24;

// Script code, run off-chain by forge: a failed `require` is meant to abort the whole run with
// its message.
// forge-lint: disable-start(custom-errors)

import {console2} from "@forge-std-1.16.2/console2.sol";

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {BackingOracleBatchScript} from "src/scripts/ops/lib/BackingOracleBatchScript.sol";

/// @title BackingOracleSetupBatch
/// @notice The multisig batch that prepares the Kernel membership of the BackingOracle and its
///         BackingOracleConfigTimelock. The entry point is declarative: it reads the live
///         state and adds only the activations that are missing, so a second run on a
///         converged state proposes nothing.
///
///         Entry points:
///         - `setupKernel` (DAO MS as the Kernel executor): activate the oracle and its
///           timelock in the Kernel. Neither is enabled here: binding the timelock as the
///           config operator and the first `enable` of both, with the initial backing, are
///           admin calls, which on mainnet belong to an OCG proposal.
///
///         The batches of YieldRepurchaseFacilityV2 activate the pair together with the
///         facility stack (`YieldRepurchaseFacilityV2SetupBatch.setupKernel`); this batch
///         serves a deployment of the oracle pair alone.
contract BackingOracleSetupBatch is BackingOracleBatchScript {
    // =========== ENTRY POINTS =========== //

    /// @notice Activates the BackingOracle and its config timelock in the Kernel (DAO MS as the
    ///         Kernel executor).
    /// @dev Each activation is added only when the policy is not active. The heart beat
    ///      validation is skipped while the oracle is disabled: the activation of a disabled
    ///      oracle changes nothing that a heart beat reads.
    ///
    ///      Reverts if:
    ///      - The args file is not empty.
    ///      - The oracle and the timelock are not bound to each other, or either reports
    ///        another Kernel.
    ///      - The batch owner is not the Kernel executor.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    function setupKernel(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        _validateArgsFileEmpty(argsFile_);

        OracleStack memory stack = _oracleStack();

        console2.log("\n=== Activate the BackingOracle and its config timelock in the Kernel ===");
        console2.log("Kernel:", stack.kernel);
        console2.log("BackingOracle:", stack.oracle);
        console2.log("BackingOracleConfigTimelock:", stack.timelock);

        _requireKernelExecutor(stack.kernel);

        // An oracle that is enabled starts serving its backing to the facility once it is
        // active, so the heart beat is validated then; a disabled one serves nothing
        _skipHeartbeatValidation = !IEnabler(stack.oracle).isEnabled();

        _planActivatePolicy(stack.kernel, stack.oracle, ORACLE_NAME);
        _planActivatePolicy(stack.kernel, stack.timelock, ORACLE_TIMELOCK_NAME);

        _setPostBatchValidateSelector(this._validateSetupKernel.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validates the state after `setupKernel`: both policies are active in the
    ///         Kernel.
    function _validateSetupKernel() external view {
        OracleStack memory stack = _oracleStack();

        console2.log("\nValidating setupKernel post-batch state");
        require(_isActive(stack.kernel, stack.oracle), "BackingOracle is not active in the Kernel");
        require(
            _isActive(stack.kernel, stack.timelock),
            "BackingOracleConfigTimelock is not active in the Kernel"
        );
        console2.log("  Both policies are active in the Kernel");
        console2.log("setupKernel post-batch validation passed");
    }

    // =========== HOOKS =========== //

    function _batchName() internal pure override returns (string memory name) {
        return "BackingOracleSetupBatch";
    }
}

// forge-lint: disable-end(custom-errors)
