// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {console2} from "forge-std/console2.sol";

contract ConvertibleDepositAuctioneerEnableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodEnabled(address indexed depositAsset, uint8 depositPeriod);

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);
    }

    // given the contract is not enabled
    //  [X] it succeeds

    function test_givenContractNotEnabled() public {
        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS, 0);

        // Check the tick is populated
        _assertPreviousTick(0, 0, 0, uint48(block.timestamp));
    }

    // when the deposit period is zero
    //  [X] it reverts

    function test_whenDepositPeriodIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.ConvertibleDepositAuctioneer_InvalidParams.selector,
                "deposit period"
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(0);
    }

    // given the deposit period is already enabled
    //  [X] it reverts

    function test_givenDepositPeriodAlreadyEnabled_reverts()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer
                    .ConvertibleDepositAuctioneer_DepositPeriodAlreadyEnabled
                    .selector,
                address(iReserveToken),
                PERIOD_MONTHS
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);
    }

    // given the deposit period was previously enabled
    //  [X] the tick for the deposit period is initialized

    function test_givenDepositPeriodPreviouslyEnabled()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodDisabled(PERIOD_MONTHS)
    {
        // Warp forward, so we know the timestamp will be different
        vm.warp(block.timestamp + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS, 0);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // given there is another deposit period enabled
    //  [X] the deposit period is added to the deposit periods array
    //  [X] the deposit period is enabled
    //  [X] the tick for the deposit period is initialized
    //  [X] an event is emitted

    function test_givenOtherDepositPeriodEnabled()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS + 1);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS + 1);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS + 1, 1);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // [X] the deposit period is added to the deposit periods array
    // [X] the deposit period is enabled
    // [X] the tick for the deposit period is initialized
    // [X] an event is emitted

    function test_success() public givenEnabled {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(PERIOD_MONTHS);

        // Assert state
        _assertPeriodEnabled(PERIOD_MONTHS, 0);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    /// @notice Test that existing deposit periods maintain correct capacity allocation when a new period is enabled
    /// @dev This test demonstrates a bug where enabling a new deposit period causes existing periods
    ///      to lose capacity because _getCurrentTick recalculates using the NEW period count instead
    ///      of preserving capacity accumulated with the original period count.
    ///
    ///      Expected behavior: Capacity accumulated during a time period should be based on the
    ///      period count that was active during that time, not the current period count.
    function test_capacityAllocationWhenEnablingDepositPeriod() public givenEnabled {
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

        // Step 1: Enable periods A and B (2 periods total)
        vm.prank(admin);
        auctioneer.enableDepositPeriod(periodA);
        vm.prank(admin);
        auctioneer.enableDepositPeriod(periodB);

        assertEq(auctioneer.getDepositPeriodsCount(), 2, "2 periods enabled");

        // Step 1.5: Make bids to reduce capacity so we can see the difference more clearly
        _mintReserveToken(recipient, 10000e18);
        _approveReserveTokenSpending(recipient, address(depositManager), 10000e18);

        // Make a large bid on period A to consume most of its capacity
        vm.prank(recipient);
        auctioneer.bid(periodA, 5000e18, 1, false, false);

        // Also make a bid on period B
        vm.prank(recipient);
        auctioneer.bid(periodB, 5000e18, 1, false, false);

        // Step 2: Let time pass with 2 periods active - use shorter time to avoid tick size capping
        uint256 timePassedSeconds = 6 hours;
        vm.warp(block.timestamp + timePassedSeconds);

        // Step 3: Calculate expected values using the same method as the contract
        uint256 expectedCapacityToAdd2Periods = (TARGET * timePassedSeconds) / 1 days / 2;
        uint256 expectedCapacityToAdd3Periods = (TARGET * timePassedSeconds) / 1 days / 3;

        console2.log("=== BEFORE ENABLING PERIOD C ===");
        console2.log("Time passed (seconds):", timePassedSeconds);
        console2.log("TARGET:", TARGET);
        console2.log("Periods count:", auctioneer.getDepositPeriodsCount());
        console2.log("Expected capacity to add (2 periods):", expectedCapacityToAdd2Periods);
        console2.log("Expected capacity to add (3 periods):", expectedCapacityToAdd3Periods);
        console2.log("TICK_SIZE:", TICK_SIZE);

        // Check the previous tick state (stored state) before getCurrentTick
        IConvertibleDepositAuctioneer.Tick memory storedTickA = auctioneer.getPreviousTick(periodA);
        console2.log("Period A stored tick before getCurrentTick:");
        console2.log("  - capacity:", storedTickA.capacity);
        console2.log("  - price:", storedTickA.price);
        console2.log("  - lastUpdate:", storedTickA.lastUpdate);
        console2.log("  - current timestamp:", block.timestamp);

        // Capture tick states while 2 periods are active
        IConvertibleDepositAuctioneer.Tick memory expectedTickA = auctioneer.getCurrentTick(
            periodA
        );
        IConvertibleDepositAuctioneer.Tick memory expectedTickB = auctioneer.getCurrentTick(
            periodB
        );

        console2.log("Period A calculated capacity (2 periods):", expectedTickA.capacity);
        console2.log("Period A calculated price (2 periods):", expectedTickA.price);
        console2.log("Period B calculated capacity (2 periods):", expectedTickB.capacity);
        console2.log("Period B calculated price (2 periods):", expectedTickB.price);

        // Manual calculation to verify
        uint256 manualNewCapacity = storedTickA.capacity + expectedCapacityToAdd2Periods;
        console2.log("Manual calculation: stored + expected =", manualNewCapacity);

        // Step 4: Enable period C, changing the total to 3 periods
        vm.prank(admin);
        auctioneer.enableDepositPeriod(periodC);

        console2.log("\n=== AFTER ENABLING PERIOD C ===");
        console2.log("Periods count:", auctioneer.getDepositPeriodsCount());

        // Step 5: Check tick states after enabling period C
        IConvertibleDepositAuctioneer.Tick memory actualTickA = auctioneer.getCurrentTick(periodA);
        IConvertibleDepositAuctioneer.Tick memory actualTickB = auctioneer.getCurrentTick(periodB);

        console2.log("Period A capacity (3 periods):", actualTickA.capacity);
        console2.log("Period A price (3 periods):", actualTickA.price);
        console2.log("Period B capacity (3 periods):", actualTickB.capacity);
        console2.log("Period B price (3 periods):", actualTickB.price);

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
            console2.log("BUG DETECTED: Period A capacity changed after enabling period C");
        }

        // These assertions should fail if the bug exists
        // Account for potential rounding differences of ±1 due to mulDivUp operations
        assertApproxEqAbs(
            actualTickA.capacity,
            expectedTickA.capacity,
            1,
            "Period A should maintain correct capacity after enabling period C"
        );
        assertEq(
            actualTickA.price,
            expectedTickA.price,
            "Period A should maintain correct price after enabling period C"
        );
        assertApproxEqAbs(
            actualTickB.capacity,
            expectedTickB.capacity,
            1,
            "Period B should maintain correct capacity after enabling period C"
        );
        assertEq(
            actualTickB.price,
            expectedTickB.price,
            "Period B should maintain correct price after enabling period C"
        );
    }
}
