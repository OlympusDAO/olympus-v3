// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

/// @title Burner Loans Custody Accounting Library
/// @notice Shared DepositManager accounting reads and shortfall validation.
library BurnerLoansCustodyAccounting {
    /// @notice Reverts when DepositManager custody cannot cover the operator's liabilities.
    /// @dev Borrow and extension add exposure without mutating DepositManager, so its post-mutation
    ///      solvency validation does not run on those paths. Call this before either operation.
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
            revert IBurnerLoans.BurnerLoans_CustodyShortfall(asset_, liabilities, assets, borrowed);
        }
    }

    /// @notice Returns whether custody assets and borrowing cover outstanding liabilities.
    function isSolvent(
        uint256 assets_,
        uint256 borrowed_,
        uint256 liabilities_
    ) internal pure returns (bool) {
        return liabilities_ <= assets_ || borrowed_ >= liabilities_ - assets_;
    }
}
