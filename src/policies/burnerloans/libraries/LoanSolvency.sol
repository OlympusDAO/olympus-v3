// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

/// @title Burner Loans Custody Accounting Library
/// @notice Shared DepositManager accounting reads and shortfall validation.
library LoanSolvency {
    /// @notice Requires DepositManager custody to cover the operator's liabilities.
    /// @dev Reverts if:
    ///      - DepositManager custody cannot cover the operator's liabilities.
    ///
    /// @param depositManager_ DepositManager policy to query.
    /// @param asset_ Custodied asset.
    /// @param operator_ DepositManager operator.
    function requireSolvent(
        IDepositManager depositManager_,
        address asset_,
        address operator_
    ) internal view {
        IERC20 asset = IERC20(asset_);
        // Solvency uses the asset-equivalent balance, not its underlying share count.
        // forge-lint: disable-next-line(unused-return)
        (, uint256 assets) = depositManager_.getOperatorAssets(asset, operator_);
        uint256 borrowed = depositManager_.getBorrowedAmount(asset, operator_);
        uint256 liabilities = depositManager_.getOperatorLiabilities(asset, operator_);
        if (!isSolvent(assets, borrowed, liabilities)) {
            revert IBurnerLoansCore.BurnerLoansCore_Insolvent(
                asset_,
                liabilities,
                assets,
                borrowed
            );
        }
    }

    /// @notice Returns whether custody assets and borrowing cover outstanding liabilities.
    /// @dev No external state or token calls; checked arithmetic errors propagate.
    /// @param assets_ Operator assets presently held in custody.
    /// @param borrowed_ Operator assets currently borrowed from custody.
    /// @param liabilities_ Operator collateral liabilities, in underlying units.
    /// @return bool Whether held plus borrowed assets cover the operator liabilities.
    function isSolvent(
        uint256 assets_,
        uint256 borrowed_,
        uint256 liabilities_
    ) internal pure returns (bool) {
        // Equivalent to assets + borrowed >= liabilities, without overflowing that sum. Subtract
        // only after proving assets alone do not cover liabilities, so the subtraction cannot underflow.
        return liabilities_ <= assets_ || borrowed_ >= liabilities_ - assets_;
    }
}
