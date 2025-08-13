// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";

import {console2} from "forge-std/console2.sol";

contract ConvertibleDepositAuctioneerDisableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodDisabled(address indexed depositAsset, uint8 depositPeriod);

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    // given the deposit period is not enabled
    //  [X] it reverts

    function test_givenDepositPeriodNotEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectDepositAssetAndPeriodNotEnabledRevert(iReserveToken, PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    // given there are no other deposit periods for the deposit asset
    //  [X] it removes the deposit period from the deposit asset's periods array
    //  [X] it removes the deposit asset from the deposit assets array
    //  [X] it disables the deposit asset and period
    //  [X] the tick is removed
    //  [X] an event is emitted

    function test_givenNoOtherDepositPeriods()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            false,
            "deposit period disabled"
        );
        assertEq(auctioneer.getDepositPeriods().length, 0, "deposit periods length");
        assertEq(auctioneer.getDepositPeriodsCount(), 0, "deposit periods count");

        // Check the tick is removed
        _assertPreviousTick(0, 0, TICK_SIZE, 0);
    }

    // [X] it removes the deposit period from the deposit periods array
    // [X] it disables the deposit period
    // [X] the tick is removed
    // [X] an event is emitted

    function test_givenOtherDepositPeriods()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS + 1)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS + 1, 0);

        // Check the tick is removed
        _assertPreviousTick(0, 0, TICK_SIZE, 0);
    }

    /// @notice Test that remaining deposit periods maintain correct capacity allocation when a period is disabled
    /// @dev This test demonstrates a bug where disabling a deposit period causes remaining periods
    ///      to gain extra capacity because _getCurrentTick recalculates using the NEW (smaller) period count
    ///      instead of preserving capacity accumulated with the original period count.
    ///
    ///      Expected behavior: Capacity accumulated during a time period should be based on the
    ///      period count that was active during that time, not the current period count.
    function test_capacityAllocationWhenDisablingDepositPeriod()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(12)
        givenDepositPeriodEnabled(18)
    {
        uint8 periodA = PERIOD_MONTHS;
        uint8 periodB = 12;
        uint8 periodC = 18;
        // Enable the other periods with the DepositManager
        {
            vm.startPrank(admin);
            depositManager.addAssetPeriod(iReserveToken, periodB, 90e2);
            depositManager.addAssetPeriod(iReserveToken, periodC, 90e2);
            vm.stopPrank();
        }

        // Step 1: Verify all 3 periods are enabled
        assertEq(auctioneer.getDepositPeriodsCount(), 3, "3 periods enabled");

        // Step 1.5: Make bids to reduce capacity so we can see the difference more clearly
        _mintReserveToken(recipient, 10000e18);
        _approveReserveTokenSpending(recipient, address(depositManager), 10000e18);

        // Make bids on periods A and B to consume most of their capacity
        vm.prank(recipient);
        auctioneer.bid(periodA, 3000e18, 1, false, false);
        vm.prank(recipient);
        auctioneer.bid(periodB, 3000e18, 1, false, false);

        console2.log("periodA capacity", auctioneer.getCurrentTick(periodA).capacity);
        console2.log("periodB capacity", auctioneer.getCurrentTick(periodB).capacity);
        console2.log("tick size", auctioneer.getCurrentTickSize());

        // Step 2: Let time pass with 3 periods active
        uint256 timePassedSeconds = 1 hours;
        vm.warp(block.timestamp + timePassedSeconds);

        // Step 3: Calculate expected values using the same method as the contract
        uint256 expectedCapacityToAdd3Periods = (TARGET * timePassedSeconds) / 1 days / 3;
        uint256 expectedCapacityToAdd2Periods = (TARGET * timePassedSeconds) / 1 days / 2;

        console2.log("=== BEFORE DISABLING PERIOD C ===");
        console2.log("Time passed (seconds):", timePassedSeconds);
        console2.log("TARGET:", TARGET);
        console2.log("Periods count:", auctioneer.getDepositPeriodsCount());
        console2.log("Expected capacity to add (3 periods):", expectedCapacityToAdd3Periods);
        console2.log("Expected capacity to add (2 periods):", expectedCapacityToAdd2Periods);
        console2.log("TICK_SIZE:", TICK_SIZE);

        // Check the previous tick state (stored state) before getCurrentTick
        IConvertibleDepositAuctioneer.Tick memory storedTickA = auctioneer.getPreviousTick(periodA);
        console2.log("Period A stored tick before getCurrentTick:");
        console2.log("  - capacity:", storedTickA.capacity);
        console2.log("  - price:", storedTickA.price);
        console2.log("  - lastUpdate:", storedTickA.lastUpdate);
        console2.log("  - current timestamp:", block.timestamp);

        // Capture the correct tick states while 3 periods are active
        IConvertibleDepositAuctioneer.Tick memory expectedTickA = auctioneer.getCurrentTick(
            periodA
        );
        IConvertibleDepositAuctioneer.Tick memory expectedTickB = auctioneer.getCurrentTick(
            periodB
        );

        console2.log("Period A calculated capacity (3 periods):", expectedTickA.capacity);
        console2.log("Period A calculated price (3 periods):", expectedTickA.price);
        console2.log("Period B calculated capacity (3 periods):", expectedTickB.capacity);
        console2.log("Period B calculated price (3 periods):", expectedTickB.price);

        // Manual calculation to verify
        uint256 manualNewCapacity = storedTickA.capacity + expectedCapacityToAdd3Periods;
        console2.log("Manual calculation: stored + expected =", manualNewCapacity);

        // Step 4: Disable period C, changing the total to 2 periods
        vm.prank(admin);
        auctioneer.disableDepositPeriod(periodC);

        console2.log("\n=== AFTER DISABLING PERIOD C ===");
        console2.log("Periods count:", auctioneer.getDepositPeriodsCount());

        // Step 5: Check if periods A and B maintain their correct capacity
        // BUG: getCurrentTick will now recalculate using 2 periods instead of 3,
        // giving periods A and B more capacity: (TARGET * 9 hours / 1 day) / 2 periods
        IConvertibleDepositAuctioneer.Tick memory actualTickA = auctioneer.getCurrentTick(periodA);
        IConvertibleDepositAuctioneer.Tick memory actualTickB = auctioneer.getCurrentTick(periodB);

        console2.log("Period A capacity (2 periods):", actualTickA.capacity);
        console2.log("Period A price (2 periods):", actualTickA.price);
        console2.log("Period B capacity (2 periods):", actualTickB.capacity);
        console2.log("Period B price (2 periods):", actualTickB.price);

        console2.log("\n=== DIFFERENCES ===");
        console2.log(
            "Period A capacity difference:",
            int256(actualTickA.capacity) - int256(expectedTickA.capacity)
        );
        console2.log(
            "Period B capacity difference:",
            int256(actualTickB.capacity) - int256(expectedTickB.capacity)
        );

        // The bug should cause these to be different
        if (actualTickA.capacity != expectedTickA.capacity) {
            console2.log("BUG DETECTED: Period A capacity changed after disabling period C");
        }

        // These assertions should fail if the bug exists
        // Account for potential rounding differences of ±1 due to mulDivUp operations
        assertApproxEqAbs(
            actualTickA.capacity,
            expectedTickA.capacity,
            1,
            "Period A should maintain correct capacity after disabling period C"
        );
        assertEq(
            actualTickA.price,
            expectedTickA.price,
            "Period A should maintain correct price after disabling period C"
        );
        assertApproxEqAbs(
            actualTickB.capacity,
            expectedTickB.capacity,
            1,
            "Period B should maintain correct capacity after disabling period C"
        );
        assertEq(
            actualTickB.price,
            expectedTickB.price,
            "Period B should maintain correct price after disabling period C"
        );
    }
}
