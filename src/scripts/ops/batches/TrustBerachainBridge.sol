// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import {LayerZeroConstants} from "src/scripts/LayerZeroConstants.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";
import {CrossChainBridge} from "src/policies/CrossChainBridge.sol";

/// @notice     Sets the Berachain Bridge as trusted
contract TrustBerachainBridge is OlyBatch {
    using stdJson for string;

    address kernel;
    address mainnetBridge;
    address berachainBridge;

    function _envAddressWithChain(
        string memory chain_,
        string memory key_
    ) internal view returns (address) {
        return env.readAddress(string.concat(".current.", chain_, ".", key_));
    }

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");

        mainnetBridge = _envAddressWithChain("mainnet", "olympus.policies.CrossChainBridge");
        berachainBridge = _envAddressWithChain("berachain", "olympus.policies.CrossChainBridge");
    }

    // Entry point for the batch #1
    function setupBridge(bool send_) external isDaoBatch(send_) {
        // Validate addresses
        require(mainnetBridge != address(0), "Mainnet bridge address is not set");
        require(berachainBridge != address(0), "Berachain bridge address is not set");

        uint16 berachainLzChainId = LayerZeroConstants.getRemoteEndpointId("berachain");

        console2.log("Setting up mainnet bridge to trust berachain bridge");
        console2.log("Mainnet bridge:", mainnetBridge);
        console2.log("Berachain bridge:", berachainBridge);
        console2.log("Berachain bridge packed:");
        console2.logBytes(abi.encodePacked(berachainBridge));
        console2.log("Berachain LZ chain ID:", berachainLzChainId);

        // 1. Set the Berachain Bridge as trusted
        addToBatch(
            mainnetBridge,
            abi.encodeWithSelector(
                CrossChainBridge.setTrustedRemoteAddress.selector,
                berachainLzChainId,
                abi.encodePacked(berachainBridge)
            )
        );

        console2.log("Batch completed");
    }
}
