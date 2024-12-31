// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";

contract ConvertibleDepositAuctioneerDeactivateTest is ConvertibleDepositAuctioneerTest {
    // when the caller does not have the "emergency_shutdown" role
    //  [ ] it reverts
    // when the contract is already deactivated
    //  [ ] the state is unchanged
    //  [ ] it does not emit an event
    // when the contract is active
    //  [ ] it deactivates the contract
    //  [ ] it emits an event
}
