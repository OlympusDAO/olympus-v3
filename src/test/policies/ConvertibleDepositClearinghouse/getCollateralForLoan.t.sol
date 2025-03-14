// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

import {console2} from "forge-std/console2.sol";

contract GetCollateralForLoanCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // when the principal is 0
    //  [X] the collateral is 0
    // when the collateral is not a whole number
    //  [X] it rounds up
    // [X] the collateral is calculated based on the debt token

    function test_zero() public {
        // Call function
        uint256 collateral = clearinghouse.getCollateralForLoan(0);

        // Assertions
        assertEq(collateral, 0, "collateral");
    }

    function test_success() public {
        // assetsPerShare = 2e18
        // principal = collateral * loanToCollateral / 1e18
        // => collateral = principal * 1e18 / loanToCollateral

        // Case 1:
        // Principal (shares) = 3e18
        // Principal (assets) = 3e18 * assetsPerShare / 1e18 = 6e18
        // Collateral = 6e18 * 1e18 / 75e16 = 8e18
        assertEq(clearinghouse.getCollateralForLoan(3e18), 8e18, "case 1");

        // Case 2:
        // Principal (shares) = 1e18
        // Principal (assets) = 1e18 * assetsPerShare / 1e18 = 2e18
        // Collateral = 2e18 * 1e18 / 75e16 = 2666666666666666667 (rounds up)
        assertEq(clearinghouse.getCollateralForLoan(1e18), 2666666666666666667, "case 2");

        // Case 3:
        // Principal (shares) = 50e18
        // Principal (assets) = 50e18 * assetsPerShare / 1e18 = 100e18
        // Collateral = 100e18 * 1e18 / 75e16 = 133333333333333333334 (rounds up)
        assertEq(clearinghouse.getCollateralForLoan(50e18), 133333333333333333334, "case 3");
    }
}
