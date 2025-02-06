// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";

/// @notice This is a sample batch script that fixes a misconfiguration of the EmissionManager policy with the BondFixedTermAuctioneer.
/// @dev    It should be run with `DAO_MS` set to the `bondOwner` address.
contract EmissionManagerCallbackAuthStatus is OlyBatch {
    address kernel;
    address constant bondOwner = 0x007BD11FCa0dAaeaDD455b51826F9a015f2f0969;
    address bondFixedTermAuctioneer;
    address emissionManager;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        bondFixedTermAuctioneer = envAddress(
            "current",
            "external.bond-protocol.BondFixedTermAuctioneer"
        );
        emissionManager = envAddress("current", "olympus.policies.EmissionManager");
    }

    // Entry point for the batch #1
    function fix(bool send_) external isDaoBatch(send_) {
        addToBatch(
            bondFixedTermAuctioneer,
            abi.encodeWithSelector(
                IBondAuctioneer.setCallbackAuthStatus.selector,
                emissionManager,
                true
            )
        );
    }
}
