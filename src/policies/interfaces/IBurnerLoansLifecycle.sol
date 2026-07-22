// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Lifecycle Interface
/// @notice State-changing borrower lifecycle operations.
interface IBurnerLoansLifecycle is IBurnerLoans {
    /// @notice Reconciles MINTR approval to the global cap less active FLOAN principal.
    /// @dev Restricted to the `burner_loans_manager` role.
    /// @return approval Remaining bounded MINTR approval after reconciliation.
    function syncMintApproval() external returns (uint256 approval);

    /// @notice Deposits collateral into a borrower's position.
    function depositCollateral(address, uint128, address) external returns (uint256, uint256);

    /// @notice Withdraws credited collateral from a borrower's position.
    function withdrawCollateral(
        address,
        uint128,
        address,
        address
    ) external returns (address, uint256, uint256, uint256);

    /// @notice Borrows OHM against a collateral position.
    function borrow(
        address,
        uint128,
        address,
        address,
        uint256
    ) external returns (uint256, uint256, uint256, uint48, uint256);

    /// @notice Repays OHM principal for a borrower.
    function repay(address, uint128, address) external returns (uint256 healthFactor);

    /// @notice Extends an active position's maturity and charges any applicable fee.
    function extend(
        address,
        address,
        uint16,
        uint256
    ) external returns (uint256 fee, uint48 maturity, uint256 healthFactor);

    /// @notice Defaults eligible positions and routes seized collateral.
    function seize(address, address[] calldata) external returns (uint256, uint256);

    /// @notice Claims excess collateral yield for the treasury.
    function harvestYield(address) external returns (uint256 yieldClaimed);
}
