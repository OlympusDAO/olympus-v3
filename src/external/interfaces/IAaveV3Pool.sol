// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title IAaveV3Pool
/// @notice Aave V3 Pool interface for supply/borrow operations
interface IAaveV3Pool {
    /// @notice Supplies an asset to the pool
    /// @param asset The address of the underlying asset to supply
    /// @param amount The amount to be supplied
    /// @param onBehalfOf The address that will receive the aToken
    /// @param referralCode Code used to register the integrator originating the operation
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Deposits an asset to the pool (alias for supply, for backwards compatibility)
    /// @param asset The address of the underlying asset to deposit
    /// @param amount The amount to be deposited
    /// @param onBehalfOf The address that will receive the aToken
    /// @param referralCode Code used to register the integrator originating the operation
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Borrows an asset from the pool
    /// @param asset The address of the underlying asset to borrow
    /// @param amount The amount to be borrowed
    /// @param interestRateMode The interest rate mode: 1 for stable, 2 for variable
    /// @param referralCode Code used to register the integrator originating the operation
    /// @param onBehalfOf Address of the user who will receive the debt
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    /// @notice Withdraws an asset from the pool
    /// @param asset The address of the underlying asset to withdraw
    /// @param amount The underlying amount to be withdrawn
    /// @param to The address that will receive the underlying
    /// @return The final amount withdrawn
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /// @notice Repays a borrowed asset
    /// @param asset The address of the underlying borrowed asset
    /// @param amount The amount to repay
    /// @param interestRateMode The interest rate mode: 1 for stable, 2 for variable
    /// @param onBehalfOf The address of the user who will get his debt reduced/removed
    /// @return The final amount repaid
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);

    /// @notice Gets user account data across all reserves
    /// @param user The address of the user
    /// @return totalCollateralBase The total collateral of the user in the base currency
    /// @return totalDebtBase The total debt of the user in the base currency
    /// @return availableBorrowsBase The borrowing power left of the user in the base currency
    /// @return currentLiquidationThreshold The liquidation threshold of the user
    /// @return ltv The loan to value of the user
    /// @return healthFactor The current health factor of the user
    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /// @notice Returns the configuration bitmap of the reserve
    /// @param asset The address of the underlying asset of the reserve
    /// @return The configuration bitmap (decode LTV from bits 0-15)
    function getConfiguration(address asset) external view returns (uint256);

    /// @notice Returns the normalized income of the reserve
    /// @param asset The address of the underlying asset of the reserve
    /// @return The reserve's normalized income
    function getReserveNormalizedIncome(address asset) external view returns (uint256);

    /// @notice Returns the normalized variable debt per unit of asset
    /// @param asset The address of the underlying asset of the reserve
    /// @return The reserve normalized variable debt
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);

    /// @notice Sets the asset of msg.sender to be used as collateral
    /// @param asset The address of the underlying asset
    /// @param useAsCollateral True if the asset should be used as collateral
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    /// @notice Sets the eMode category for the user
    /// @param categoryId The eMode category id (0 to disable)
    function setUserEMode(uint8 categoryId) external;

    /// @notice Returns the eMode category id for the user
    /// @param user The address of the user
    /// @return The eMode category id (0 if no eMode set)
    function getUserEMode(address user) external view returns (uint256);

    /// @notice Returns eMode category data
    /// @param id The eMode category id
    /// @return ltv The loan to value for the category
    /// @return liquidationThreshold The liquidation threshold for the category
    /// @return liquidationBonus The liquidation bonus for the category
    /// @return priceSource The address of the price source
    /// @return label The label of the category
    function getEModeCategoryData(
        uint8 id
    )
        external
        view
        returns (
            uint16 ltv,
            uint16 liquidationThreshold,
            uint16 liquidationBonus,
            address priceSource,
            string memory label
        );
}
