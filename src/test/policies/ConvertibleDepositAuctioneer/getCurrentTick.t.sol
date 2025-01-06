// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerCurrentTickTest is ConvertibleDepositAuctioneerTest {
    // given the contract has not been initialized
    //  [X] it reverts
    // given the contract is inactive
    //  [X] it reverts
    // given a bid has never been received and the tick price is at the minimum price
    //  given no time has passed
    //   [X] the tick capacity remains at the tick size
    //   [X] the tick price remains at the min price
    //  [X] the tick capacity remains at the tick size
    //  [X] the tick price remains at the min price
    // when the new capacity (current tick capacity + added capacity) is equal to the tick size
    //  [X] the tick price is unchanged
    //  [X] the tick capacity is the tick size
    // when the new capacity is less than the tick size
    //  [X] the tick price is unchanged
    //  [X] the tick capacity is the new capacity
    // when the new capacity is greater than the tick size
    //  given the tick step is = 100e2
    //   [X] the tick price is unchanged
    //   [X] the tick capacity is the new capacity
    //  given the tick step is > 100e2
    //   when the new price is lower than the minimum price
    //    [X] the tick price is set to the minimum price
    //    [X] the capacity is set to the tick size
    //   [X] it reduces the price by the tick step until the total capacity is less than the tick size
    //   [X] the tick capacity is set to the remainder

    function test_contractNotInitialized_reverts() public {
        // Expect revert
        vm.expectRevert(IConvertibleDepositAuctioneer.CDAuctioneer_NotActive.selector);

        // Call function
        auctioneer.getCurrentTick();
    }

    function test_contractInactive_reverts() public givenInitialized givenContractInactive {
        // Expect revert
        vm.expectRevert(IConvertibleDepositAuctioneer.CDAuctioneer_NotActive.selector);

        // Call function
        auctioneer.getCurrentTick();
    }

    function test_fullCapacity_sameTime(uint48 secondsPassed_) public givenInitialized {
        uint48 secondsPassed = uint48(bound(secondsPassed_, 0, 86400 - 1));

        // Warp to change the block timestamp
        vm.warp(block.timestamp + secondsPassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        uint256 expectedTickPrice = 15e18;
        uint256 expectedTickCapacity = 10e9;

        // Assert current tick
        assertEq(tick.capacity, expectedTickCapacity, "capacity");
        assertEq(tick.price, expectedTickPrice, "price");
    }

    function test_fullCapacity(uint48 secondsPassed_) public givenInitialized {
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
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert current tick
        assertEq(tick.capacity, expectedTickCapacity, "capacity");
        assertEq(tick.price, expectedTickPrice, "price");
    }

    function test_newCapacityEqualToTickSize() public givenInitialized givenRecipientHasBid(75e18) {
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
        assertEq(auctioneer.getCurrentTick().capacity, 5e9, "previous tick capacity");

        // Assert that the time passed will result in the correct capacity
        uint48 timePassed = 21600;
        assertEq(
            (auctioneer.getState().target * timePassed) / 1 days,
            5e9,
            "expected new capacity"
        );

        // Warp forward
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_newCapacityLessThanTickSize()
        public
        givenInitialized
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
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 9e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_newCapacityGreaterThanTickSize()
        public
        givenInitialized
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
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickStepSame_newCapacityGreaterThanTickSize()
        public
        givenInitialized
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
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 2e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickStepSame_newCapacityLessThanTickSize()
        public
        givenInitialized
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
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 75e8, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickStepSame_newCapacityEqualToTickSize()
        public
        givenInitialized
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
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }

    function test_tickPriceAboveMinimum_newCapacityGreaterThanTickSize()
        public
        givenInitialized
        givenRecipientHasBid(330e18)
    {
        // Bid size of 330e18 results in:
        // 1. 330e18 * 1e9 / 15e18 = 22e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (330e18 - 150e18) * 1e9 / 165e17 = 10,909,090,909. Greater than tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16
        // 3. (330e18 - 150e18 - 165e18) * 1e9 / 1815e16 = 826,446,280
        // Remaining capacity is 10e9 - 826,446,280 = 9,173,553,720

        // Added capacity will be 5e9
        // New capacity will be 9,173,553,720 + 5e9 = 14,173,553,720

        // Calculate the expected tick price
        // Excess capacity = 14,173,553,720 - 10e9 = 4,173,553,720
        // Tick price = 165e17

        // Warp forward
        uint48 timePassed = 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 4173553720, "new tick capacity");
        assertEq(tick.price, 165e17, "new tick price");
    }

    function test_tickPriceAboveMinimum_newPriceBelowMinimum()
        public
        givenInitialized
        givenRecipientHasBid(330e18)
    {
        // Bid size of 330e18 results in:
        // 1. 330e18 * 1e9 / 15e18 = 22e9. Greater than tick size of 10e9. Bid amount becomes 150e18. New price is 15e18 * 110e2 / 100e2 = 165e17
        // 2. (330e18 - 150e18) * 1e9 / 165e17 = 10,909,090,909. Greater than tick size of 10e9. Bid amount becomes 165e18. New price is 165e17 * 110e2 / 100e2 = 1815e16
        // 3. (330e18 - 150e18 - 165e18) * 1e9 / 1815e16 = 826,446,280
        // Remaining capacity is 10e9 - 826,446,280 = 9,173,553,720

        // Added capacity will be 25e9
        // New capacity will be 9,173,553,720 + 25e9 = 34,173,553,720

        // Calculate the expected tick price
        // 1. Excess capacity = 34,173,553,720 - 10e9 = 24,173,553,720
        //    Tick price = 165e17
        // 2. Excess capacity = 24,173,553,720 - 10e9 = 14,173,553,720
        //    Tick price = 165e17 * 100e2 / 110e2 = 15e18
        // 3. Excess capacity = 14,173,553,720 - 10e9 = 4,173,553,720
        //    Tick price = 15e18 * 100e2 / 110e2 = 13636363636363636364
        //    Tick price is below the minimum price, so it is set to the minimum price
        //    New capacity = tick size = 10e9

        // Warp forward
        uint48 timePassed = 5 * 21600;
        vm.warp(block.timestamp + timePassed);

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getCurrentTick();

        // Assert tick capacity
        assertEq(tick.capacity, 10e9, "new tick capacity");
        assertEq(tick.price, 15e18, "new tick price");
    }
}
