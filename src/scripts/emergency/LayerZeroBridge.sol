// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

interface ICrossChainBridge {
    function setBridgeStatus(bool isActive_) external;
}

/// @notice Disables the LayerZero cross-chain bridge by setting its status to inactive
/// @dev    Requires DAO multisig (bridge_admin role)
contract LayerZeroBridge is BatchScriptV2, IEmergencyBatch {
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
        console2.log("Disabling LayerZero bridge");

        address bridgeAddress = _envAddressNotZero("olympus.policies.CrossChainBridge");
        addToBatch(
            bridgeAddress,
            abi.encodeWithSelector(ICrossChainBridge.setBridgeStatus.selector, false)
        );

        proposeBatch();

        console2.log("Completed");
    }
}
