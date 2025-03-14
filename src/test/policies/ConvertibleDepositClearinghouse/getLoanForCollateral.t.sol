// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract GetLoanForCollateralCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // when the collateral is 0
    //  [X] the principal is 0
    //  [X] the interest is 0
    // when the collateral is not a whole number
    //  [X] the principal is rounded down
    //  [X] the interest is rounded down
    // [X] the principal is in debt token terms
    // [X] the interest is in debt token terms

    function test_zero() public {
        // Call function
        (uint256 principal, uint256 interest) = clearinghouse.getLoanForCollateral(0);

        // Assertions
        assertEq(principal, 0, "principal");
        assertEq(interest, 0, "interest");
    }

    function test_success() public {
        // assetsPerShare = 2e18
        // principal = collateral * loanToCollateral / 1e18
        // interestBps = (interestRate * duration / 365 days)
        // interest = principal * interestBps / 1e18

        // interestBps = 1e16 * 121 days / 365 days = 3315068493150684.93150684931506849315068493150684932 = 3315068493150685 (rounded up)

        // Case 1:
        // collateral = 10e18
        // principal (assets) = 10e18 * 75e16 / 1e18 = 75e17
        // principal (shares) = 75e17 * 1e18 / 2e18 = 375e16
        // interest = 375e16 * 3315068493150685 / 1e18 = 12431506849315068.75 = 12431506849315069 (rounded up)
        (uint256 principal, uint256 interest) = clearinghouse.getLoanForCollateral(10e18);
        assertEq(principal, 375e16, "principal");
        assertEq(interest, 12431506849315069, "interest");

        // Case 2:
        // collateral = 95e17
        // principal (assets) = 95e17 * 75e16 / 1e18 = 7125e15
        // principal (shares) = 7125e15 * 1e18 / 2e18 = 35625e14
        // interest = 35625e14 * 3315068493150685 / 1e18 = 11809931506849315.3125 = 11809931506849316 (rounded up)
        (uint256 principalTwo, uint256 interestTwo) = clearinghouse.getLoanForCollateral(95e17);
        assertEq(principalTwo, 35625e14, "principalTwo");
        assertEq(interestTwo, 11809931506849316, "interestTwo");

        // Case 3:
        // collateral = 987654321
        // principal (assets) = 987654321 * 75e16 / 1e18 = 740740740.75 = 740740740 (rounded down)
        // principal (shares) = 740740740 * 1e18 / 2e18 = 370370370
        // interest = 370370370 * 3315068493150685 / 1e18 = 1227803.1443835617 = 1227804 (rounded up)
        (uint256 principalThree, uint256 interestThree) = clearinghouse.getLoanForCollateral(
            987654321
        );
        assertEq(principalThree, 370370370, "principalThree");
        assertEq(interestThree, 1227804, "interestThree");

        // Case 4:
        // collateral = 2666666666666666666
        // principal (assets) = 2666666666666666666 * 75e16 / 1e18 = 1999999999999999999.5 = 2000000000000000000 (rounded up)
        // principal (shares) = 2000000000000000000 * 1e18 / 2e18 = 1000000000000000000
        // interest = 1000000000000000000 * 3315068493150685 / 1e18 = 3315068493150685
        (uint256 principalFour, uint256 interestFour) = clearinghouse.getLoanForCollateral(
            2666666666666666666
        );
        assertEq(principalFour, 1000000000000000000, "principalFour");
        assertEq(interestFour, 3315068493150685, "interestFour");
    }
}
