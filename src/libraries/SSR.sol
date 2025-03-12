// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

library SSRLib {
    /// @notice Converts a Sky Savings Rate (SSR) to an APR
    /// @dev    Uses a fourth-order binomial expansion to approximate the compound interest formula:
    ///         APR = ((1 + x)^n - 1) * 100%, where:
    ///         - x is the per-second growth rate (SSR - 1)
    ///         - n is the number of seconds in a year
    ///         The binomial expansion used is:
    ///         (1 + x)^n ≈ 1 + nx + (n(n-1)/2)x² + (n(n-1)(n-2)/6)x³ + (n(n-1)(n-2)(n-3)/24)x⁴
    ///         Each term is calculated with 27 decimals of precision to minimize rounding errors.
    ///         The final result is rounded to the nearest basis point.
    ///
    /// @param  ssr_ The Sky Savings Rate with 27 decimals (e.g., 1000000002659864411854984565 for 8.75%)
    /// @return apr Annual interest rate in basis points where 100% = 100e2 (e.g., 875 for 8.75%)
    function ssrToApr(uint256 ssr_) public pure returns (uint16 apr) {
        // Constants
        uint256 SECONDS_PER_YEAR = 365 days; // 31536000
        uint256 SSR_PRECISION = 1e27;
        uint256 ONE_HUNDRED_PERCENT = 100e2;

        // Get the per-second rate (x) where SSR = 1 + x
        uint256 x = ssr_ - SSR_PRECISION;

        uint256 n = SECONDS_PER_YEAR;

        // Calculate terms with extra precision (1e27)
        // First term: nx
        uint256 sum = n * x;

        // Second term: (n(n-1)/2)x^2
        uint256 x_squared = (x * x) / SSR_PRECISION;
        sum += (n * (n - 1) / 2) * x_squared;

        // Third term: (n(n-1)(n-2)/6)x^3
        uint256 x_cubed = (x_squared * x) / SSR_PRECISION;
        sum += (n * (n - 1) * (n - 2) / 6) * x_cubed;

        // Fourth term: (n(n-1)(n-2)(n-3)/24)x^4
        uint256 x_fourth = (x_cubed * x) / SSR_PRECISION;
        sum += (n * (n - 1) * (n - 2) * (n - 3) / 24) * x_fourth;

        // Convert to basis points (100e2) with rounding
        sum = sum * ONE_HUNDRED_PERCENT + (SSR_PRECISION / 2);
        apr = uint16(sum / SSR_PRECISION);

        return apr;
    }
}
