// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

contract SplitCDPOSTest is CDPOSTest {
    // when the position does not exist
    //  [ ] it reverts
    // when the caller is not the owner of the position
    //  [ ] it reverts
    // when the caller is a permissioned address
    //  [ ] it reverts
    // when the amount is 0
    //  [ ] it reverts
    // when the amount is greater than the remaining deposit
    //  [ ] it reverts
    // when the to_ address is the zero address
    //  [ ] it reverts
    // when wrap is true
    //  [ ] it wraps the new position
    // [ ] it creates a new position with the new amount, new owner and the same expiry
    // [ ] it updates the remaining deposit of the original position
    // [ ] it emits a PositionSplit event
}
