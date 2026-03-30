// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title IAaveV3DataProvider
/// @notice Minimal Aave V3 data provider interface for reserve-level user balances
interface IAaveV3DataProvider {
    /// @notice Returns per-reserve user position data
    /// @param asset The reserve asset address
    /// @param user The user address
    /// @return currentATokenBalance The user's aToken balance for the reserve
    /// @return currentStableDebt The user's stable debt balance for the reserve
    /// @return currentVariableDebt The user's variable debt balance for the reserve
    /// @return principalStableDebt The user's principal stable debt
    /// @return scaledVariableDebt The user's scaled variable debt
    /// @return stableBorrowRate The user's stable borrow rate
    /// @return liquidityRate The reserve liquidity rate
    /// @return stableRateLastUpdated Last timestamp stable rate was updated
    /// @return usageAsCollateralEnabled Whether reserve is enabled as collateral
    function getUserReserveData(
        address asset,
        address user
    )
        external
        view
        returns (
            uint256 currentATokenBalance,
            uint256 currentStableDebt,
            uint256 currentVariableDebt,
            uint256 principalStableDebt,
            uint256 scaledVariableDebt,
            uint256 stableBorrowRate,
            uint256 liquidityRate,
            uint40 stableRateLastUpdated,
            bool usageAsCollateralEnabled
        );
}
