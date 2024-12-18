// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

contract UnwrapCDPOSTest is CDPOSTest {
    // when the position does not exist
    //  [ ] it reverts
    // when the caller is not the owner of the position
    //  [ ] it reverts
    // when the caller is a permissioned address
    //  [ ] it reverts
    // when the position is not wrapped
    //  [ ] it reverts
    // [ ] it burns the ERC721 token
    // [ ] it emits a PositionUnwrapped event
    // [ ] the position is marked as unwrapped
    // [ ] the balance of the owner is decreased
    // [ ] the position is listed as owned by the owner
    // [ ] the owner's list of positions is updated
}
