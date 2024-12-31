// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerTimeToExpiryTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "cd_admin" role
    //  [ ] it reverts
    // when the contract is deactivated
    //  [ ] it sets the time to expiry
    // [ ] it sets the time to expiry
    // [ ] it emits an event
}
