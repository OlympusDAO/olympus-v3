// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

contract TransferFromCDPOSTest is CDPOSTest {
    // when the position does not exist
    //  [ ] it reverts
    // when the caller is not the owner of the position
    //  [ ] it reverts
    // when the caller is a permissioned address
    //  [ ] it reverts
    // [ ] it transfers the ownership of the position to the to_ address
    // [ ] it adds the position to the to_ address's list of positions
    // [ ] it removes the position from the from_ address's list of positions
}
