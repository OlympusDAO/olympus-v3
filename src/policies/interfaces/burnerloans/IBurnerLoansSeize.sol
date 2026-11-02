// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

/// @notice Permissionless bounded liquidation batches bound to a permanent Burner Loans Core.
interface IBurnerLoansSeize {
    /// @notice A batch is empty.
    error BurnerLoans_InvalidBatch();

    /// @notice A borrower appears more than once in a seizure batch.
    /// @param borrower Duplicated borrower address.
    error BurnerLoans_DuplicateBorrower(address borrower);

    /// @notice A borrower does not currently satisfy the seizure conditions.
    /// @param borrower Borrower that cannot be seized.
    error BurnerLoans_PositionNotSeizable(address borrower);

    /// @notice Defaults and redeems a complete batch; protocol callers receive no keeper reward.
    /// @param asset Configured underlying collateral token shared by the positions.
    /// @param borrowers Distinct nonzero accounts whose positions must all be seizable.
    /// @return token Underlying collateral or vault share token paid or recorded as pending.
    /// @return reward Token amount allocated to the caller as keeper reward.
    /// @return treasuryAmount Token amount allocated to the current Treasury.
    function seize(
        address asset,
        address[] calldata borrowers
    ) external returns (address token, uint256 reward, uint256 treasuryAmount);

    /// @notice Quotes a bounded liquidation batch for an explicit keeper.
    /// @param actor_ Keeper identity used to select protocol-caller rewards.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param borrowers_ Borrowers included in the bounded liquidation batch.
    /// @return result Batch debt/collateral, output and keeper/Treasury distribution estimates.
    function previewSeizeFor(
        address actor_,
        address asset_,
        address[] calldata borrowers_
    ) external view returns (IBurnerLoansCore.SeizePreview memory result);
}
