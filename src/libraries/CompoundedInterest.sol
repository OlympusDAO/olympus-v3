// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {wadExp} from "solmate/utils/SignedWadMath.sol";

library CompoundedInterest {
    using FixedPointMathLib for uint256;

    uint96 internal constant ONE_YEAR = 365 days;

    /// @notice Calculate the continuously compounded interest
    /// given by: Pₜ = P₀eʳᵗ
    /// @param principal The principal amount, in 18 decimal places
    /// @param elapsedSecs The elapsed seconds
    /// @param interestRatePerYear The interest rate per year, in 18 decimal places
    function continuouslyCompounded(
        uint256 principal,
        uint256 elapsedSecs,
        uint96 interestRatePerYear
    ) internal pure returns (uint256 result) {
        return
            principal.mulWadDown(
                uint256(wadExp(int256((interestRatePerYear * elapsedSecs) / ONE_YEAR)))
            );
    }
}
