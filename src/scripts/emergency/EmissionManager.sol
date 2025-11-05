// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

contract EmissionManager is BatchScriptV2, IEmergencyBatch {
    /// @notice Emergency shutdown of EmissionManager and ConvertibleDepositAuctioneer
    ///
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it
    /// @param argsFilePath_ Path to the arguments file (not used for this script)
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable)
    /// @param signature_ Optional signature for the batch (if submitting pre-signed transaction)
    /// @dev    Shuts down:
    ///         - Disables EmissionManager (which also closes active bond market and disables convertible deposit auction)
    ///         - Disables ConvertibleDepositAuctioneer explicitly
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
        console2.log("Shutting down EmissionManager");

        // Disable EmissionManager
        address emissionManagerAddress = _envAddressNotZero("olympus.policies.EmissionManager");
        console2.log("  Disabling EmissionManager");
        addToBatch(emissionManagerAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Disable ConvertibleDepositAuctioneer
        address cdAuctioneerAddress = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );
        console2.log("  Disabling ConvertibleDepositAuctioneer");
        addToBatch(cdAuctioneerAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Run
        proposeBatch();

        console2.log("Completed");
    }
}
