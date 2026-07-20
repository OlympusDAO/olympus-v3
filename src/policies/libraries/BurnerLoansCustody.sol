// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

/// @title Burner Loans Custody Library
/// @notice Separately linked DepositManager operations executed in the lifecycle's context.
/// @dev Library delegatecalls preserve BurnerLoans as the DepositManager operator and receipt holder.
library BurnerLoansCustody {
    using TransferHelper for ERC20;

    function validateCustodySupport(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        bool requireEnabledPeriod_
    ) public view returns (IDepositManager.AssetConfiguration memory assetConfiguration) {
        return
            validateCustodySupportFor(
                depositManager_,
                asset_,
                depositPeriod_,
                requireEnabledPeriod_,
                address(this)
            );
    }

    function validateCustodySupportFor(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        bool requireEnabledPeriod_,
        address operator_
    ) public view returns (IDepositManager.AssetConfiguration memory assetConfiguration) {
        try IEnabler(address(depositManager_)).isEnabled() returns (bool enabled) {
            if (!enabled) {
                revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
            }
        } catch {
            revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
        }

        assetConfiguration = depositManager_.getAssetConfiguration(IERC20(asset_));
        if (!assetConfiguration.isConfigured) {
            revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
        }

        IDepositManager.AssetPeriodStatus memory assetPeriod = depositManager_.isAssetPeriod(
            IERC20(asset_),
            depositPeriod_,
            operator_
        );
        if (!assetPeriod.isConfigured || (requireEnabledPeriod_ && !assetPeriod.isEnabled)) {
            revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
        }
    }

    function validateDepositAmount(
        IDepositManager depositManager_,
        address asset_,
        IDepositManager.AssetConfiguration memory assetConfiguration_,
        uint128 amount_
    ) public view {
        validateDepositAmountFor(
            depositManager_,
            asset_,
            assetConfiguration_,
            amount_,
            address(this)
        );
    }

    function validateDepositAmountFor(
        IDepositManager depositManager_,
        address asset_,
        IDepositManager.AssetConfiguration memory assetConfiguration_,
        uint128 amount_,
        address operator_
    ) public view {
        if (amount_ < assetConfiguration_.minimumDeposit) {
            revert IAssetManager.AssetManager_MinimumDepositNotMet(
                asset_,
                amount_,
                assetConfiguration_.minimumDeposit
            );
        }

        (, uint256 assetAmountBefore) = depositManager_.getOperatorAssets(
            IERC20(asset_),
            operator_
        );
        if (assetAmountBefore + amount_ > assetConfiguration_.depositCap) {
            revert IAssetManager.AssetManager_DepositCapExceeded(
                asset_,
                assetAmountBefore,
                assetConfiguration_.depositCap
            );
        }
    }

    function previewDepositAmount(address vault_, uint128 amount_) public view returns (uint128) {
        if (vault_ == address(0)) return amount_;
        IERC4626 vault = IERC4626(vault_);
        uint256 shares = vault.previewDeposit(amount_);
        return shares == 0 ? 0 : SafeCast.toUint128(vault.previewRedeem(shares));
    }

    function previewWithdrawAmount(address vault_, uint128 amount_) public view returns (uint256) {
        if (vault_ == address(0)) return amount_;
        IERC4626 vault = IERC4626(vault_);
        return vault.previewRedeem(vault.convertToShares(amount_));
    }

    function deposit(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint128 amount_
    ) public returns (uint128 depositedCollateral) {
        ERC20 asset = ERC20(asset_);
        uint256 startingBalance = IERC20(asset_).balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount_);
        asset.safeApprove(address(depositManager_), amount_);

        uint256 depositedCollateralRaw;
        (, depositedCollateralRaw) = depositManager_.deposit(
            IDepositManager.DepositParams({
                asset: IERC20(asset_),
                depositPeriod: depositPeriod_,
                depositor: address(this),
                amount: amount_,
                shouldWrap: false
            })
        );
        depositedCollateral = SafeCast.toUint128(depositedCollateralRaw);

        uint256 residualBalance = IERC20(asset_).balanceOf(address(this));
        if (residualBalance > startingBalance) {
            revert IBurnerLoans.BurnerLoans_ResidualCollateralBalance(
                asset_,
                residualBalance - startingBalance
            );
        }
        _approveReceiptBurn(depositManager_, asset_, depositPeriod_);
    }

    function withdraw(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint128 amount_,
        address recipient_
    ) public returns (uint256) {
        return
            depositManager_.withdraw(
                IDepositManager.WithdrawParams({
                    asset: IERC20(asset_),
                    depositPeriod: depositPeriod_,
                    depositor: address(this),
                    recipient: recipient_,
                    amount: amount_,
                    isWrapped: false
                })
            );
    }

    function _approveReceiptBurn(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_
    ) private {
        IReceiptTokenManager receiptTokenManager = depositManager_.getReceiptTokenManager();
        if (address(receiptTokenManager) == address(0)) return;

        uint256 receiptTokenId = depositManager_.getReceiptTokenId(
            IERC20(asset_),
            depositPeriod_,
            address(this)
        );
        if (
            receiptTokenManager.allowance(
                address(this),
                address(depositManager_),
                receiptTokenId
            ) !=
            type(uint256).max &&
            !receiptTokenManager.approve(
                address(depositManager_),
                receiptTokenId,
                type(uint256).max
            )
        ) {
            revert IBurnerLoans.BurnerLoans_ReceiptApprovalFailed(address(receiptTokenManager));
        }
    }
}
