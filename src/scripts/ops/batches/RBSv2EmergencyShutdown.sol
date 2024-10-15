// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Policies
import {IHeart} from "src/policies/RBS/interfaces/IHeart.sol";
import {IOperator} from "src/policies/RBS/interfaces/IOperator.sol";

/// @notice Emergency shutdown of RBSv2
contract RBSv2EmergencyShutdown is OlyBatch, StdAssertions {
    using stdJson for string;

    // Olympus contracts
    address operator;
    address heart;

    function loadEnv() internal override {
        operator = envAddress("current", "olympus.policies.OperatorV2");
        heart = envAddress("current", "olympus.policies.OlympusHeartV2");
    }

    function deactivate(bool send_) public isEmergencyBatch(send_) {
        console2.log("Disabling any open Operator markets");
        addToBatch(operator, abi.encodeWithSelector(IOperator.deactivate.selector));

        console2.log("Disabling Heartbeats");
        addToBatch(heart, abi.encodeWithSelector(IHeart.deactivate.selector));

        console2.log("RBSv2 deactivated");
    }

    function activate(bool send_) public isEmergencyBatch(send_) {
        console2.log("Enabling Operator");
        addToBatch(operator, abi.encodeWithSelector(IOperator.activate.selector));

        console2.log("Enabling Heartbeats");
        addToBatch(heart, abi.encodeWithSelector(IHeart.activate.selector));

        console2.log("RBSv2 activated");
    }
}
