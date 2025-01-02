// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

contract ConvertibleDepositAuctioneerUpdatedTickTest is ConvertibleDepositAuctioneerTest {
    // given the initial auction parameters have not been set
    //  [X] it reverts
    // given the contract is inactive
    //  [X] it reverts
    // given a bid has never been received
    //  [ ] it calculates the new capacity based on the time since contact activation
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

    function test_invalidAuctionParameters_reverts() public givenContractActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_InvalidParams.selector,
                "auction parameters"
            )
        );

        // Call function
        auctioneer.getUpdatedTick();
    }

    function test_contractInactive_reverts() public givenContractInactive {
        // Expect revert
        vm.expectRevert(IConvertibleDepositAuctioneer.CDAuctioneer_NotActive.selector);

        // Call function
        auctioneer.getUpdatedTick();
    }

    function test_noBidReceived()
        public
        givenContractActive
        givenTickStep(TICK_STEP)
        givenTimeToExpiry(TIME_TO_EXPIRY)
        givenAuctionParametersStandard
    {
        uint48 daysPassed = 2 days;

        // Warp to change the block timestamp
        vm.warp(block.timestamp + daysPassed);

        // Expected values
        // Tick size = 10e9
        // Current tick capacity = tick size = 10e9
        // Current tick price =
        // New capacity added = target * days passed = 20e9 * 2 = 40e9
        // New capacity = 10e9 + 40e9 = 50e9
        // Iteration 1:
        //   New capacity = 50e9 - 10e9 = 40e9
        //   Tick price = 10e9 * 1e18 / 9e17 = 10e9
        // Iteration 2:
        //   New capacity = 40e9 - 10e9 = 30e9
        //   Tick price = 10e9 * 9e17 / 9e17 = 10e9
        // Iteration 3:
        //   New capacity = 30e9 - 10e9 = 20e9
        //   Tick price = 10e9 * 9e17 / 9e17 = 10e9
        // uint256 expectedCapacity = TARGET + TARGET * 2;
        // uint256 expectedPrice = expectedCapacity - TICK_SIZE

        // Call function
        IConvertibleDepositAuctioneer.Tick memory tick = auctioneer.getUpdatedTick();

        // Assertions
        assertEq(tick.capacity, TICK_SIZE);
    }
}
