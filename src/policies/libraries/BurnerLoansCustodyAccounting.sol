// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

/// @title Burner Loans Custody Accounting Library
/// @notice Shared DepositManager accounting reads and shortfall validation.
library BurnerLoansCustodyAccounting {
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
