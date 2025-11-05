// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

contract CoolerV2 is BatchScriptV2, IEmergencyBatch {
    /// @notice Emergency shutdown of all Cooler V2 operations
    ///
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it
    /// @param argsFilePath_ Path to the arguments file (not used for this script)
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable)
    /// @param signature_ Optional signature for the batch (if submitting pre-signed transaction)
    /// @dev    Shuts down:
    ///         - Pauses borrows on CoolerV2
    ///         - Pauses liquidations on CoolerV2
    ///         - Disables CoolerComposites
    ///         - Disables CoolerV2Migrator
    ///         Uses Emergency MS for execution (for CoolerV2), DAO MS for composites/migrator
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
        console2.log("Shutting down Cooler V2 operations");

        // Pause borrows on CoolerV2
        address coolerV2Address = _envAddressNotZero("olympus.policies.CoolerV2");
        console2.log("  Pausing borrows");
        addToBatch(
            coolerV2Address,
            abi.encodeWithSelector(IMonoCooler.setBorrowPaused.selector, true)
        );

        // Pause liquidations on CoolerV2
        console2.log("  Pausing liquidations");
        addToBatch(
            coolerV2Address,
            abi.encodeWithSelector(IMonoCooler.setLiquidationsPaused.selector, true)
        );

        // Disable CoolerComposites
        address compositesAddress = _envAddressNotZero("olympus.periphery.CoolerComposites");
        console2.log("  Disabling CoolerComposites");
        addToBatch(compositesAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Disable CoolerV2Migrator
        address migratorAddress = _envAddressNotZero("olympus.periphery.CoolerV2Migrator");
        console2.log("  Disabling CoolerV2Migrator");
        addToBatch(migratorAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        // Run
        proposeBatch();

        console2.log("Completed");
    }
}
