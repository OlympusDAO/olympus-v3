// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13 <0.9.0;

interface IBaseSilo {
    /// @dev Storage struct that holds all required data for a single token market
    struct AssetStorage {
        /// @dev Token that represents a share in totalDeposits of Silo
        address collateralToken;
        /// @dev Token that represents a share in collateralOnlyDeposits of Silo
        address collateralOnlyToken;
        /// @dev Token that represents a share in totalBorrowAmount of Silo
        address debtToken;
        /// @dev COLLATERAL: Amount of asset token that has been deposited to Silo with interest earned by depositors.
        /// It also includes token amount that has been borrowed.
        uint256 totalDeposits;
        /// @dev COLLATERAL ONLY: Amount of asset token that has been deposited to Silo that can be ONLY used
        /// as collateral. These deposits do NOT earn interest and CANNOT be borrowed.
        uint256 collateralOnlyDeposits;
        /// @dev DEBT: Amount of asset token that has been borrowed with accrued interest.
        uint256 totalBorrowAmount;
    }

    /// @notice Get asset storage data
    /// @param _asset asset address
    /// @return AssetStorage struct
    function assetStorage(address _asset) external view returns (AssetStorage memory);
}
