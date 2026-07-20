// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Lifecycle Interface
/// @notice State-changing borrower lifecycle operations.
interface IBurnerLoansLifecycle is IBurnerLoans {
    function depositCollateral(address, uint128, address) external returns (uint256, uint256);

    function withdrawCollateral(
        address,
        uint128,
        address,
        address
    ) external returns (address, uint256, uint256, uint256);

    function borrow(
        address,
        uint128,
        address,
        address,
        uint256
    ) external returns (uint256, uint256, uint256, uint48, uint256);

    function repay(address, uint128, address) external returns (uint256 healthFactor);

    function extend(
        address,
        address,
        uint16,
        uint256
    ) external returns (uint256 fee, uint48 maturity, uint256 healthFactor);

    function seize(address, address[] calldata) external returns (uint256, uint256);

    function harvestYield(address) external returns (uint256 yieldClaimed);
}
