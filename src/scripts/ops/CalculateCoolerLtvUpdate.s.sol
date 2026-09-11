// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import {WithEnvironment} from "../WithEnvironment.s.sol";
import {ICoolerLtvOracle} from "../../policies/interfaces/cooler/ICoolerLtvOracle.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title Update Cooler LTV
 * @notice Operational script to update CoolerV2 OLTV on Sepolia
 *
 * This script will:
 * 1. Query current state
 * 2. Calculate required rate of change
 * 3. Update limits if necessary
 * 4. Set the target OLTV over the minimum time period (7 days)
 *
 * Usage (direct value - may fail with very large numbers):
 *   forge script src/scripts/ops/CalculateCoolerLtvUpdate.s.sol:UpdateCoolerLtv \
 *     --rpc-url sepolia \
 *     --account <your-wallet> \
 *     --broadcast \
 *     --sig "updateOltv(uint96)" 872636398584498440592620626480000000000
 *
 * Usage (via environment variable - recommended for large numbers):
 *   TARGET_OLTV=872636398584498440592620626480000000000 \
 *   forge script src/scripts/ops/CalculateCoolerLtvUpdate.s.sol:UpdateCoolerLtv \
 *     --rpc-url sepolia \
 *     --account <your-wallet> \
 *     --broadcast \
 *     --sig "updateOltvFromEnv()"
 */
contract UpdateCoolerLtv is WithEnvironment {
    /// @notice Update the OLTV to the target value, adjusting limits as needed
    /// @param targetOltv The target Origination LTV (18 decimals)
    /// Can also be called with updateOltvFromEnv() to read from TARGET_OLTV env var
    function updateOltv(uint96 targetOltv) public {
        _loadEnv("sepolia");

        address oracleAddress = _envAddress("olympus.policies.CoolerV2LtvOracle");
        require(oracleAddress != address(0), "CoolerV2LtvOracle not found in env.json");

        ICoolerLtvOracle oracle = ICoolerLtvOracle(oracleAddress);

        console2.log("\n=== Updating CoolerV2 LTV Oracle ===\n");
        console2.log("Oracle Address:", oracleAddress);

        // Query current state
        uint96 currentOltv = oracle.currentOriginationLtv();
        uint96 maxDelta = oracle.maxOriginationLtvDelta();
        uint32 minTimeDelta = oracle.minOriginationLtvTargetTimeDelta();
        uint96 maxRateOfChange = oracle.maxOriginationLtvRateOfChange();

        console2.log("\n--- Current State ---");
        console2.log("Current OLTV:");
        console2.log(currentOltv);
        console2.log("Max OLTV Delta:");
        console2.log(maxDelta);
        console2.log("Min Target Time Delta:");
        console2.log(minTimeDelta);
        console2.log("seconds (");
        console2.log(minTimeDelta / 86400);
        console2.log("days)");
        console2.log("Max Rate of Change:");
        console2.log(maxRateOfChange);
        console2.log("OLTV/second");

        // Validate target
        console2.log("\n--- Target Update ---");
        console2.log("Target OLTV:");
        console2.log(targetOltv);

        if (targetOltv < currentOltv) {
            revert("Target OLTV is less than current OLTV (cannot decrease)");
        }

        uint96 delta = targetOltv - currentOltv;
        console2.log("Required Delta:");
        console2.log(delta);

        // Calculate required rate of change for minimum time
        uint96 requiredRateForMinTime = delta / minTimeDelta;
        console2.log("Required rate of change:");
        console2.log(requiredRateForMinTime);
        console2.log("OLTV/second");

        // Check if we need to update limits
        bool needsDeltaUpdate = delta > maxDelta;
        bool needsRateUpdate = requiredRateForMinTime > maxRateOfChange;

        if (needsDeltaUpdate) {
            console2.log("\n  Delta exceeds maxOriginationLtvDelta, will update limit");
        }
        if (needsRateUpdate) {
            console2.log("  Rate exceeds maxOriginationLtvRateOfChange, will update limit");
        }

        // Start broadcasting transactions
        vm.startBroadcast();

        // Update max delta if needed
        if (needsDeltaUpdate) {
            console2.log("\n--- Updating maxOriginationLtvDelta ---");
            console2.log("Setting to:");
            console2.log(delta);
            oracle.setMaxOriginationLtvDelta(delta);
            console2.log("Updated");
        }

        // Update max rate of change if needed
        if (needsRateUpdate) {
            console2.log("\n--- Updating maxOriginationLtvRateOfChange ---");
            console2.log("Setting delta:");
            console2.log(delta);
            console2.log("Setting time delta:");
            console2.log(minTimeDelta);
            console2.log("This will set max rate to:");
            console2.log(requiredRateForMinTime);
            console2.log("OLTV/second");
            oracle.setMaxOriginationLtvRateOfChange(delta, minTimeDelta);
            console2.log("Updated");
        }

        // Set the target OLTV
        console2.log("\n--- Setting Target OLTV ---");
        uint40 targetTime = uint40(block.timestamp + minTimeDelta);
        console2.log("Target value:");
        console2.log(targetOltv);
        console2.log("Target time:");
        console2.log(targetTime);
        console2.log("(timestamp)");
        console2.log("Time from now:");
        console2.log(minTimeDelta);
        console2.log("seconds (");
        console2.log(minTimeDelta / 86400);
        console2.log("days)");
        console2.log("Rate of change:");
        console2.log(requiredRateForMinTime);
        console2.log("OLTV/second");

        oracle.setOriginationLtvAt(targetOltv, targetTime);
        console2.log("Target OLTV set");

        vm.stopBroadcast();

        // Verify the update
        console2.log("\n--- Verification ---");
        uint96 newCurrentOltv = oracle.currentOriginationLtv();
        console2.log("Current OLTV after update:");
        console2.log(newCurrentOltv);
        console2.log("(Note: This will gradually increase to");
        console2.log(targetOltv);
        console2.log("over");
        console2.log(minTimeDelta / 86400);
        console2.log("days)");

        console2.log("\nUpdate complete!");
    }

    /// @notice Update the OLTV reading the target value from TARGET_OLTV environment variable
    /// This is useful when the number is too large for shell parsing
    /// Usage: TARGET_OLTV=872636398584498440592620626480000000000 forge script ... --sig "updateOltvFromEnv()"
    function updateOltvFromEnv() public {
        uint96 targetOltv = uint96(vm.envUint("TARGET_OLTV"));
        updateOltv(targetOltv);
    }
}
