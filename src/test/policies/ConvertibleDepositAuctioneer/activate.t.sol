// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerActivateTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "emergency_shutdown" role
    //  [ ] it reverts
    // when the contract is already activated
    //  [ ] the state is unchanged
    //  [ ] it does not emit an event
    // when the contract is not activated
    //  [ ] it activates the contract
    //  [ ] it emits an event
}
