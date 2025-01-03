// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerUpdatedTickTest is ConvertibleDepositAuctioneerTest {
    // given the contract has not been initialized
    //  [ ] it reverts
    // given the contract is inactive
    //  [X] it reverts
    // given a bid has never been received
    //  [X] it calculates the new capacity based on the time since contract activation
    // given less than 1 day has passed
    //  [ ] the tick capacity is unchanged
    //  [ ] the tick price is unchanged
    // when the total capacity (current tick capacity + new capacity) is equal to the tick size
    //  [ ] the tick price is unchanged
    //  [ ] the tick capacity is unchanged
    // when the total capacity is less than the tick size
    //  [ ] the tick price is unchanged
    //  [ ] the tick capacity is unchanged
    // when the total capacity is greater than the tick size
    //  given the tick step is > 1e18
    //   [ ] the tick price increases
    //  given the tick step is = 1e18
    //   [ ] the tick price is unchanged
    //  given the tick step is < 1e18
    //   when the new price is lower than the minimum price
    //    [ ] the tick price is set to the minimum price
    //    [ ] the capacity is set to the tick size
    //   [ ] it reduces the price by the tick step until the total capacity is less than the tick size
    //   [ ] the tick capacity is set to the remainder

    function test_contractInactive_reverts() public givenContractInactive {
        // Expect revert
        vm.expectRevert(IConvertibleDepositAuctioneer.CDAuctioneer_NotActive.selector);

        // Call function
        auctioneer.getUpdatedTick();
    }

    function test_noBidReceived() public givenInitialized {
        uint48 daysPassed = 2 days;

        // Warp to change the block timestamp
        vm.warp(block.timestamp + daysPassed);

        // Expected values
        // Tick size = 10e9
        // Tick step = 9e17
        // Current tick capacity = tick size = 10e9
        // Current tick price = min price = 15e18
        // New capacity added = target * days passed = 20e9 * 2 = 40e9
        // New capacity = 10e9 + 40e9 = 50e9
        // Iteration 1:
        //   New capacity = 50e9 - 10e9 = 40e9
        //   Tick price = 15e18 * 1e18 / 9e17 = 16666666666666666667 (rounded up)
        // Iteration 2:
        //   New capacity = 40e9 - 10e9 = 30e9
        //   Tick price = 16666666666666666667 * 1e18 / 9e17 = 18518518518518518519 (rounded up)
        // Iteration 3:
        //   New capacity = 30e9 - 10e9 = 20e9
        //   Tick price = 18518518518518518519 * 1e18 / 9e17 = 20576131687242798355 (rounded up)
        // Iteration 4:
        //   New capacity = 20e9 - 10e9 = 10e9
        //   Tick price = 20576131687242798355 * 1e18 / 9e17 = 22862368541380887062
        //
        // New capacity is not > tick size, so we stop
        uint256 expectedTickPrice = 22862368541380887062;
        uint256 expectedTickCapacity = 10e9;

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getUpdatedTick();

        // Assert current tick
        assertEq(tick.capacity, expectedTickCapacity, "capacity");
        assertEq(tick.price, expectedTickPrice, "price");
    }
}
