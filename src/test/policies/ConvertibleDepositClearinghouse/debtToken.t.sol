// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract DebtTokenCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // [X] the debt token is the vault token

    function test_debtToken() public {
        // Assertions
        assertEq(address(clearinghouse.debtToken()), address(vault));
    }
}
