// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

contract CreateCDPOSTest is CDPOSTest {
    // when the caller is not a permissioned address
    //  [ ] it reverts
    // when the owner is the zero address
    //  [ ] it reverts
    // when the convertible deposit token is the zero address
    //  [ ] it reverts
    // when the remaining deposit is 0
    //  [ ] it reverts
    // when the conversion price is 0
    //  [ ] it reverts
    // when the expiry is in the past or now
    //  [ ] it reverts
    // when multiple positions are created
    //  [ ] the position IDs are sequential
    //  [ ] the position IDs are unique
    //  [ ] the owner's list of positions is updated
    //  [ ] the owner's balance is increased
    // when the expiry is in the future
    //  [ ] it sets the expiry
    // when the conversion would result in an overflow
    //  [ ] it reverts
    // when the conversion would result in an underflow
    //  [ ] it reverts
    // when the wrap flag is true
    //  [ ] it mints the ERC721 token
    //  [ ] it marks the position as wrapped
    // [ ] it emits a PositionCreated event
    // [ ] the position is marked as unwrapped
    // [ ] the position is listed as owned by the owner
    // [ ] the owner's list of positions is updated
    // [ ] the balance of the owner is increased
}
