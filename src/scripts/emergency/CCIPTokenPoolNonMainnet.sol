// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Disables the CCIP burn/mint token pool on non-canonical chains
/// @dev    Uses the Emergency multisig by default
contract CCIPTokenPoolNonMainnet is BatchScriptV2, IEmergencyBatch {
    function _isChainCanonical(string memory chain_) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("mainnet")) ||
            keccak256(abi.encodePacked(chain_)) == keccak256(abi.encodePacked("sepolia"));
    }

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

        if (_isChainCanonical(chain)) {
            revert("CCIPTokenPoolNonMainnet: only non-canonical chains");
        }

        console2.log("\n");
        console2.log("Disabling CCIP burn/mint token pool");

        address tokenPoolAddress = _envAddressNotZero("olympus.policies.CCIPBurnMintTokenPool");
        addToBatch(tokenPoolAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();

        console2.log("Completed");
    }
}
