// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans View Interface
/// @notice Read-only position and quote surface implemented by the lifecycle policy.
interface IBurnerLoansView is IBurnerLoans {
    /// @notice Returns the OHM debt token used by this facility.
    /// @return address The OHM token address.
    function ohm() external view returns (address);

    /// @notice Returns the OHM funding Burner Loans Inventory bound to this facility.
    /// @return address The Burner Loans Inventory address.
    function inventory() external view returns (address);

    /// @notice Returns the Burner Loans Config policy authorized to configure this facility.
    /// @return address The Burner Loans Config address.
    function configurator() external view returns (address);

    /// @notice Validates that a collateral asset is supported by this facility's dependencies.
    /// @dev Reverts when PRICE does not support the asset or the facility's Deposit Manager cannot
    ///      provide enabled custody for the Burner Loans deposit period.
    /// @param asset_ Collateral asset to validate.
    function validateAssetDependencies(address asset_) external view;

    /// @notice Returns the fixed-term loan module used by this facility.
    /// @return address The FLOAN module address.
    function floan() external view returns (address);

    /// @return Position The borrower's position for the collateral asset.
    function getPosition(address, address) external view returns (Position memory);

    /// @return address[] The active borrowers for the collateral asset.
    function getActiveBorrowers(address) external view returns (address[] memory);

    /// @return bool True when the borrower can be seized for the collateral asset.
    function isSeizable(address, address) external view returns (bool);

    /// @return SeizePreview The projected seizure result.
    function previewSeize(address, address[] calldata) external view returns (SeizePreview memory);

    /// @return address[] The seizable borrowers found in the requested scan range.
    /// @return uint256 The next borrower index to scan.
    /// @return uint256 The number of borrowers inspected.
    function getSeizableBorrowers(
        address,
        uint256,
        uint256,
        uint256
    ) external view returns (address[] memory, uint256, uint256);

    /// @return uint256 The projected collateral shares after the deposit.
    /// @return uint256 The projected health factor after the deposit.
    function previewDepositCollateral(
        address,
        uint128,
        address
    ) external view returns (uint256, uint256);

    /// @return WithdrawPreview The projected collateral withdrawal result.
    function previewWithdrawCollateral(
        address,
        uint128,
        address
    ) external view returns (WithdrawPreview memory);

    /// @return BorrowPreview The projected borrow result.
    function previewBorrow(address, uint128, address) external view returns (BorrowPreview memory);

    /// @return RepayPreview The projected repayment result.
    function previewRepay(address, uint128, address) external view returns (RepayPreview memory);

    /// @return ExtendPreview The projected extension result.
    function previewExtend(address, address, uint16) external view returns (ExtendPreview memory);

    /// @return uint256 The position health factor.
    function positionHealthFactor(address, uint256, uint256) external view returns (uint256);

    /// @return HarvestPreview The projected collateral-yield harvest result.
    function previewHarvestYield(address) external view returns (HarvestPreview memory);

    /// @return AssetCollateralStatus The collateral accounting status for the asset.
    function getAssetCollateralStatus(address) external view returns (AssetCollateralStatus memory);
}
