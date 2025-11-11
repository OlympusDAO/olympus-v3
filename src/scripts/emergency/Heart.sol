// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Disables the Olympus Heart policy via the emergency multisig
contract Heart is BatchScriptV2, IEmergencyBatch {
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
        console2.log("Disabling Olympus Heart");

        address heartAddress = _envAddressNotZero("olympus.policies.OlympusHeart");
        addToBatch(heartAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();

        console2.log("Completed");
    }
}
