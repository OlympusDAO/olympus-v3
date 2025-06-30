// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerCurrentTickTest is ConvertibleDepositAuctioneerTest {
    // given the contract is disabled
    //  [X] it reverts

    function test_contractDisabled_reverts() public {
        // Expect revert
        _expectNotEnabledRevert();

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

    function test_fullCapacity_sameTime(
        uint48 secondsPassed_
    ) public givenEnabled givenDepositPeriodEnabled(PERIOD_MONTHS) {
        uint48 secondsPassed = uint48(bound(secondsPassed_, 0, 86400 - 1));

        // Warp to change the block timestamp
        vm.warp(block.timestamp + secondsPassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        uint256 expectedTickPrice = 15e18;
        uint256 expectedTickCapacity = 10e9;

        // Assert current tick
        assertEq(tick.capacity, expectedTickCapacity, "capacity");
        assertEq(tick.price, expectedTickPrice, "price");
    }

    //  [X] the tick price remains at the min price
    //  [X] the tick capacity remains at the standard tick size

    function test_fullCapacity(
        uint48 secondsPassed_
    ) public givenEnabled givenDepositPeriodEnabled(PERIOD_MONTHS) {
        uint48 secondsPassed = uint48(bound(secondsPassed_, 1, 7 days));

        // Warp to change the block timestamp
        vm.warp(block.timestamp + secondsPassed);

        // Expected values
        // Tick size = 10e9
        // Tick step = 110e2
        // Current tick capacity = tick size = 10e9
        // Current tick price = min price = 15e18
        // New capacity added = target * days passed = 20e9 * 2 = 40e9
        // New capacity = 10e9 + 40e9 = 50e9
        // Iteration 1:
        //   New capacity = 50e9 - 10e9 = 40e9
        //   Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //
        // Updated tick price is < min price, so it is set to the min price
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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

        // Call setAuctionParameters, which resets the day
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 1815e16, "new tick price");
    }

    //   [X] the tick price is unchanged
    //   [X] the tick capacity is set to the current tick size
    //   [X] the tick size does not change

    function test_newCapacityEqualToTickSize_dayTargetMet()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenTickStep(100e2)
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenRecipientHasBid(330e18)
    {
        // Bid size of 330e18 results in:
        // 1. 330e18 * 1e9 / 15e18 = 22e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (330e18 - 150e18) * 1e9 / 165e17 = 10,909,090,909. Greater than tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16
        // 3. (330e18 - 150e18 - 165e18) * 1e9 / 1815e16 = 826,446,280
        // Remaining capacity is 5e9 - 826,446,280 = 4,173,553,720

        // Added capacity will be 30e9
        // New capacity will be 4,173,553,720 + 30e9 = 34,173,553,720

        // Calculate the expected tick price
        // As it is the next day, the tick size will reset to 10e9
        // 1. Excess capacity = 34,173,553,720 - 10e9 = 24,173,553,720
        //    Tick price = 165e17
        // 2. Excess capacity = 24,173,553,720 - 10e9 = 14,173,553,720
        //    Tick price = 165e17 * 100e2 / 110e2 = 15e18
        // 3. Excess capacity = 14,173,553,720 - 10e9 = 4,173,553,720
        //    Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //    Tick price is below the minimum price, so it is set to the minimum price
        //    New capacity = current tick size = 10e9

        // Warp forward
        // Otherwise the time passed will not be correct
        vm.warp(block.timestamp + 6 * 21600);

        // Call setAuctionParameters, which resets the day
        vm.prank(emissionManager);
        auctioneer.setAuctionParameters(TARGET, TICK_SIZE, MIN_PRICE);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    //     [ ] the tick price is set to the minimum price
    //     [ ] the tick capacity is set to the current tick size
    //     [ ] the tick size does not change

    //    [X] the tick price is set to the minimum price
    //    [X] the capacity is set to the standard tick size

    function test_tickPriceAboveMinimum_newPriceBelowMinimum()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (270e18 - 150e18) * 1e9 / 165e17 = 7,272,727,273. Less than tick size of 10e9.
        // Remaining capacity is 10e9 - 7,272,727,273 = 2,727,272,727

        // Added capacity will be 30e9
        // New capacity will be 2,727,272,727 + 30e9 = 32,727,272,727

        // Calculate the expected tick price
        // 1. Excess capacity = 32,727,272,727 - 10e9 = 22,727,272,727
        //    Tick price = 165e17
        // 2. Excess capacity = 22,727,272,727 - 10e9 = 12,727,272,727
        //    Tick price = 165e17 * 100e2 / 110e2 = 15e18
        // 3. Excess capacity = 12,727,272,727 - 10e9 = 2,727,272,727
        //    Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //    Tick price is below the minimum price, so it is set to the minimum price
        //    New capacity = tick size = 10e9

        // Warp forward
        uint48 timePassed = 6 * 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    //   given the current tick size is 5e9
    //    given the current timestamp is on a different day to the last bid
    //     [X] the tick capacity is set to the standard tick size
    //     [X] the tick size is set to the standard tick size

    function test_tickPriceAboveMinimum_newCapacityGreaterThanTickSize_dayTargetMet_nextDay()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenRecipientHasBid(330e18)
    {
        // Bid size of 330e18 results in:
        // 1. 330e18 * 1e9 / 15e18 = 22e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (330e18 - 150e18) * 1e9 / 165e17 = 10,909,090,909. Greater than tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16
        // 3. (330e18 - 150e18 - 165e18) * 1e9 / 1815e16 = 826,446,280
        // Remaining capacity is 5e9 - 826,446,280 = 4,173,553,720

        // Added capacity will be 5e9
        // New capacity will be 4,173,553,720 + 5e9 = 9,173,553,720

        // Calculate the expected tick price
        // Excess capacity = 9,173,553,720 - 5e9 = 4,173,553,720
        // Tick price = 165e17

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 4173553720, "new tick capacity");
        assertEq(tick.price, 165e17, "new tick price");
    }

    //   [X] it reduces the price by the tick step until the total capacity is less than the standard tick size
    //   [X] the tick capacity is set to the remainder

    function test_tickPriceAboveMinimum_newCapacityGreaterThanTickSize()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenRecipientHasBid(45e18)
    {
        // Bid size of 45e18 results in convertible amount of 3e9
        // Remaining capacity is 7e9

        // Added capacity will be 5e9
        // New capacity will be 7e9 + 5e9 = 12e9
        // Excess capacity = 12e9 - 10e9 = 2e9
        // Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        // Because the tick price is below the minimum price, capacity is set to the tick size

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(PERIOD_MONTHS);

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickStepSame_newCapacityLessThanTickSize()
        public
        givenEnabled
        givenTickStep(100e2)
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenTickStep(100e2)
        givenDepositPeriodEnabled(PERIOD_MONTHS)
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS + 1)
        givenRecipientHasBid(270e18)
    {
        // Bid size of 270e18 results in:
        // 1. 270e18 * 1e9 / 15e18 = 18e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // This is for the other deposit asset and period
        // The current deposit asset and period has 10e9 capacity and is at the minimum price

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(
            PERIOD_MONTHS + 1
        );

        // Assert tick
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, MIN_PRICE, "new tick price");
    }

    //  given the tick capacity for the current deposit asset and period has been depleted
    //   [X] the added capacity is based on half of the target and the time passed since the last bid

    function test_givenOtherDepositAssetAndPeriodEnabled_tickCapacityDepleted()
        public
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS + 1)
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
        givenEnabled
        givenDepositPeriodEnabled(PERIOD_MONTHS)
        givenDepositPeriodEnabled(PERIOD_MONTHS + 1)
        givenRecipientHasBid(360375e15)
    {
        // Bid size of 360375e15 results in:
        // 1. 360375e15 * 1e9 / 15e18 = 24,025,000,000. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (360375e15 - 150e18) * 1e9 / 165e17 = 12,750,000,000. Greater than the tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16. Day target met, so tick size becomes 5e9.
        // 3. (360375e15 - 150e18 - 165e18) * 1e9 / 1815e16 = 25e8. Less than the tick size of 5e9.

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick(
            PERIOD_MONTHS + 1
        );

        // Assert tick
        assertEq(tick.capacity, 5e9, "new tick capacity");
        assertEq(tick.price, MIN_PRICE, "new tick price");
    }
}
