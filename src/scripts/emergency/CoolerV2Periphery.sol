// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Disables Cooler V2 periphery contracts that are owned by the DAO multisig
/// @dev    Targets:
///         - CoolerComposites
///         - CoolerV2Migrator
contract CoolerV2Periphery is BatchScriptV2, IEmergencyBatch {
    function run(
        bool signOnly_,
        string memory argsFilePath_,
        string memory ledgerDerivationPath_,
        bytes memory signature_
    )
        external
        override
        setUp(
            true, // Runs as DAO MS
            signOnly_,
            argsFilePath_,
            ledgerDerivationPath_,
            signature_
        )
    {
        _validateArgsFileEmpty(argsFilePath_);

        console2.log("\n");
        console2.log("Disabling Cooler V2 periphery contracts");

        address compositesAddress = _envAddressNotZero("olympus.periphery.CoolerComposites");
        console2.log("  Disabling CoolerComposites");
        addToBatch(compositesAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        address migratorAddress = _envAddressNotZero("olympus.periphery.CoolerV2Migrator");
        console2.log("  Disabling CoolerV2Migrator");
        addToBatch(migratorAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();

        console2.log("Completed");
    }
}
