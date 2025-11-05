// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

contract ConvertibleDeposits is BatchScriptV2, IEmergencyBatch {
    /// @notice Emergency shutdown of Convertible Deposits system
    ///
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it
    /// @param argsFilePath_ Path to the arguments file (not used for this script)
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable)
    /// @param signature_ Optional signature for the batch (if submitting pre-signed transaction)
    /// @dev    Shuts down:
    ///         - Disables ConvertibleDepositFacility
    ///         - Disables DepositRedemptionVault
    ///         - Disables DepositManager
    ///         Uses Emergency MS for execution
    function run(
        bool signOnly_,
        string memory argsFilePath_,
        string memory ledgerDerivationPath_,
        bytes memory signature_
    )
        external
        override
        setUpEmergency(signOnly_, argsFilePath_, ledgerDerivationPath_, signature_)
    {
        _validateArgsFileEmpty(argsFilePath_);

        console2.log("\n");
        console2.log("Shutting down Convertible Deposits");

        // Disable ConvertibleDepositFacility
        address facilityAddress = _envAddressNotZero("olympus.policies.ConvertibleDepositFacility");
        console2.log("  Disabling ConvertibleDepositFacility");
        addToBatch(facilityAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Disable DepositRedemptionVault
        address vaultAddress = _envAddressNotZero("olympus.policies.DepositRedemptionVault");
        console2.log("  Disabling DepositRedemptionVault");
        addToBatch(vaultAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Disable DepositManager
        address managerAddress = _envAddressNotZero("olympus.policies.DepositManager");
        console2.log("  Disabling DepositManager");
        addToBatch(managerAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Run
        proposeBatch();

        console2.log("Completed");
    }
}
