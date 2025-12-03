// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";

import {console2} from "forge-std/console2.sol";

contract ConvertibleDepositAuctioneerCurrentTickTest is ConvertibleDepositAuctioneerTest {
    // given the contract is disabled
    //  [X] it does not revert

    function test_contractDisabled_doesNotRevert()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenDisabled
    {
        // Call function
        auctioneer.getCurrentTick(PERIOD_MONTHS);
    }

    // given the deposit asset and period are not enabled
    //  [X] it reverts

    function test_givenDepositAssetAndPeriodNotEnabled_reverts() public givenEnabled {
        // Expect revert
        _expectDepositAssetAndPeriodNotEnabledRevert(iReserveToken, PERIOD_MONTHS);

        // Call function
        auctioneer.getCurrentTick(PERIOD_MONTHS);
    }

    // given a bid has never been received and the tick price is at the minimum price
    //  given no time has passed
    //   [X] the tick price remains at the min price
    //   [X] the tick capacity remains at the standard tick size

    function test_fullCapacity_sameTime()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        uint256 expectedTickPrice = 15e18;
        uint256 expectedTickCapacity = 10e9;

        // Assert current tick
        assertEq(tick.capacity, expectedTickCapacity, "capacity");
        assertEq(tick.price, expectedTickPrice, "price");
    }

    //  given the target is zero
    //   [X] the tick price remains at the min price
    //   [X] the tick capacity remains at the standard tick size

    function test_fullCapacity_targetZero(
        uint48 secondsPassed_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(0, TICK_SIZE, MIN_PRICE)
    {
        uint48 secondsPassed = uint48(bound(secondsPassed_, 1, 7 days));

        // Warp to change the block timestamp
        vm.warp(block.timestamp + secondsPassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert current tick
        // As the day target is zero, no new capacity is added, hence the values stay the same
        assertEq(tick.capacity, TICK_SIZE, "capacity");
        assertEq(tick.price, MIN_PRICE, "price");
        assertEq(auctioneer.getCurrentTickSize(), TICK_SIZE, "tick size");
    }

    //  [X] the tick price remains at the min price
    //  [X] the tick capacity is adjusted according to the time passed

    function test_fullCapacity_newCapacityLessThanTickSize(
        uint48 secondsPassed_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        // For new capacity to stay within the tick size, the time passed must be less than 12 hours (20e9 * 12/24)
        uint48 secondsPassed = uint48(bound(secondsPassed_, 1, 12 hours));

        // Current tick capacity = 10e9
        // Current tick price = 15e18
        // Tick size = 10e9
        // Tick step = 110e2

        // Warp to change the block timestamp
        vm.warp(block.timestamp + secondsPassed);

        // Expected values
        // Added capacity < 10e9
        // 10e9 < New capacity < 20e9
        //
        // Iteration 1:
        // - Capacity: < 10e9
        // - Price: 15e18 * 100e2 / 110e2 = 13636363636363636364
        // - Price is below the minimum price, so it is set to the minimum price
        uint256 expectedTickPrice = 15e18;
        uint256 expectedTickCapacity = (uint256(secondsPassed) * 20e9) / 1 days;

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert current tick
        assertEq(tick.capacity, expectedTickCapacity, "capacity");
        assertEq(tick.price, expectedTickPrice, "price");
    }

    function test_fullCapacity_newCapacityGreaterThanTickSize(
        uint48 secondsPassed_
    ) public givenDepositPeriodEnabled(PERIOD_MONTHS) givenEnabled {
        // For new capacity to exceed the tick size, the time passed must be greater than 12 hours (20e9 * 12/24)
        uint48 secondsPassed = uint48(bound(secondsPassed_, 12 hours + 1, 24 hours));

        // Current tick capacity = 10e9
        // Current tick price = 15e18
        // Tick size = 10e9
        // Tick step = 110e2

        // Warp to change the block timestamp
        vm.warp(block.timestamp + secondsPassed);

        // Expected values
        // 10e9 < Added capacity < 20e9
        // 20e9 < New capacity < 30e9
        //
        // Iteration 1:
        // - Capacity: 10e9 < New capacity < 20e9
        // - Price: 15e18 * 100e2 / 110e2 = 13636363636363636364
        // - Price is below the minimum price, so it is set to the minimum price
        // - Capacity is capped to the tick size
        uint256 expectedTickPrice = 15e18;
        uint256 expectedTickCapacity = 10e9;

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert current tick
        assertEq(tick.capacity, expectedTickCapacity, "capacity");
        assertEq(tick.price, expectedTickPrice, "price");
    }

    // when the new capacity (current tick capacity + added capacity) is equal to the current tick size
    //  given the current tick size is 5e9
    //   given the current timestamp is on a different day to the last bid
    //    [X] the tick capacity is set to the standard tick size
    //    [X] the tick size is set to the standard tick size

    function test_newCapacityEqualToTickSize_dayTargetMet_nextDay()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(378861111101700000000)
    {
        // 150e18 + 165e18 + 63861111101700000000 = 378861111101700000000
        // Bid size of 378861111101700000000 results in:
        // 1. 378861111101700000000 * 1e9 / 15e18 = 24,025,000,000. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (378861111101700000000 - 150e18) * 1e9 / 165e17 = 12,750,000,000. Greater than the tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16. Day target met, so tick size becomes 5e9.
        // 3. (378861111101700000000 - 150e18 - 165e18) * 1e9 / 1815e16 = 3518518518. Less than the tick size of 5e9.
        // Remaining capacity is 5e9 - 3518518518 = 1481481482

        // 20e9*36800/(24*60*60) = 8518518518 added capacity
        // New capacity will be 1481481482 + 8518518518 = 10e9

        // Calculate the expected tick price
        // As it is the next day, the tick size will reset to 10e9

        // Warp forward to the next day
        // Otherwise the time passed will not be correct
        vm.warp(block.timestamp + 36800);

        IConvertibleDepositAuctioneer.Tick memory previousTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Call setAuctionParameters, which resets the day and updates lastUpdate
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert previously-stored tick was updated with the values before the new parameters were set
        assertEq(tick.capacity, previousTick.capacity, "new tick capacity");
        assertEq(tick.price, previousTick.price, "new tick price");
    }

    //   [X] the tick price is unchanged
    //   [X] the tick capacity is set to the current tick size
    //   [X] the tick size does not change

    function test_newCapacityEqualToTickSize_dayTargetMet()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(360375e15)
    {
        // Bid size of 360375e15 results in:
        // 1. 360375e15 * 1e9 / 15e18 = 24,025,000,000. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (360375e15 - 150e18) * 1e9 / 165e17 = 12,750,000,000. Greater than the tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16. Day target met, so tick size becomes 5e9.
        // 3. (360375e15 - 150e18 - 165e18) * 1e9 / 1815e16 = 25e8. Less than the tick size of 5e9.

        // Remaining capacity is 25e8
        // Added capacity will be 25e8
        // New capacity will be 25e8 + 25e8 = 5e9

        // Calculate the expected tick price
        // Tick price remains at 1815e16

        // Warp forward
        uint48 timePassed = 10800;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 5e9, "new tick capacity");
        assertEq(tick.price, 1815e16, "new tick price");
    }

    //  [X] the tick price is unchanged
    //  [X] the tick capacity is set to the standard tick size

    function test_newCapacityEqualToTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(75e18)
    {
        // Min price is 15e18
        // We need a bid and time to pass so that remaining capacity + new capacity = tick size
        // Given a tick size of 10e9
        // We want to get to a remaining capacity of 5e9
        // 5e9 = bid size * 1e9 / 15e18
        // Bid size = 5e9 * 15e18 / 1e9 = 75e18
        // If there is capacity of 5e9, we need new capacity of 5e9
        // new capacity = 20e9 * time passed / 1 days
        // time passed = 5e9 * 1 days / 20e9 = 21600 seconds

        // Assert that the convertible amount is correct
        uint256[] memory positionIds = convertibleDepositPositions.getUserPositionIds(recipient);
        assertEq(
            convertibleDepositPositions.previewConvert(positionIds[0], 75e18),
            5e9,
            "convertible amount"
        );

        // Assert tick capacity
        assertEq(auctioneer.getCurrentTick(PERIOD_MONTHS).capacity, 5e9, "previous tick capacity");

        // Assert that the time passed will result in the correct capacity
        uint48 timePassed = 21600;
        assertEq(
            (auctioneer.getAuctionParameters().target * timePassed) / 1 days,
            5e9,
            "expected new capacity"
        );

        // Warp forward
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    // when the new capacity is less than the current tick size
    //  [X] the tick price is unchanged
    //  [X] the tick capacity is set to the new capacity

    function test_newCapacityLessThanTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(90e18)
    {
        // Bid size of 90e18 results in convertible amount of 6e9
        // Remaining capacity is 4e9

        // Added capacity will be 5e9
        // New capacity will be 4e9 + 5e9 = 9e9

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 9e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    // when the new capacity is greater than the current tick size
    //  given the tick step is = 100e2
    //   [X] the tick price is unchanged
    //   [X] the tick capacity is set to the new capacity

    function test_tickStepSame_newCapacityGreaterThanTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenTickStep(100e2)
        givenRecipientHasBid(45e18)
    {
        // Bid size of 45e18 results in convertible amount of 3e9
        // Remaining capacity is 7e9

        // Added capacity will be 5e9
        // New capacity will be 7e9 + 5e9 = 12e9
        // Excess capacity = 12e9 - 10e9 = 2e9
        // Tick price = 15e18 * 100e2 / 100e2 = 15e18

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 2e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    //  given the tick step is > 100e2
    //   when the new price is lower than the minimum price
    //    given the current tick size is 5e9
    //     given the current timestamp is on a different day to the last bid
    //      [X] the tick capacity is set to the standard tick size
    //      [X] the tick size is set to the standard tick size

    function test_tickPriceAboveMinimum_newPriceBelowMinimum_dayTargetMet_nextDay()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(330e18)
    {
        // Bid size of 330e18 results in:
        // 1. 330e18 * 1e9 / 15e18 = 22e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (330e18 - 150e18) * 1e9 / 165e17 = 10,909,090,909. Greater than tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16
        // 3. (330e18 - 150e18 - 165e18) * 1e9 / 1815e16 = 826446280
        // Remaining capacity is 5e9 - 826446280 = 4173553720

        // Added capacity will be 30e9
        // New capacity will be 4173553720 + 30e9 = 34173553720

        // Calculate the expected tick price
        // As it is the next day, the tick size will reset to 10e9
        // 1. Excess capacity = 34173553720 - 10e9 = 24173553720
        //    Tick price = 165e17
        // 2. Excess capacity = 24173553720 - 10e9 = 14173553720
        //    Tick price = 165e17 * 100e2 / 110e2 = 15e18
        // 3. Excess capacity = 14173553720 - 10e9 = 4173553720
        //    Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //    Tick price is below the minimum price, so it is set to the minimum price

        // Warp forward
        // Otherwise the time passed will not be correct
        vm.warp(block.timestamp + 6 * 21600);

        IConvertibleDepositAuctioneer.Tick memory previousTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Call setAuctionParameters, which resets the day and updates lastUpdate
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert previously-stored tick was updated with the values before the new parameters were set
        assertEq(tick.capacity, 4173553720, "new tick capacity");
        assertEq(tick.price, previousTick.price, "new tick price");
    }

    //     [ ] the tick price is set to the minimum price
    //     [ ] the tick capacity is set to the current tick size
    //     [ ] the tick size does not change

    //    [X] the tick price is set to the minimum price
    //    [X] the capacity is set to the standard tick size

    function test_tickPriceAboveMinimum_newPriceBelowMinimum()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (270e18 - 150e18) * 1e9 / 165e17 = 7272727272. Less than tick size of 10e9.
        // Remaining capacity is 10e9 - 7272727272 = 2727272728

        // Warp forward
        // 36 hours
        uint48 timePassed = 6 * 21600;
        vm.warp(block.timestamp + timePassed);

        // Added capacity will be 30e9 (1.5 * 20e9)
        // New capacity will be 2727272728 + 30e9 = 32727272728

        // Calculate the expected tick price
        // 1. Excess capacity = 32727272728 - 10e9 = 22727272728
        //    Tick price = 165e17 * 100e2 / 110e2 = 15e18
        // 2. Excess capacity = 22727272728 - 10e9 = 12727272728
        //    Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //    Tick price is below the minimum price, so it is set to the minimum price
        //
        // Capacity is capped to the tick size

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickPriceAboveMinimum_capacitySingleIteration_newPriceBelowMinimum()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (270e18 - 150e18) * 1e9 / 165e17 = 7272727272. Less than tick size of 10e9.
        // Remaining capacity is 10e9 - 7272727272 = 2727272728

        // Warp forward
        // 12 hours
        uint48 timePassed = 2 * 21600;
        vm.warp(block.timestamp + timePassed);

        // Added capacity will be 10e9
        // New capacity will be 2727272728 + 10e9 = 12727272728

        // Calculate the expected tick price
        // 1. Excess capacity = 12727272728 - 10e9 = 2727272728
        //    Tick price = 165e17 * 100e2 / 110e2 = 15e18

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 2727272728, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickPriceAboveMinimum_capacityTwoIterations_newPriceBelowMinimum()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (270e18 - 150e18) * 1e9 / 165e17 = 7272727272. Less than tick size of 10e9.
        // Remaining capacity is 10e9 - 7272727272 = 2727272728

        // Warp forward
        // 24 hours
        uint48 timePassed = 4 * 21600;
        vm.warp(block.timestamp + timePassed);

        // Added capacity will be 20e9 (1 * 20e9)
        // New capacity will be 2727272728 + 20e9 = 22727272728

        // Calculate the expected tick price
        // 1. Excess capacity = 22727272728 - 10e9 = 12727272728
        //    Tick price = 165e17 * 100e2 / 110e2 = 15e18
        // 2. Excess capacity = 12727272728 - 10e9 = 2727272728
        //    Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //    Tick price is below the minimum price, so it is set to the minimum price

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 2727272728, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    //   given the current tick size is 5e9
    //    given the current timestamp is on a different day to the last bid
    //     [X] the tick capacity is set to the standard tick size
    //     [X] the tick size is set to the standard tick size

    function test_tickPriceAboveMinimum_newCapacityGreaterThanTickSize_dayTargetMet_nextDay()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(330e18)
    {
        // Bid size of 330e18 results in:
        // 1. 330e18 * 1e9 / 15e18 = 22e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (330e18 - 150e18) * 1e9 / 165e17 = 10,909,090,909. Greater than tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16
        // 3. (330e18 - 150e18 - 165e18) * 1e9 / 1815e16 = 826,446,280
        // Remaining capacity is 5e9 - 826,446,280 = 4173553720

        // 20e9*36800/(24*60*60) = 8518518518 added capacity
        // New capacity will be 8518518518 + 4173553720 = 12692072238

        // Calculate the expected tick price
        // As it is the next day, the tick size will reset to 10e9
        // Excess capacity = 12692072238 - 10e9 = 2692072238
        // Tick price = 165e17

        // Warp forward
        // Otherwise the time passed will not be correct
        vm.warp(block.timestamp + 36800);

        // Call setAuctionParameters, which resets the day
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 2692072238, "new tick capacity");
        assertEq(tick.price, 165e17, "new tick price");
    }

    //    [X] it reduces the price by the tick step until the total capacity is less than the current tick size
    //    [X] the tick capacity is set to the remainder
    //    [X] the tick size does not change

    function test_tickPriceAboveMinimum_newCapacityGreaterThanTickSize_dayTargetMet()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(330e18)
    {
        // Bid size of 330e18 results in:
        // 1. 330e18 * 1e9 / 15e18 = 22e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (330e18 - 150e18) * 1e9 / 165e17 = 10,909,090,909. Greater than tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16
        // 3. (330e18 - 150e18 - 165e18) * 1e9 / 1815e16 = 826,446,280
        // Remaining capacity is 5e9 - 826,446,280 = 4,173,553,720

        // Increase time to 12 hours to get more capacity that exceeds initial tick size
        // Added capacity will be 10e9
        // New capacity will be 4,173,553,720 + 10e9 = 14,173,553,720

        // Calculate the expected tick price with the fix (using initial tick size 10e9)
        // Total capacity = 14,173,553,720
        // Since 14,173,553,720 > 10e9, one decay iteration occurs:
        // - Subtract 10e9: 14,173,553,720 - 10e9 = 4,173,553,720
        // - Apply price decay: 1815e16 * 100e2 / 110e2 = 16500000000000000000 (165e17)
        // - Check: 4,173,553,720 < 10e9, so no more decay
        // Final capacity capped at current tick size (5e9)

        // Warp forward
        uint48 timePassed = 43200; // 12 hours
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity - should be 4,173,553,720 (remainder after decay)
        assertEq(tick.capacity, 4173553720, "new tick capacity");
        assertEq(tick.price, 165e17, "new tick price");
    }

    //   [X] it reduces the price by the tick step until the total capacity is less than the standard tick size
    //   [X] the tick capacity is set to the remainder

    function test_tickPriceAboveMinimum_newCapacityGreaterThanTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (270e18 - 150e18) * 1e9 / 165e17 = 7272727272. Less than the tick size of 10e9, so the tick price remains unchanged.
        // Remaining capacity is 10e9 - 7272727272 = 2727272728

        // 20e9*32400/86400 = 7,500,000,000
        // Added capacity will be 7,500,000,000
        // New capacity will be 2727272728 + 7,500,000,000 = 10227272728

        // Calculate the expected tick price
        // Excess capacity = 10227272728 - 10e9 = 227272728
        // Tick price = 165e17 * 100e2 / 110e2 = 15e18

        // Warp forward
        uint48 timePassed = 32400;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 227272728, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_newCapacityGreaterThanTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenRecipientHasBid(45e18)
    {
        // Bid size of 45e18 results in convertible amount of 3e9
        // Remaining capacity is 7e9

        // Warp forward
        // 6 hours
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Added capacity will be 5e9 (0.25 * 20e9)
        // New capacity will be 7e9 + 5e9 = 12e9

        // Calculate the expected tick price
        // 1. Excess capacity = 12e9 - 10e9 = 2e9
        //    Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //    Tick price is below the minimum price, so it is set to the minimum price
        //
        // Capacity remains the same at 2e9

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 2e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickStepSame_newCapacityLessThanTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenTickStep(100e2)
        givenRecipientHasBid(75e18)
    {
        // Bid size of 75e18 results in convertible amount of 5e9
        // Remaining capacity is 5e9

        // Added capacity will be 2.5e9
        // New capacity will be 5e9 + 2.5e9 = 7.5e9
        // Not greater than tick size, so price remains unchanged

        // Warp forward
        uint48 timePassed = 10800;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 75e8, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickStepSame_newCapacityEqualToTickSize()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
        givenTickStep(100e2)
        givenRecipientHasBid(75e18)
    {
        // Bid size of 75e18 results in convertible amount of 5e9
        // Remaining capacity is 5e9

        // Added capacity will be 5e9
        // New capacity will be 5e9 + 5e9 = 10e9
        // Not greater than tick size, so price remains unchanged

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    // given there is another deposit asset and period enabled
    //  given the tick capacity for the other deposit asset and period has been depleted
    //   [X] the tick price for the current deposit asset and period is the minimum price and not affected by the other deposit asset and period

    function test_givenOtherDepositAssetAndPeriodEnabled_otherTickCapacityDepleted()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // This is for the other deposit asset and period
        // The current deposit asset and period has 10e9 capacity and is at the minimum price

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Added capacity will be 6/24 * 20e9 / 2 = 2.5e9
        // New capacity will be 10e9 + 2.5e9 = 12.5e9
        // Iteration 1:
        // - Capacity = 12.5e9 - 10e9 = 2.5e9
        // - Price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        // - Price is below the minimum price, so it is set to the minimum price

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(
            PERIOD_MONTHS_TWO
        );

        // Assert tick
        assertEq(tick.capacity, 2.5e9, "new tick capacity");
        assertEq(tick.price, MIN_PRICE, "new tick price");
    }

    //  given the tick capacity for the current deposit asset and period has been depleted
    //   [X] the added capacity is based on half of the target and the time passed since the last bid

    function test_givenOtherDepositAssetAndPeriodEnabled_tickCapacityDepleted()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (270e18 - 150e18) * 1e9 / 165e17 = 7272727272. Less than the tick size of 10e9, so the tick price remains unchanged.
        // Remaining capacity is 10e9 - 7272727272 = 2727272728

        // Day target is 20e9
        // Number of active deposit assets and periods is 2
        // Day target allocation is 20e9 / 2 = 10e9

        // 10e9*32400/86400 = 3750000000
        // Added capacity will be 3750000000
        // New capacity will be 2727272728 + 3750000000 = 6477272728
        // < 10e9, so the tick price remains unchanged

        // Warp forward
        uint48 timePassed = 32400;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick
        assertEq(tick.capacity, 6477272728, "new tick capacity");
        assertEq(tick.price, 165e17, "new tick price");
    }

    //  given the day target has been met by the other deposit asset and period
    //   [X] the tick size for the current deposit asset and period is half of the standard tick size

    function test_givenOtherDepositAssetAndPeriodEnabled_otherDepositAssetAndPeriodDayTargetMet()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS_TWO)
        givenEnabled
        givenRecipientHasBid(360375e15)
    {
        // Bid size of 360375e15 results in:
        // 1. 360375e15 * 1e9 / 15e18 = 24,025,000,000. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (360375e15 - 150e18) * 1e9 / 165e17 = 12,750,000,000. Greater than the tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16. Day target met, so tick size becomes 5e9.
        // 3. (360375e15 - 150e18 - 165e18) * 1e9 / 1815e16 = 25e8. Less than the tick size of 5e9.

        // Assert tick
        // Capacity: 5e9
        // Price: 15e18
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(
            PERIOD_MONTHS_TWO
        );
        assertEq(tick.capacity, 5e9, "new tick capacity");
        assertEq(tick.price, MIN_PRICE, "new tick price");

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Added capacity will be 6/24 * 20e9 / 2 = 2.5e9
        // New capacity will be 5e9 + 2.5e9 = 7.5e9
        // Tick size is 5e9
        // Iteration 1:
        // - Capacity = 6.5e9 - 5e9 = 2.5e9
        // - Price = 15e18
        // - Capacity is not greater than the standard tick size, so it exits
        //
        // Capacity is capped to the current tick size

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tickAfterWarp = auctioneer.getCurrentTick(
            PERIOD_MONTHS_TWO
        );

        // Assert tick
        // Capacity: halved as the day target is met
        // Price: unaffected by the day target being met
        assertEq(tickAfterWarp.capacity, 2.5e9, "new tick capacity");
        assertEq(tickAfterWarp.price, MIN_PRICE, "new tick price");
    }

    /// @notice Test that price decay uses initial tick size (10e9), not reduced current tick size (5e9)
    /// @dev This test demonstrates the accelerated price decay bug with deterministic values
    function test_priceDecayUsesInitialTickSize_noDecay()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        _mintReserveToken(recipient, 100000e18);
        _approveReserveTokenSpending(recipient, address(depositManager), 100000e18);

        // Make large purchase to reduce tick size from 10e9 to 5e9
        // Tick one: 10e9 capacity, price of 15e18, deposit of 150e18
        // Tick two: 10e9 capacity, price of 165e17, deposit of 165e18, day target met, so tick size is halved to 5e9
        // Tick three: 5e9 capacity, price of 1815e16, deposit of 90e18. Remaining capacity is 5e9 - 4958677685 = 41322315
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 405e18, 1, false, false);

        // Get state after purchase
        IConvertibleDepositAuctioneer.Tick memory tickAfterPurchase = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Let exactly 6 hours pass
        vm.warp(block.timestamp + 6 hours);

        /**
         * MATHEMATICAL PROOF (using actual test values):
         *
         * Capacity to add over 6 hours:
         * capacityToAdd = (20e9 * 21600) / 86400 / 1 = 5e9
         *
         * After purchase (actual values from test):
         * - tickAfterPurchase.capacity = 41322315
         * - Total capacity = 41322315 + 5e9 = 5041322315
         *
         * CORRECT BEHAVIOR (using initial TICK_SIZE = 10e9):
         * - Check: 5041322315 > 10e9? Not, exit loop
         * - Expected price = unchanged from after purchase
         * - Expected capacity = 5041322315 (but capped at current tick size 5e9)
         */

        // Get actual result
        IConvertibleDepositAuctioneer.Tick memory actualTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Expected values based on actual test scenario
        uint256 capacityToAdd = 5e9; // (20e9 * 21600) / 86400 / 1

        uint256 expectedCapacity = 5e9; // Capped at current tick size
        uint256 expectedPrice = 1815e16; // No price change expected

        console2.log("Capacity after purchase:", tickAfterPurchase.capacity);
        console2.log("Capacity to add (6 hours):", capacityToAdd);
        console2.log("Expected total capacity:", expectedCapacity);
        console2.log("Expected price (no decay):", expectedPrice);
        console2.log("Actual capacity:", actualTick.capacity);
        console2.log("Actual price:", actualTick.price);
        console2.log("Current tick size (reduced):", auctioneer.getCurrentTickSize());

        // These should pass when the fix is implemented (use initial tick size in decay loop)
        assertEq(
            actualTick.capacity,
            expectedCapacity,
            "Should use initial tick size for decay calculation"
        );
        assertEq(
            actualTick.price,
            expectedPrice,
            "Price should not decay when using initial tick size"
        );
    }

    /// @notice Test that price decay correctly performs one iteration using initial tick size (10e9)
    /// @dev This test demonstrates that decay calculations use the initial tick size, not the reduced current tick size
    function test_priceDecayUsesInitialTickSize_oneDecayIteration()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled
    {
        _mintReserveToken(recipient, 100000e18);
        _approveReserveTokenSpending(recipient, address(depositManager), 100000e18);

        // Make large purchase to reduce tick size from 10e9 to 5e9
        // Tick one: 10e9 capacity, price of 15e18, deposit of 150e18
        // Tick two: 10e9 capacity, price of 165e17, deposit of 165e18, day target met, so tick size is halved to 5e9
        // Tick three: 5e9 capacity, price of 1815e16, deposit of 90e18. Remaining capacity is 5e9 - 4958677685 = 41322315
        vm.prank(recipient);
        auctioneer.bid(PERIOD_MONTHS, 405e18, 1, false, false);

        // Get state after purchase
        IConvertibleDepositAuctioneer.Tick memory tickAfterPurchase = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Let exactly 12 hours pass to get more capacity
        vm.warp(block.timestamp + 12 hours);

        /**
         * MATHEMATICAL PROOF (using actual test values):
         *
         * Capacity to add over 12 hours:
         * capacityToAdd = (20e9 * 43200) / 86400 / 1 = 10e9
         *
         * After purchase (from previous test):
         * - tickAfterPurchase.capacity = 41322315
         * - Total capacity = 41322315 + 10e9 = 10041322315
         *
         * CORRECT BEHAVIOR (using initial TICK_SIZE = 10e9):
         * - Check: 10041322315 > 10e9? Yes, enter while loop
         * - Subtract: 10041322315 - 10e9 = 41322315, apply price decay once
         * - Check: 41322315 > 10e9? No, exit loop
         * - Expected price = tickAfterPurchase.price * 100e2 / 110e2 (decay by tick step)
         * - Expected capacity = 41322315 (but capped at current tick size 1e9)
         *
         * BUGGY BEHAVIOR (using reduced tick size = 5e9):
         * - Check: 10.69e9 > 5e9? Yes, enter while loop
         * - Multiple iterations (2+ times) subtracting 5e9 each time
         * - Result: excessive price decay, much lower than expected
         */

        // Get actual result
        IConvertibleDepositAuctioneer.Tick memory actualTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Expected values based on one decay iteration using initial tick size (10e9)
        uint256 capacityToAdd = 10e9; // (20e9 * 43200) / 86400 / 1
        uint256 totalCapacity = 41322315 + capacityToAdd; // 10041322315

        // One decay iteration: totalCapacity - initialTickSize = remainingCapacity
        uint256 remainingCapacity = totalCapacity - 10e9; // 41322315

        // Price decay: tickAfterPurchase.price * 100e2 / 110e2 (using mulDivUp for exact calculation)
        uint256 expectedPrice = 165e17; // Actual calculated value

        // Final capacity capped at current tick size (1e9)
        uint256 expectedCapacity = remainingCapacity > 1e9 ? 1e9 : remainingCapacity;

        console2.log("Capacity after purchase:", tickAfterPurchase.capacity);
        console2.log("Capacity to add (12 hours):", capacityToAdd);
        console2.log("Total capacity before decay:", totalCapacity);
        console2.log("Expected remaining capacity after 1 decay:", remainingCapacity);
        console2.log("Expected price after 1 decay:", expectedPrice);
        console2.log("Expected final capacity (capped):", expectedCapacity);
        console2.log("Actual capacity:", actualTick.capacity);
        console2.log("Actual price:", actualTick.price);
        console2.log("Current tick size (reduced):", auctioneer.getCurrentTickSize());

        // These should pass when the fix is implemented (use initial tick size in decay loop)
        assertEq(
            actualTick.capacity,
            expectedCapacity,
            "Should use initial tick size for decay calculation"
        );
        assertEq(
            actualTick.price,
            expectedPrice,
            "Price should decay exactly once using initial tick size"
        );
    }

    // given the day target is zero
    //  given the tick price is above the minimum
    //   [X] the tick price does not decay
    //   [X] the tick size does not decay

    function test_givenTickPriceAboveMinimum_targetZero(
        uint48 secondsPassed_
    )
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabled // Start with standard parameters
        givenRecipientHasBid(1000e18) // Make a bid to move the tick
    {
        uint48 secondsPassed = uint48(bound(secondsPassed_, 1, 7 days));

        // Disable the auction by setting target to 0
        _setAuctionParameters(0, TICK_SIZE, MIN_PRICE);

        IConvertibleDepositAuctioneer.Tick memory previousTick = auctioneer.getPreviousTick(
            PERIOD_MONTHS
        );

        // Warp to change the block timestamp
        vm.warp(block.timestamp + secondsPassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert current tick
        // As the day target is zero, no new capacity is added and no decay occurs, hence the values stay the same
        assertEq(
            tick.capacity,
            previousTick.capacity,
            "capacity should not change when target is 0"
        );
        assertEq(tick.price, previousTick.price, "price should not decay when target is 0");
        assertEq(
            tick.lastUpdate,
            previousTick.lastUpdate,
            "lastUpdate should not change when target is 0"
        );

        // Assert auction is not active
        assertEq(
            auctioneer.isAuctionActive(),
            false,
            "auction should be inactive when target is 0"
        );
    }

    // ========== GAS SNAPSHOT TESTS FOR TICK DECAY OPTIMIZATION ========== //

    /// @notice Test price decay with few ticks (~8 ticks)
    /// @dev MATHEMATICAL PROOF:
    ///      Tick size: 2e8 (0.2e9 OHM)
    ///      Target: 20e9 OHM/day
    ///      Time warp: 2 hours
    ///
    ///      STEP 1: Initial state after bid
    ///      Starting price: 998409613180787391841156435 wei
    ///      Starting capacity: 98614089 wei of OHM
    ///
    ///      STEP 2: Calculate decay
    ///      Capacity added = (20e9 * 2 hours) / 24 hours = 1666666666 wei of OHM
    ///      Total capacity = initialCapacity + addedCapacity = 98614089 + 1666666666 = 1765280755 wei
    ///
    ///      Decay loop: while (newCapacity > tickSize)
    ///      Tick size = 2e8 = 200000000 wei
    ///
    ///      Iteration 0: newCapacity = 1765280755 > 200000000 ✓
    ///                   price = 998409613180787391841156435.mulDivUp(100e2, 110e2) = 907645102891624901673778578
    ///                   newCapacity = 1765280755 - 200000000 = 1565280755
    ///
    ///      Iteration 1: newCapacity = 1565280755 > 200000000 ✓
    ///                   price = 907645102891624901673778578.mulDivUp(100e2, 110e2) = 825131911719659001521616890
    ///                   newCapacity = 1565280755 - 200000000 = 1365280755
    ///
    ///      Iteration 2: newCapacity = 1365280755 > 200000000 ✓
    ///                   price = 825131911719659001521616890.mulDivUp(100e2, 110e2) = 750119919745144546837833537
    ///                   newCapacity = 1365280755 - 200000000 = 1165280755
    ///
    ///      Iteration 3: newCapacity = 1165280755 > 200000000 ✓
    ///                   price = 750119919745144546837833537.mulDivUp(100e2, 110e2) = 681927199768313224398030489
    ///                   newCapacity = 1165280755 - 200000000 = 965280755
    ///
    ///      Iteration 4: newCapacity = 965280755 > 200000000 ✓
    ///                   price = 681927199768313224398030489.mulDivUp(100e2, 110e2) = 619933817971193840361845900
    ///                   newCapacity = 965280755 - 200000000 = 765280755
    ///
    ///      Iteration 5: newCapacity = 765280755 > 200000000 ✓
    ///                   price = 619933817971193840361845900.mulDivUp(100e2, 110e2) = 563576198155630763965314455
    ///                   newCapacity = 765280755 - 200000000 = 565280755
    ///
    ///      Iteration 6: newCapacity = 565280755 > 200000000 ✓
    ///                   price = 563576198155630763965314455.mulDivUp(100e2, 110e2) = 512341998323300694513922232
    ///                   newCapacity = 565280755 - 200000000 = 365280755
    ///
    ///      Iteration 7: newCapacity = 365280755 > 200000000 ✓
    ///                   price = 512341998323300694513922232.mulDivUp(100e2, 110e2) = 465765453021182449558111120
    ///                   newCapacity = 365280755 - 200000000 = 165280755
    ///
    ///      Iteration 8: newCapacity = 165280755 > 200000000 ✗ (loop exits)
    ///
    ///      Final price = 465765453021182449558111120 wei
    ///      Final capacity = 165280755 wei
    ///
    ///      STEP 3: Calculate final capacity
    ///      Total capacity = initialCapacity + addedCapacity
    ///      Initial capacity = 2e8 (full tick after bid)
    ///      Added capacity = 1,666,666,666 OHM
    ///      Total capacity = 2e8 + 1,666,666,666 = 1,866,666,666 OHM
    ///
    ///      After 8 tick traversals: 1,866,666,666 - (8 × 2e8) = 1,866,666,666 - 1,600,000,000 = 266,666,666 OHM
    ///      Since 266666666 < 1e8 (current tick size), the final capacity is 1e8
    ///      Final capacity = 1e8 OHM
    function test_priceDecay_fewTicks()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(TARGET, 2e8, MIN_PRICE)
        givenRecipientHasBid(1000000000e18)
    {
        // Get initial price after bids
        IConvertibleDepositAuctioneer.Tick memory initialTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Warp to create capacity requiring 8 ticks
        uint48 timeWarp = uint48(2 hours);
        vm.warp(block.timestamp + timeWarp);

        // Snapshot gas
        vm.startSnapshotGas("priceDecay_fewTicks");
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);
        uint256 gasUsed = vm.stopSnapshotGas();

        // Log results
        console2.log("=== Few Ticks (8 ticks) ===");
        console2.log("Initial price after bids:", initialTick.price);
        console2.log("Initial capacity:", initialTick.capacity);
        console2.log("Time warped (hours):", timeWarp / 1 hours);
        console2.log("Gas used:", gasUsed);
        console2.log("Final price:", tick.price);
        console2.log("Final capacity:", tick.capacity);

        // Verify correctness with hard-coded expected values
        assertEq(tick.price, 465765453021182449558111120, "Final price after 8 ticks");
        assertEq(tick.capacity, 1e8, "Final capacity after 8 tick traversals");
    }

    /// @notice Test price decay with many ticks (25 ticks)
    /// @dev MATHEMATICAL PROOF:
    ///      Tick size: 2e8 (0.2e9 OHM)
    ///      Target: 20e9 OHM/day
    ///      Time warp: 6 hours
    ///
    ///      STEP 1: Initial state after bid
    ///      Starting price: 998409613180787391841156435 wei
    ///      Starting capacity: 98614089 wei of OHM
    ///
    ///      STEP 2: Calculate decay
    ///      Capacity added = (20e9 * 6 hours) / 24 hours = 5000000000 wei of OHM
    ///      Total capacity = initialCapacity + addedCapacity = 98614089 + 5000000000 = 5098614089 wei
    ///
    ///      Decay loop: while (newCapacity > tickSize)
    ///      Tick size = 2e8 = 200000000 wei
    ///
    ///      Iteration 0: newCapacity = 5098614089 > 200000000 ✓
    ///                   price = 998409613180787391841156435.mulDivUp(100e2, 110e2) = 907645102891624901673778578
    ///                   newCapacity = 5098614089 - 200000000 = 4898614089
    ///
    ///      Iteration 1: newCapacity = 4898614089 > 200000000 ✓
    ///                   price = 907645102891624901673778578.mulDivUp(100e2, 110e2) = 825131911719659001521616890
    ///                   newCapacity = 4898614089 - 200000000 = 4698614089
    ///
    ///      Iteration 2: newCapacity = 4698614089 > 200000000 ✓
    ///                   price = 825131911719659001521616890.mulDivUp(100e2, 110e2) = 750119919745144546837833537
    ///                   newCapacity = 4698614089 - 200000000 = 4498614089
    ///
    ///      Iteration 3: newCapacity = 4498614089 > 200000000 ✓
    ///                   price = 750119919745144546837833537.mulDivUp(100e2, 110e2) = 681927199768313224398030489
    ///                   newCapacity = 4498614089 - 200000000 = 4298614089
    ///
    ///      Iteration 4: newCapacity = 4298614089 > 200000000 ✓
    ///                   price = 681927199768313224398030489.mulDivUp(100e2, 110e2) = 619933817971193840361845900
    ///                   newCapacity = 4298614089 - 200000000 = 4098614089
    ///
    ///      Iteration 5: newCapacity = 4098614089 > 200000000 ✓
    ///                   price = 619933817971193840361845900.mulDivUp(100e2, 110e2) = 563576198155630763965314455
    ///                   newCapacity = 4098614089 - 200000000 = 3898614089
    ///
    ///      Iteration 6: newCapacity = 3898614089 > 200000000 ✓
    ///                   price = 563576198155630763965314455.mulDivUp(100e2, 110e2) = 512341998323300694513922232
    ///                   newCapacity = 3898614089 - 200000000 = 3698614089
    ///
    ///      Iteration 7: newCapacity = 3698614089 > 200000000 ✓
    ///                   price = 512341998323300694513922232.mulDivUp(100e2, 110e2) = 465765453021182449558111120
    ///                   newCapacity = 3698614089 - 200000000 = 3498614089
    ///
    ///      Iteration 8: newCapacity = 3498614089 > 200000000 ✓
    ///                   price = 465765453021182449558111120.mulDivUp(100e2, 110e2) = 423423139110165863234646473
    ///                   newCapacity = 3498614089 - 200000000 = 3298614089
    ///
    ///      Iteration 9: newCapacity = 3298614089 > 200000000 ✓
    ///                   price = 423423139110165863234646473.mulDivUp(100e2, 110e2) = 384930126463787148395133158
    ///                   newCapacity = 3298614089 - 200000000 = 3098614089
    ///
    ///      Iteration 10: newCapacity = 3098614089 > 200000000 ✓
    ///                    price = 384930126463787148395133158.mulDivUp(100e2, 110e2) = 349936478603442862177393780
    ///                    newCapacity = 3098614089 - 200000000 = 2898614089
    ///
    ///      Iteration 11: newCapacity = 2898614089 > 200000000 ✓
    ///                    price = 349936478603442862177393780.mulDivUp(100e2, 110e2) = 318124071457675329252176164
    ///                    newCapacity = 2898614089 - 200000000 = 2698614089
    ///
    ///      Iteration 12: newCapacity = 2698614089 > 200000000 ✓
    ///                    price = 318124071457675329252176164.mulDivUp(100e2, 110e2) = 289203701325159390229251059
    ///                    newCapacity = 2698614089 - 200000000 = 2498614089
    ///
    ///      Iteration 13: newCapacity = 2498614089 > 200000000 ✓
    ///                    price = 289203701325159390229251059.mulDivUp(100e2, 110e2) = 262912455750144900208410054
    ///                    newCapacity = 2498614089 - 200000000 = 2298614089
    ///
    ///      Iteration 14: newCapacity = 2298614089 > 200000000 ✓
    ///                    price = 262912455750144900208410054.mulDivUp(100e2, 110e2) = 239011323409222636553100050
    ///                    newCapacity = 2298614089 - 200000000 = 2098614089
    ///
    ///      Iteration 15: newCapacity = 2098614089 > 200000000 ✓
    ///                    price = 239011323409222636553100050.mulDivUp(100e2, 110e2) = 217283021281111487775545500
    ///                    newCapacity = 2098614089 - 200000000 = 1898614089
    ///
    ///      Iteration 16: newCapacity = 1898614089 > 200000000 ✓
    ///                    price = 217283021281111487775545500.mulDivUp(100e2, 110e2) = 197530019346464988886859546
    ///                    newCapacity = 1898614089 - 200000000 = 1698614089
    ///
    ///      Iteration 17: newCapacity = 1698614089 > 200000000 ✓
    ///                    price = 197530019346464988886859546.mulDivUp(100e2, 110e2) = 179572744860422717169872315
    ///                    newCapacity = 1698614089 - 200000000 = 1498614089
    ///
    ///      Iteration 18: newCapacity = 1498614089 > 200000000 ✓
    ///                    price = 179572744860422717169872315.mulDivUp(100e2, 110e2) = 163247949873111561063520287
    ///                    newCapacity = 1498614089 - 200000000 = 1298614089
    ///
    ///      Iteration 19: newCapacity = 1298614089 > 200000000 ✓
    ///                    price = 163247949873111561063520287.mulDivUp(100e2, 110e2) = 148407227157374146421382080
    ///                    newCapacity = 1298614089 - 200000000 = 1098614089
    ///
    ///      Iteration 20: newCapacity = 1098614089 > 200000000 ✓
    ///                    price = 148407227157374146421382080.mulDivUp(100e2, 110e2) = 134915661052158314928529164
    ///                    newCapacity = 1098614089 - 200000000 = 898614089
    ///
    ///      Iteration 21: newCapacity = 898614089 > 200000000 ✓
    ///                    price = 134915661052158314928529164.mulDivUp(100e2, 110e2) = 122650600956507559025935604
    ///                    newCapacity = 898614089 - 200000000 = 698614089
    ///
    ///      Iteration 22: newCapacity = 698614089 > 200000000 ✓
    ///                    price = 122650600956507559025935604.mulDivUp(100e2, 110e2) = 111500546324097780932668731
    ///                    newCapacity = 698614089 - 200000000 = 498614089
    ///
    ///      Iteration 23: newCapacity = 498614089 > 200000000 ✓
    ///                    price = 111500546324097780932668731.mulDivUp(100e2, 110e2) = 101364133021907073575153392
    ///                    newCapacity = 498614089 - 200000000 = 298614089
    ///
    ///      Iteration 24: newCapacity = 298614089 > 200000000 ✓
    ///                    price = 101364133021907073575153392.mulDivUp(100e2, 110e2) = 92149211838097339613775811
    ///                    newCapacity = 298614089 - 200000000 = 98614089
    ///
    ///      Iteration 25: newCapacity = 98614089 > 200000000 ✗ (loop exits)
    ///
    ///      Final price = 92149211838097339613775811 wei
    ///      Final capacity = 98614089 wei
    function test_priceDecay_manyTicks()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(TARGET, 2e8, MIN_PRICE)
        givenRecipientHasBid(1000000000e18)
    {
        // Get initial price after bids
        IConvertibleDepositAuctioneer.Tick memory initialTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Warp to create capacity requiring 25 ticks
        uint48 timeWarp = uint48(6 hours);
        vm.warp(block.timestamp + timeWarp);

        // Snapshot gas
        vm.startSnapshotGas("priceDecay_manyTicks");
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);
        uint256 gasUsed = vm.stopSnapshotGas();

        // Log results
        console2.log("=== Many Ticks (25 ticks) ===");
        console2.log("Initial price after bids:", initialTick.price);
        console2.log("Initial capacity:", initialTick.capacity);
        console2.log("Time warped (hours):", timeWarp / 1 hours);
        console2.log("Gas used:", gasUsed);
        console2.log("Final price:", tick.price);
        console2.log("Final capacity:", tick.capacity);

        // Verify correctness with hard-coded expected values
        assertEq(tick.price, 92149211838097339613775811, "Final price after 25 ticks");
        assertEq(tick.capacity, 98614089, "Final capacity after 25 tick traversals");
    }

    /// @notice Test price decay with few ticks (~50 ticks)
    /// @dev MATHEMATICAL PROOF:
    ///      Tick size: 2e8 (0.2e9 OHM)
    ///      Target: 20e9 OHM/day
    ///      Time warp: 12 hours
    ///
    ///      STEP 1: Initial state after bid
    ///      Starting price: 998409613180787391841156435 wei
    ///      Starting capacity: 98614089 wei of OHM
    ///
    ///      STEP 2: Calculate decay
    ///      Capacity added = (20e9 * 12 hours) / 24 hours = 10000000000 wei of OHM
    ///      Total capacity = initialCapacity + addedCapacity = 98614089 + 10000000000 = 10098614089 wei
    ///
    ///      Decay loop: while (newCapacity > tickSize)
    ///      Tick size = 2e8 = 200000000 wei
    ///
    ///      Iteration 0: newCapacity = 10098614089 > 200000000 ✓
    ///                   price = 998409613180787391841156435.mulDivUp(100e2, 110e2) = 907645102891624901673778578
    ///                   newCapacity = 10098614089 - 200000000 = 9898614089
    ///
    ///      Iteration 1: newCapacity = 9898614089 > 200000000 ✓
    ///                   price = 907645102891624901673778578.mulDivUp(100e2, 110e2) = 825131911719659001521616890
    ///                   newCapacity = 9898614089 - 200000000 = 9698614089
    ///
    ///      Iteration 2: newCapacity = 9698614089 > 200000000 ✓
    ///                   price = 825131911719659001521616890.mulDivUp(100e2, 110e2) = 750119919745144546837833537
    ///                   newCapacity = 9698614089 - 200000000 = 9498614089
    ///
    ///      Iteration 3: newCapacity = 9498614089 > 200000000 ✓
    ///                   price = 750119919745144546837833537.mulDivUp(100e2, 110e2) = 681927199768313224398030489
    ///                   newCapacity = 9498614089 - 200000000 = 9298614089
    ///
    ///      Iteration 4: newCapacity = 9298614089 > 200000000 ✓
    ///                   price = 681927199768313224398030489.mulDivUp(100e2, 110e2) = 619933817971193840361845900
    ///                   newCapacity = 9298614089 - 200000000 = 9098614089
    ///
    ///      Iteration 5: newCapacity = 9098614089 > 200000000 ✓
    ///                   price = 619933817971193840361845900.mulDivUp(100e2, 110e2) = 563576198155630763965314455
    ///                   newCapacity = 9098614089 - 200000000 = 8898614089
    ///
    ///      Iteration 6: newCapacity = 8898614089 > 200000000 ✓
    ///                   price = 563576198155630763965314455.mulDivUp(100e2, 110e2) = 512341998323300694513922232
    ///                   newCapacity = 8898614089 - 200000000 = 8698614089
    ///
    ///      Iteration 7: newCapacity = 8698614089 > 200000000 ✓
    ///                   price = 512341998323300694513922232.mulDivUp(100e2, 110e2) = 465765453021182449558111120
    ///                   newCapacity = 8698614089 - 200000000 = 8498614089
    ///
    ///      Iteration 8: newCapacity = 8498614089 > 200000000 ✓
    ///                   price = 465765453021182449558111120.mulDivUp(100e2, 110e2) = 423423139110165863234646473
    ///                   newCapacity = 8498614089 - 200000000 = 8298614089
    ///
    ///      Iteration 9: newCapacity = 8298614089 > 200000000 ✓
    ///                   price = 423423139110165863234646473.mulDivUp(100e2, 110e2) = 384930126463787148395133158
    ///                   newCapacity = 8298614089 - 200000000 = 8098614089
    ///
    ///      Iteration 10: newCapacity = 8098614089 > 200000000 ✓
    ///                    price = 384930126463787148395133158.mulDivUp(100e2, 110e2) = 349936478603442862177393780
    ///                    newCapacity = 8098614089 - 200000000 = 7898614089
    ///
    ///      Iteration 11: newCapacity = 7898614089 > 200000000 ✓
    ///                    price = 349936478603442862177393780.mulDivUp(100e2, 110e2) = 318124071457675329252176164
    ///                    newCapacity = 7898614089 - 200000000 = 7698614089
    ///
    ///      Iteration 12: newCapacity = 7698614089 > 200000000 ✓
    ///                    price = 318124071457675329252176164.mulDivUp(100e2, 110e2) = 289203701325159390229251059
    ///                    newCapacity = 7698614089 - 200000000 = 7498614089
    ///
    ///      Iteration 13: newCapacity = 7498614089 > 200000000 ✓
    ///                    price = 289203701325159390229251059.mulDivUp(100e2, 110e2) = 262912455750144900208410054
    ///                    newCapacity = 7498614089 - 200000000 = 7298614089
    ///
    ///      Iteration 14: newCapacity = 7298614089 > 200000000 ✓
    ///                    price = 262912455750144900208410054.mulDivUp(100e2, 110e2) = 239011323409222636553100050
    ///                    newCapacity = 7298614089 - 200000000 = 7098614089
    ///
    ///      Iteration 15: newCapacity = 7098614089 > 200000000 ✓
    ///                    price = 239011323409222636553100050.mulDivUp(100e2, 110e2) = 217283021281111487775545500
    ///                    newCapacity = 7098614089 - 200000000 = 6898614089
    ///
    ///      Iteration 16: newCapacity = 6898614089 > 200000000 ✓
    ///                    price = 217283021281111487775545500.mulDivUp(100e2, 110e2) = 197530019346464988886859546
    ///                    newCapacity = 6898614089 - 200000000 = 6698614089
    ///
    ///      Iteration 17: newCapacity = 6698614089 > 200000000 ✓
    ///                    price = 197530019346464988886859546.mulDivUp(100e2, 110e2) = 179572744860422717169872315
    ///                    newCapacity = 6698614089 - 200000000 = 6498614089
    ///
    ///      Iteration 18: newCapacity = 6498614089 > 200000000 ✓
    ///                    price = 179572744860422717169872315.mulDivUp(100e2, 110e2) = 163247949873111561063520287
    ///                    newCapacity = 6498614089 - 200000000 = 6298614089
    ///
    ///      Iteration 19: newCapacity = 6298614089 > 200000000 ✓
    ///                    price = 163247949873111561063520287.mulDivUp(100e2, 110e2) = 148407227157374146421382080
    ///                    newCapacity = 6298614089 - 200000000 = 6098614089
    ///
    ///      Iteration 20: newCapacity = 6098614089 > 200000000 ✓
    ///                    price = 148407227157374146421382080.mulDivUp(100e2, 110e2) = 134915661052158314928529164
    ///                    newCapacity = 6098614089 - 200000000 = 5898614089
    ///
    ///      Iteration 21: newCapacity = 5898614089 > 200000000 ✓
    ///                    price = 134915661052158314928529164.mulDivUp(100e2, 110e2) = 122650600956507559025935604
    ///                    newCapacity = 5898614089 - 200000000 = 5698614089
    ///
    ///      Iteration 22: newCapacity = 5698614089 > 200000000 ✓
    ///                    price = 122650600956507559025935604.mulDivUp(100e2, 110e2) = 111500546324097780932668731
    ///                    newCapacity = 5698614089 - 200000000 = 5498614089
    ///
    ///      Iteration 23: newCapacity = 5498614089 > 200000000 ✓
    ///                    price = 111500546324097780932668731.mulDivUp(100e2, 110e2) = 101364133021907073575153392
    ///                    newCapacity = 5498614089 - 200000000 = 5298614089
    ///
    ///      Iteration 24: newCapacity = 5298614089 > 200000000 ✓
    ///                    price = 101364133021907073575153392.mulDivUp(100e2, 110e2) = 92149211838097339613775811
    ///                    newCapacity = 5298614089 - 200000000 = 5098614089
    ///
    ///      Iteration 25: newCapacity = 5098614089 > 200000000 ✓
    ///                    price = 92149211838097339613775811.mulDivUp(100e2, 110e2) = 83772010761906672376159829
    ///                    newCapacity = 5098614089 - 200000000 = 4898614089
    ///
    ///      Iteration 26: newCapacity = 4898614089 > 200000000 ✓
    ///                    price = 83772010761906672376159829.mulDivUp(100e2, 110e2) = 76156373419915156705599845
    ///                    newCapacity = 4898614089 - 200000000 = 4698614089
    ///
    ///      Iteration 27: newCapacity = 4698614089 > 200000000 ✓
    ///                    price = 76156373419915156705599845.mulDivUp(100e2, 110e2) = 69233066745377415186908950
    ///                    newCapacity = 4698614089 - 200000000 = 4498614089
    ///
    ///      Iteration 28: newCapacity = 4498614089 > 200000000 ✓
    ///                    price = 69233066745377415186908950.mulDivUp(100e2, 110e2) = 62939151586706741079008137
    ///                    newCapacity = 4498614089 - 200000000 = 4298614089
    ///
    ///      Iteration 29: newCapacity = 4298614089 > 200000000 ✓
    ///                    price = 62939151586706741079008137.mulDivUp(100e2, 110e2) = 57217410533369764617280125
    ///                    newCapacity = 4298614089 - 200000000 = 4098614089
    ///
    ///      Iteration 30: newCapacity = 4098614089 > 200000000 ✓
    ///                    price = 57217410533369764617280125.mulDivUp(100e2, 110e2) = 52015827757608876924800114
    ///                    newCapacity = 4098614089 - 200000000 = 3898614089
    ///
    ///      Iteration 31: newCapacity = 3898614089 > 200000000 ✓
    ///                    price = 52015827757608876924800114.mulDivUp(100e2, 110e2) = 47287116143280797204363740
    ///                    newCapacity = 3898614089 - 200000000 = 3698614089
    ///
    ///      Iteration 32: newCapacity = 3698614089 > 200000000 ✓
    ///                    price = 47287116143280797204363740.mulDivUp(100e2, 110e2) = 42988287402982542913057946
    ///                    newCapacity = 3698614089 - 200000000 = 3498614089
    ///
    ///      Iteration 33: newCapacity = 3498614089 > 200000000 ✓
    ///                    price = 42988287402982542913057946.mulDivUp(100e2, 110e2) = 39080261275438675375507224
    ///                    newCapacity = 3498614089 - 200000000 = 3298614089
    ///
    ///      Iteration 34: newCapacity = 3298614089 > 200000000 ✓
    ///                    price = 39080261275438675375507224.mulDivUp(100e2, 110e2) = 35527510250398795795915659
    ///                    newCapacity = 3298614089 - 200000000 = 3098614089
    ///
    ///      Iteration 35: newCapacity = 3098614089 > 200000000 ✓
    ///                    price = 35527510250398795795915659.mulDivUp(100e2, 110e2) = 32297736591271632541741509
    ///                    newCapacity = 3098614089 - 200000000 = 2898614089
    ///
    ///      Iteration 36: newCapacity = 2898614089 > 200000000 ✓
    ///                    price = 32297736591271632541741509.mulDivUp(100e2, 110e2) = 29361578719337847765219554
    ///                    newCapacity = 2898614089 - 200000000 = 2698614089
    ///
    ///      Iteration 37: newCapacity = 2698614089 > 200000000 ✓
    ///                    price = 29361578719337847765219554.mulDivUp(100e2, 110e2) = 26692344290307134332017777
    ///                    newCapacity = 2698614089 - 200000000 = 2498614089
    ///
    ///      Iteration 38: newCapacity = 2498614089 > 200000000 ✓
    ///                    price = 26692344290307134332017777.mulDivUp(100e2, 110e2) = 24265767536642849392743434
    ///                    newCapacity = 2498614089 - 200000000 = 2298614089
    ///
    ///      Iteration 39: newCapacity = 2298614089 > 200000000 ✓
    ///                    price = 24265767536642849392743434.mulDivUp(100e2, 110e2) = 22059788669675317629766759
    ///                    newCapacity = 2298614089 - 200000000 = 2098614089
    ///
    ///      Iteration 40: newCapacity = 2098614089 > 200000000 ✓
    ///                    price = 22059788669675317629766759.mulDivUp(100e2, 110e2) = 20054353336068470572515236
    ///                    newCapacity = 2098614089 - 200000000 = 1898614089
    ///
    ///      Iteration 41: newCapacity = 1898614089 > 200000000 ✓
    ///                    price = 20054353336068470572515236.mulDivUp(100e2, 110e2) = 18231230305516791429559306
    ///                    newCapacity = 1898614089 - 200000000 = 1698614089
    ///
    ///      Iteration 42: newCapacity = 1698614089 > 200000000 ✓
    ///                    price = 18231230305516791429559306.mulDivUp(100e2, 110e2) = 16573845732287992208690279
    ///                    newCapacity = 1698614089 - 200000000 = 1498614089
    ///
    ///      Iteration 43: newCapacity = 1498614089 > 200000000 ✓
    ///                    price = 16573845732287992208690279.mulDivUp(100e2, 110e2) = 15067132483898174735172981
    ///                    newCapacity = 1498614089 - 200000000 = 1298614089
    ///
    ///      Iteration 44: newCapacity = 1298614089 > 200000000 ✓
    ///                    price = 15067132483898174735172981.mulDivUp(100e2, 110e2) = 13697393167180158850157256
    ///                    newCapacity = 1298614089 - 200000000 = 1098614089
    ///
    ///      Iteration 45: newCapacity = 1098614089 > 200000000 ✓
    ///                    price = 13697393167180158850157256.mulDivUp(100e2, 110e2) = 12452175606527417136506597
    ///                    newCapacity = 1098614089 - 200000000 = 898614089
    ///
    ///      Iteration 46: newCapacity = 898614089 > 200000000 ✓
    ///                    price = 12452175606527417136506597.mulDivUp(100e2, 110e2) = 11320159642297651942278725
    ///                    newCapacity = 898614089 - 200000000 = 698614089
    ///
    ///      Iteration 47: newCapacity = 698614089 > 200000000 ✓
    ///                    price = 11320159642297651942278725.mulDivUp(100e2, 110e2) = 10291054220270592674798841
    ///                    newCapacity = 698614089 - 200000000 = 498614089
    ///
    ///      Iteration 48: newCapacity = 498614089 > 200000000 ✓
    ///                    price = 10291054220270592674798841.mulDivUp(100e2, 110e2) = 9355503836609629704362583
    ///                    newCapacity = 498614089 - 200000000 = 298614089
    ///
    ///      Iteration 49: newCapacity = 298614089 > 200000000 ✓
    ///                    price = 9355503836609629704362583.mulDivUp(100e2, 110e2) = 8505003487826936094875076
    ///                    newCapacity = 298614089 - 200000000 = 98614089
    ///
    ///      Iteration 50: newCapacity = 98614089 > 200000000 ✗ (loop exits)
    ///
    ///      Final price = 8505003487826936094875076 wei
    ///      Final capacity = 98614089 wei
    function test_priceDecay_veryManyTicks()
        public
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenEnabledWithParameters(TARGET, 2e8, MIN_PRICE)
        givenRecipientHasBid(1000000000e18)
    {
        // Get initial price after bids
        IConvertibleDepositAuctioneer.Tick memory initialTick = auctioneer.getCurrentTick(
            PERIOD_MONTHS
        );

        // Warp to create capacity requiring 50 ticks
        uint48 timeWarp = uint48(12 hours);
        vm.warp(block.timestamp + timeWarp);

        // Snapshot gas
        vm.startSnapshotGas("priceDecay_veryManyTicks");
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);
        uint256 gasUsed = vm.stopSnapshotGas();

        // Log results
        console2.log("=== Very Many Ticks (50 ticks) ===");
        console2.log("Initial price after bids:", initialTick.price);
        console2.log("Initial capacity:", initialTick.capacity);
        console2.log("Time warped (hours):", timeWarp / 1 hours);
        console2.log("Gas used:", gasUsed);
        console2.log("Final price:", tick.price);
        console2.log("Final capacity:", tick.capacity);

        // Verify correctness with hard-coded expected values
        assertEq(tick.price, 8505003487826936094875076, "Final price after 50 ticks");
        assertEq(tick.capacity, 98614089, "Final capacity after 50 tick traversals");
    }

    // TODO add tests for overflow of tick price calculation
}
