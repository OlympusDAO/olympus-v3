// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerUpdatedTickTest is ConvertibleDepositAuctioneerTest {
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
    //  when the new price is lower than the minimum price
    //   [ ] the tick price is set to the minimum price
    //   [ ] the capacity is set to the tick size
    //  [ ] it adjusts the price by the tick step until the total capacity is less than the tick size
    //  [ ] the tick capacity is set to the remainder
}
