// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {ConvertibleDepositAuctioneer} from "src/policies/deposits/ConvertibleDepositAuctioneer.sol";

import {console2} from "forge-std/console2.sol";

contract ConvertibleDepositAuctioneerDisableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodDisableQueued(address indexed depositAsset, uint8 depositPeriod);

    // given the contract is not enabled
    //  [X] it queues the disable (now allowed while disabled)

    function test_givenContractNotEnabled_queuesDisable()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenDisabled
    {
        // Now try to disable the period while contract is disabled
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Verify it was queued
        (bool isEnabled, bool isPendingEnabled) = auctioneer.getDepositPeriodState(PERIOD_MONTHS);
        assertEq(isEnabled, true, "period should still be enabled");
        assertEq(isPendingEnabled, false, "period should be pending disabled");
    }

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public givenEnabled {
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
        _expectDepositPeriodInvalidState(iReserveToken, PERIOD_MONTHS, false);

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
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Expect queued event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state - period should still be enabled (only queued for disable)
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            true,
            "deposit period should still be enabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 1, "deposit periods count should still be 1");

        // Check pending changes
        (bool isEnabled, bool isPendingEnabled) = auctioneer.getDepositPeriodState(PERIOD_MONTHS);
        assertEq(isEnabled, true, "period should still be enabled");
        assertEq(isPendingEnabled, false, "period should be pending disabled");
    }

    // [X] it removes the deposit period from the deposit periods array
    // [X] it disables the deposit period
    // [X] the tick is removed
    // [X] an event is emitted

    function test_givenOtherDepositPeriods()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS + 1)
        givenEnabled
    {
        // Expect queued event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodDisableQueued(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Assert state - both periods should still be enabled
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS),
            true,
            "first period should still be enabled"
        );
        assertEq(
            auctioneer.isDepositPeriodEnabled(PERIOD_MONTHS + 1),
            true,
            "second period should still be enabled"
        );
        assertEq(auctioneer.getDepositPeriodsCount(), 2, "count should still be 2");

        // Check pending changes
        (bool isEnabled, bool isPendingEnabled) = auctioneer.getDepositPeriodState(PERIOD_MONTHS);
        assertEq(isEnabled, true, "period should still be enabled");
        assertEq(isPendingEnabled, false, "period should be pending disabled");
    }

    /// @notice Test that queueing disable after disable for same period reverts
    function test_disableAfterDisable_reverts()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Queue first disable
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Expect revert when trying to disable again
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_DepositPeriodInvalidState
                    .selector,
                address(iReserveToken),
                PERIOD_MONTHS,
                false // effective state would be disabled
            )
        );

        // Call function again
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    /// @notice Test trying to disable a period that is not currently enabled reverts
    function test_disableNotEnabledPeriod_reverts() public givenEnabled {
        // Expect revert when trying to disable a period that was never enabled
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_DepositPeriodInvalidState
                    .selector,
                address(iReserveToken),
                PERIOD_MONTHS,
                false // effective state is disabled (never enabled)
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);
    }

    /// @notice Test disable -> enable -> disable sequence works correctly
    function test_disableEnableDisableSequence()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Queue disable
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Queue enable (should work since effective state becomes disabled then enabled)
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Queue disable again (should work since effective state is now enabled)
        vm.prank(admin);
        auctioneer.disableDepositPeriod(PERIOD_MONTHS);

        // Check final pending state - after disable -> enable -> disable sequence
        (bool finalIsEnabled, bool finalIsPendingEnabled) = auctioneer.getDepositPeriodState(
            PERIOD_MONTHS
        );
        assertEq(finalIsEnabled, true, "period should still be enabled");
        assertEq(finalIsPendingEnabled, false, "period should end up pending disabled");
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
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenDepositPeriodEnabled(18)
    {
        uint8 periodA = PERIOD_MONTHS;
        uint8 periodB = PERIOD_MONTHS_TWO;
        uint8 periodC = 18;
        // Enable the other periods with the DepositManager
        {
            vm.startPrank(admin);
            depositManager.addAssetPeriod(iReserveToken, periodC, address(facility), 90e2);
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
