// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {console2} from "@forge-std-1.9.6/console2.sol";

import {IOlympusTokenMigrator} from "src/interfaces/IOlympusTokenMigrator.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @notice Script to determine the maximum amount of OHMv1 that can be migrated
/// @dev    Uses binary search to find max migratable amount efficiently
///         Uses fork state only - no broadcast transactions
///         snapshot/revert are local operations - no excessive RPC calls
contract MaxMigratableOHMScript is Test {
    // Mainnet addresses
    address internal constant MIGRATOR = 0x184f3FAd8618a6F458C16bae63F70C426fE784B3;
    address internal constant GOHM = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
    address internal constant OHMV1 = 0x383518188C0C6d7730D91b2c03a03C837814a899;

    // Starting amount from mintTempOHM calculations (197726943548656 + 8245430417)
    uint256 internal constant STARTING_AMOUNT = 197735188979073;

    // Lower bound: minimum amount to test before giving up
    uint256 internal constant LOWER_BOUND = 1000e9; // 1000 OHM

    function test_calculateMaxMigratableOHM() external {
        // Create fork - this is the only RPC call
        vm.createSelectFork("mainnet");

        // Get current state from fork
        uint256 oldSupply = IOlympusTokenMigrator(MIGRATOR).oldSupply();
        uint256 totalSupply = IERC20(OHMV1).totalSupply();
        uint256 gOHMBalance = IERC20(GOHM).balanceOf(MIGRATOR);

        console2.log("=== Current State ===");
        console2.log("OHMv1 oldSupply (9 dp):", oldSupply);
        console2.log("OHMv1 totalSupply (9 dp):", totalSupply);
        console2.log("Migrator gOHM balance (18 dp):", gOHMBalance);

        console2.log("\n=== Starting Binary Search ===");
        console2.log("Starting amount (9 dp):", STARTING_AMOUNT);
        console2.log("Lower bound (9 dp):", LOWER_BOUND);

        // Check if starting amount succeeds (would mean higher max exists)
        if (_tryMigration(STARTING_AMOUNT)) {
            console2.log("\n=== WARNING ===");
            console2.log("Starting amount succeeded!");
            console2.log("The maximum migratable amount may be higher than STARTING_AMOUNT.");
            console2.log("Consider increasing STARTING_AMOUNT and running again.");
            console2.log("\nResult with current STARTING_AMOUNT:");
            console2.log("Max migratable OHMv1 (9 dp):", STARTING_AMOUNT);
            console2.log("Corresponding tempOHM (18 dp):", STARTING_AMOUNT * 1e9);
            console2.log("\n=== For args file ===");
            console2.log(
                string.concat(
                    '{"functions": [{"name": "setOHMv1ToMigrate", "args": {"OHMv1ToMigrate": "',
                    vm.toString(STARTING_AMOUNT),
                    '"}}]}'
                )
            );
            return;
        }

        // Check if LOWER_BOUND fails
        // It is returned as the max if no match is found in between,
        // so we need to check if it works.
        if (!_tryMigration(LOWER_BOUND)) {
            console2.log("\n=== WARNING ===");
            console2.log("LOWER_BOUND failed!");
            console2.log("The maximum migratable amount may be lower than LOWER_BOUND.");
            console2.log("Consider decreasing LOWER_BOUND and running again.");
            console2.log("\nResult with current LOWER_BOUND:");
            console2.log("Max migratable OHMv1 (9 dp):", LOWER_BOUND);
            console2.log("Corresponding tempOHM (18 dp):", LOWER_BOUND * 1e9);
            return;
        }

        // Binary search between LOWER_BOUND and STARTING_AMOUNT
        uint256 low = LOWER_BOUND;
        uint256 high = STARTING_AMOUNT - 1;
        uint256 iterationCount = 0;

        while (low < high) {
            iterationCount++;
            uint256 mid = (low + high + 1) / 2;

            if (iterationCount % 10 == 0) {
                console2.log("Iteration ", iterationCount);
                console2.log("  low (OHM): ", low);
                console2.log("  mid (OHM): ", mid);
                console2.log("  high (OHM): ", high);
            }

            if (_tryMigration(mid)) {
                // Migration succeeded, try higher
                low = mid;
            } else {
                // Migration failed, try lower
                high = mid - 1;
            }
        }

        // low == high == max migratable amount
        console2.log("\n=== SUCCESS ===");
        console2.log("Total iterations:", iterationCount);
        console2.log("Max migratable OHMv1 (9 dp):", low);
        console2.log("Amount decreased from starting:", STARTING_AMOUNT - low, "wei");
        console2.log("Corresponding tempOHM (18 dp):", low * 1e9);

        // Output in format suitable for args file
        console2.log("\n=== For args file ===");
        console2.log(
            string.concat(
                '{"functions": [{"name": "setOHMv1ToMigrate", "args": {"OHMv1ToMigrate": "',
                vm.toString(low),
                '"}}]}'
            )
        );
    }

    /// @notice Try to migrate a specific amount
    /// @dev    Uses snapshot/revert to preserve state
    /// @return success True if migration succeeded
    function _tryMigration(uint256 amount) internal returns (bool success) {
        uint256 snapshotId = vm.snapshotState();

        // Deal OHMv1 to this address for testing
        deal(OHMV1, address(this), amount);

        // Approve the migrator
        ERC20(OHMV1).approve(MIGRATOR, amount);

        // Try migration
        try
            IOlympusTokenMigrator(MIGRATOR).migrate(
                amount,
                IOlympusTokenMigrator.TYPE.UNSTAKED,
                IOlympusTokenMigrator.TYPE.WRAPPED
            )
        {
            success = true;
        } catch {
            success = false;
        }

        // Revert to clean state
        vm.revertToStateAndDelete(snapshotId);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
