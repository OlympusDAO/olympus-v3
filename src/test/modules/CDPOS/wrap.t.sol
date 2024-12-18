// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

contract WrapCDPOSTest is CDPOSTest {
    // when the position does not exist
    //  [ ] it reverts
    // when the caller is not the owner of the position
    //  [ ] it reverts
    // when the caller is a permissioned address
    //  [ ] it reverts
    // when the position is already wrapped
    //  [ ] it reverts
    // [ ] it mints the ERC721 token
    // [ ] it emits a PositionWrapped event
    // [ ] the position is marked as wrapped
    // [ ] the balance of the owner is increased
    // [ ] the position is listed as owned by the owner
    // [ ] the owner's list of positions is updated
}
