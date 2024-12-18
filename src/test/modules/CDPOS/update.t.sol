// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

contract UpdateCDPOSTest is CDPOSTest {
    // when the position does not exist
    //  [ ] it reverts
    // when the caller is not the owner of the position
    //  [ ] it reverts
    // when the caller is a permissioned address
    //  [ ] it reverts
    // when the amount is 0
    //  [ ] it sets the remaining deposit to 0
    // [ ] it updates the remaining deposit
    // [ ] it emits a PositionUpdated event
}
