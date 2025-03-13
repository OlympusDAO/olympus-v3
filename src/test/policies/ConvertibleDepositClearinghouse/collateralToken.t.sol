// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract CollateralTokenCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // [X] the collateral token is the CDEPO token

    function test_collateralToken() public {
        // Assertions
        assertEq(address(clearinghouse.collateralToken()), address(CDEPO));
    }
}
