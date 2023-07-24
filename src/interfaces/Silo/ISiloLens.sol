// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13 <0.9.0;

import {IBaseSilo} from "interfaces/Silo/IBaseSilo.sol";

interface ISiloLens {
    /// @notice returns total borrow amount with interest dynamically calculated at current block timestamp
    /// @param silo_ silo address
    /// @param asset_ asset address
    /// @return totalBorrowAmount_ total deposits amount with interest
    function totalBorrowAmountWithInterest(
        IBaseSilo silo_,
        address asset_
    ) external view returns (uint256 totalBorrowAmount_);

    /// @notice returns total deposits with interest dynamically calculated at current block timestamp
    /// @param silo_ silo address
    /// @param asset_ asset address
    /// @return totalDeposits_ total deposits amount with interest
    function totalDepositsWithInterest(
        IBaseSilo silo_,
        address asset_
    ) external view returns (uint256 totalDeposits_);

    /// @notice Get underlying balance of collateral or debt token
    /// @dev You can think about debt and collateral tokens as cToken in compound. They represent ownership of
    /// debt or collateral in given Silo. This method converts that ownership to exact amount of underlying token.
    /// @param assetTotalDeposits_ Total amount of assets that has been deposited or borrowed. For collateral token,
    /// use `totalDeposits` to get this value. For debt token, use `totalBorrowAmount` to get this value.
    /// @param shareToken_ share token address. It's the collateral and debt share token address. You can find
    /// these addresses in:
    /// - `ISilo.AssetStorage.collateralToken`
    /// - `ISilo.AssetStorage.collateralOnlyToken`
    /// - `ISilo.AssetStorage.debtToken`
    /// @param user_ wallet address for which to read data
    /// @return balance_ of underlying token deposited or borrowed of given user
    function balanceOfUnderlying(
        uint256 assetTotalDeposits_,
        address shareToken_,
        address user_
    ) external view returns (uint256 balance_);
}
