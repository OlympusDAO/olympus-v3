// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans View Interface
/// @notice Read-only position and quote surface implemented by the lifecycle policy.
interface IBurnerLoansView is IBurnerLoans {
    function floan() external view returns (address);

    function getPosition(address, address) external view returns (Position memory);

    function getActiveBorrowers(address) external view returns (address[] memory);

    function isSeizable(address, address) external view returns (bool);

    function previewSeize(address, address[] calldata) external view returns (SeizePreview memory);

    function getSeizableBorrowers(
        address,
        uint256,
        uint256,
        uint256
    ) external view returns (address[] memory, uint256, uint256);

    function previewDepositCollateral(
        address,
        uint128,
        address
    ) external view returns (uint256, uint256);

    function previewWithdrawCollateral(
        address,
        uint128,
        address
    ) external view returns (WithdrawPreview memory);

    function previewBorrow(address, uint128, address) external view returns (BorrowPreview memory);

    function previewRepay(address, uint128, address) external view returns (RepayPreview memory);

    function previewExtend(address, address, uint16) external view returns (ExtendPreview memory);

    function positionHealthFactor(address, uint256, uint256) external view returns (uint256);

    function previewHarvestYield(address) external view returns (HarvestPreview memory);

    function getAssetCollateralStatus(address) external view returns (AssetCollateralStatus memory);
}
