// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

interface IYieldRepurchaseFacility {
    function shutdown(ERC20[] memory tokensToTransfer) external;
}

/// @notice Shuts down the Yield Repurchase Facility by transferring USDS and sUSDS back to treasury
/// @dev    Requires DAO multisig (loop_daddy role)
contract YieldRepurchaseFacility is BatchScriptV2, IEmergencyBatch {
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
        console2.log("Shutting down Yield Repurchase Facility");

        address facilityAddress = _envAddressNotZero("olympus.policies.YieldRepurchaseFacility");
        address usds = _envAddressNotZero("external.tokens.USDS");
        address sUsds = _envAddressNotZero("external.tokens.sUSDS");

        ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = ERC20(usds);
        tokens[1] = ERC20(sUsds);

        addToBatch(
            facilityAddress,
            abi.encodeWithSelector(IYieldRepurchaseFacility.shutdown.selector, tokens)
        );

        proposeBatch();

        console2.log("Completed");
    }
}
