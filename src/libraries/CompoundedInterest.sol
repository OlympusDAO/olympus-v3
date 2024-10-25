// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

library CompoundedInterest {
    using FixedPointMathLib for uint256;

    uint256 internal constant WAD = 1e18;

    /*
    @todo considerations:

    - taylor approx is used by Morpho, and expect it's pretty cheap for gas.
    - For Temple Line of Credit, we used a far more accurate model for continuously compounding interest 
        (and used prb-math lib to help - this is an awesome lib btw)...but would be more gas intensive.
    - Not sure it actually matters tbh - was around 3k gas from memory. But can do some quick analysis on the best approach.

    This should be doing the right thing - but need some tests obv
    */

    function continuouslyCompounded(
        uint256 principal, 
        uint256 elapsed, 
        uint96 interestRate_
    ) internal pure returns (uint256) {
        return principal + principal.mulWadDown(
            wTaylorCompounded(interestRate_, elapsed)
        );
    }

    /// @dev Returns the sum of the first three non-zero terms of a Taylor expansion of e^(nx) - 1, to approximate a
    /// continuous compound interest rate.
    function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = firstTerm.mulDivDown(firstTerm, 2 * WAD);
        uint256 thirdTerm = secondTerm.mulDivDown(firstTerm, 3 * WAD);

        return firstTerm + secondTerm + thirdTerm;
    }
}
