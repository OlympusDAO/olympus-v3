// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

/// @title Burner Loans Custody Accounting Library
/// @notice Shared DepositManager accounting reads and shortfall validation.
library BurnerLoansCustodyAccounting {
    /// @notice Returns DepositManager custody accounting for an operator and asset.
    /// @param depositManager_ DepositManager policy to query.
    /// @param asset_ Custodied asset.
    /// @param operator_ DepositManager operator.
    /// @return result Shares, assets, borrowing, liabilities, yield, and solvency status.
    function status(
        IDepositManager depositManager_,
        address asset_,
        address operator_
    ) internal view returns (IBurnerLoans.AssetCollateralStatus memory result) {
        (result.shares, result.assets) = depositManager_.getOperatorAssets(
            IERC20(asset_),
            operator_
        );
        result.borrowed = depositManager_.getBorrowedAmount(IERC20(asset_), operator_);
        result.liabilities = depositManager_.getOperatorLiabilities(IERC20(asset_), operator_);
        result.solvent = _isSolvent(result.assets, result.borrowed, result.liabilities);
        result.claimableYield = depositManager_.maxClaimYield(IERC20(asset_), operator_);
    }

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
        (, uint256 assets) = depositManager_.getOperatorAssets(IERC20(asset_), operator_);
        uint256 borrowed = depositManager_.getBorrowedAmount(IERC20(asset_), operator_);
        uint256 liabilities = depositManager_.getOperatorLiabilities(IERC20(asset_), operator_);
        if (!_isSolvent(assets, borrowed, liabilities)) {
            revert IBurnerLoans.BurnerLoans_CustodyShortfall(asset_, liabilities, assets, borrowed);
        }
    }

    function _isSolvent(
        uint256 assets_,
        uint256 borrowed_,
        uint256 liabilities_
    ) private pure returns (bool) {
        return liabilities_ <= assets_ || borrowed_ >= liabilities_ - assets_;
    }
}
