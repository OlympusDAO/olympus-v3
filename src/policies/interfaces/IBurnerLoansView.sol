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

    function positionHealthFactor(address, uint256, uint256) external view returns (uint256);
}
