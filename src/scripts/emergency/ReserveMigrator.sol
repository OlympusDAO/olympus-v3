// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

interface IReserveMigrator {
    function deactivate() external;
}

/// @notice Deactivates the ReserveMigrator policy via the DAO multisig
contract ReserveMigrator is BatchScriptV2, IEmergencyBatch {
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
        console2.log("Deactivating Reserve Migrator");

        address reserveMigratorAddress = _envAddressNotZero("olympus.policies.ReserveMigrator");
        addToBatch(
            reserveMigratorAddress,
            abi.encodeWithSelector(IReserveMigrator.deactivate.selector)
        );

        proposeBatch();

        console2.log("Completed");
    }
}
