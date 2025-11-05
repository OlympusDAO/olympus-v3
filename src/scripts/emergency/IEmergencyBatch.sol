// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

/// @title IEmergencyBatch
/// @notice Interface for emergency batch scripts
/// @dev    All emergency batch scripts should implement this interface
interface IEmergencyBatch {
    /// @notice Execute the emergency shutdown batch
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it
    /// @param argsFilePath_ Path to the arguments file (optional, may be empty)
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable)
    /// @param signature_ Optional signature for the batch (if submitting pre-signed transaction)
    function run(
        bool signOnly_,
        string memory argsFilePath_,
        string memory ledgerDerivationPath_,
        bytes memory signature_
    ) external;
}
