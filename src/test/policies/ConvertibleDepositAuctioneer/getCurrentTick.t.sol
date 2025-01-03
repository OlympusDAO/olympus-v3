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
    // when the total capacity (current tick capacity + new capacity) is equal to the tick size
    //  [ ] the tick price is unchanged
    //  [ ] the tick capacity is unchanged
    // when the total capacity is less than the tick size
    //  [ ] the tick price is unchanged
    //  [ ] the tick capacity is unchanged
    // when the total capacity is greater than the tick size
    //  given the tick step is = 100e2
    //   [ ] the tick price is unchanged
    //  given the tick step is > 100e2
    //   when the new price is lower than the minimum price
    //    [ ] the tick price is set to the minimum price
    //    [ ] the capacity is set to the tick size
    //   [ ] it reduces the price by the tick step until the total capacity is less than the tick size
    //   [ ] the tick capacity is set to the remainder

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

    function test_minimumPrice_sameTime(uint48 secondsPassed_) public givenInitialized {
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

    function test_minimumPrice(uint48 secondsPassed_) public givenInitialized {
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
}
