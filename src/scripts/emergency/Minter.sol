// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergency} from "src/policies/interfaces/IEmergency.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

contract Minter is BatchScriptV2 {
    /// @notice Emergency shutdown of MINTR minting
    ///
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it
    /// @param argsFilePath_ Path to the arguments file (not used for this script)
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable)
    /// @param signature_ Optional signature for the batch (if submitting pre-signed transaction)
    /// @dev    Calls the Emergency policy's shutdownMinting() function
    ///         Uses Emergency MS for execution
    function run(
        bool signOnly_,
        string memory argsFilePath_,
        string memory ledgerDerivationPath_,
        bytes memory signature_
    ) external setUpEmergency(signOnly_, argsFilePath_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFilePath_);

        console2.log("\n");
        console2.log("Shutting down MINTR minting");

        address emergencyAddress = _envAddressNotZero("olympus.policies.Emergency");
        addToBatch(emergencyAddress, abi.encodeWithSelector(IEmergency.shutdownMinting.selector));

        // Run
        proposeBatch();

        console2.log("Completed");
    }
}
