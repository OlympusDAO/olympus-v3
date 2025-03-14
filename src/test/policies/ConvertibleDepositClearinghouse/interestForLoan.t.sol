// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract InterestForLoanCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // when the principal is 0
    //  [X] the interest is 0
    // when the principal is not a whole number
    //  [X] the interest is rounded up
    // [X] the interest is in debt token terms

    function test_zero() public {
        // Call function
        uint256 interest = clearinghouse.interestForLoan(0, DURATION);

        // Assertions
        assertEq(interest, 0, "interest");
    }

    function test_success() public {
        // interestBps = (interestRate * duration / 365 days)
        // interest = principal * interestBps / 100e2

        // interestBps = 1e16 * 121 days / 365 days = 3315068493150684.93150684931506849315068493150684932 = 3315068493150685 (rounded up)

        // Case 1:
        // principal = 10e18
        // interest = 10e18 * 3315068493150685 / 1e18 = 33150684931506850
        uint256 interest = clearinghouse.interestForLoan(10e18, DURATION);
        assertEq(interest, 33150684931506850, "interest");

        // Case 2:
        // principal = 95e17
        // interest = 95e17 * 3315068493150685 / 1e18 = 31493150684931507.5 = 31493150684931508 (rounded up)
        uint256 interestTwo = clearinghouse.interestForLoan(95e17, DURATION);
        assertEq(interestTwo, 31493150684931508, "interestTwo");

        // Case 3:
        // principal = 987654321
        // interest = 987654321 * 3315068493150685 / 1e18 = 3274141.7216712329 = 3274142 (rounded up)
        uint256 interestThree = clearinghouse.interestForLoan(987654321, DURATION);
        assertEq(interestThree, 3274142, "interestThree");
    }
}
