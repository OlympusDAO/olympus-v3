// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansContext, IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCustodyAccounting} from "src/policies/libraries/BurnerLoansCustodyAccounting.sol";
import {BurnerLoansDependencies} from "src/policies/libraries/BurnerLoansDependencies.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";
import {BurnerLoansQuote} from "src/policies/libraries/BurnerLoansQuote.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";

// Contracts
import {Policy} from "src/Kernel.sol";

/// @title Burner Loans Custody Library
/// @notice Separately linked DepositManager operations executed in the lifecycle's context.
/// @dev Library delegatecalls preserve BurnerLoans as the DepositManager operator and receipt holder.
library BurnerLoansCustody {
    using EnumerableSet for EnumerableSet.AddressSet;
    using TransferHelper for ERC20;

    /// @dev Fixed-point scale used for withdrawal health validation.
    uint256 private constant _WAD = 1e18;

    /// @notice Parameters for executing a borrow.
    struct BorrowParams {
        uint32 marketId;
        address asset;
        address onBehalfOf;
        address recipient;
        uint128 ohmAmount;
        uint256 maxFee;
    }

    /// @notice Parameters for executing a collateral withdrawal.
    struct WithdrawParams {
        uint32 marketId;
        address asset;
        address onBehalfOf;
        address recipient;
        uint128 amount;
    }

    /// @notice Quotes and executes a borrow against the first borrower position.
    /// @dev Reverts if:
    ///      - Burner Loans Inventory is not an active and enabled policy.
    ///      - The caller is unauthorized, `recipient_` is zero, or the asset market or borrower
    ///        position is unavailable.
    ///      - The amount, maturity, PRICE data, backing value, debt caps, or health bounds are
    ///        invalid.
    ///      - The quoted fee exceeds `maxFee_` or the fee transfer fails.
    ///      - FLOAN debt mutation or Inventory funding fails.
    /// @return borrowedOhm Amount of OHM borrowed.
    /// @return fee Collateral fee charged.
    /// @return resultingDebtOhm Position debt after the borrow.
    /// @return maturity Position maturity after the borrow.
    /// @return resultingHealthFactor Position health factor after the borrow.
    function borrow(
        address asset_,
        address onBehalfOf_,
        address recipient_,
        uint128 ohmAmount_,
        uint256 maxFee_
    )
        public
        returns (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 resultingDebtOhm,
            uint48 maturity,
            uint256 resultingHealthFactor
        )
    {
        BurnerLoansContext memory dependencies_ = _dependencies();
        if (
            !Policy(address(this)).kernel().isPolicyActive(Policy(address(dependencies_.inventory)))
        ) {
            revert IBurnerLoans.BurnerLoans_InventoryNotActive(address(dependencies_.inventory));
        }
        _requireSenderAuthorized(onBehalfOf_);
        if (recipient_ == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        BorrowParams memory params_;
        params_.marketId = BurnerLoansMarketConfig.firstMarketId(
            dependencies_.floan,
            address(this),
            asset_,
            address(dependencies_.ohm)
        );
        params_.asset = asset_;
        params_.onBehalfOf = onBehalfOf_;
        params_.recipient = recipient_;
        params_.ohmAmount = ohmAmount_;
        params_.maxFee = maxFee_;
        (, uint64 positionId, IFLOANv1.Position memory position) = BurnerLoansPositions
            .getWithIdOrEmpty(dependencies_.floan, params_.marketId, params_.onBehalfOf);
        IBurnerLoans.BorrowPreview memory preview = BurnerLoansQuote.quoteBorrow(
            dependencies_,
            params_.asset,
            params_.ohmAmount,
            position
        );
        if (preview.fee > params_.maxFee) {
            revert IBurnerLoans.BurnerLoans_FeeExceedsMax(preview.fee, params_.maxFee);
        }

        // FLOAN is the authoritative position ledger. Use the state returned by the mutation for
        // action outputs rather than assuming the pre-call quote became the stored result.
        IFLOANv1.Position memory resultingPosition = dependencies_.floan.increaseDebt(
            positionId,
            params_.ohmAmount,
            0,
            preview.maturity
        );
        if (preview.fee != 0) {
            // Asset admission already requires exact transfer semantics during collateral deposit.
            // Avoid two balance reads on every fee payment for the same admitted token property.
            ERC20(params_.asset).safeTransferFrom(
                msg.sender,
                address(dependencies_.treasury),
                preview.fee
            );
        }
        dependencies_.inventory.draw(params_.recipient, params_.ohmAmount);

        uint256 healthFactor = BurnerLoansQuote.positionHealthFactor(
            dependencies_,
            params_.asset,
            resultingPosition.collateral,
            resultingPosition.principalDue
        );

        emit IBurnerLoans.Borrowed(
            msg.sender,
            params_.asset,
            params_.onBehalfOf,
            params_.recipient,
            params_.ohmAmount,
            preview.fee
        );
        return (
            params_.ohmAmount,
            preview.fee,
            resultingPosition.principalDue,
            resultingPosition.maturity,
            healthFactor
        );
    }

    /// @notice Deposits collateral into custody and credits the borrower position.
    /// @dev Reverts if:
    ///      - The asset market is unavailable or originations are disabled.
    ///      - The amount is zero, below the DepositManager minimum, or exceeds its operator cap.
    ///      - The caller is unauthorized or DepositManager has no enabled custody period.
    ///      - The incoming transfer or DepositManager receipt is inexact, custody retains a
    ///        residual balance, or ERC-4626 rounding produces zero credit.
    ///      - FLOAN position creation or collateral mutation fails.
    /// @return depositedCollateral Actual collateral credited after vault rounding.
    /// @return totalCollateral Resulting position collateral.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) public returns (uint256 depositedCollateral, uint256 totalCollateral) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        uint32 marketId_ = _requireAssetOriginationsEnabled(dependencies_, asset_);
        if (amount_ == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();
        _requireSenderAuthorized(onBehalfOf_);
        IDepositManager.AssetConfiguration memory assetConfiguration = validateCustodySupportFor(
            dependencies_.depositManager,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            true,
            address(this)
        );
        validateDepositAmountFor(
            dependencies_.depositManager,
            asset_,
            assetConfiguration,
            amount_,
            address(this)
        );

        uint128 depositedCollateral_ = deposit(
            dependencies_.depositManager,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            amount_
        );
        if (depositedCollateral_ == 0) revert IBurnerLoans.BurnerLoans_ZeroCollateralCredit();
        uint64 positionId = BurnerLoansPositions.getOrCreate(
            dependencies_.floan,
            marketId_,
            onBehalfOf_
        );
        uint128 totalCollateral_ = dependencies_.floan.addCollateral(
            positionId,
            depositedCollateral_
        );

        emit IBurnerLoans.CollateralDeposited(
            msg.sender,
            asset_,
            onBehalfOf_,
            amount_,
            depositedCollateral_
        );
        return (depositedCollateral_, totalCollateral_);
    }

    /// @notice Validates and executes a collateral withdrawal.
    /// @dev Debits the requested collateral credit and returns DepositManager's nonzero actual
    ///      output, which may be lower because ERC-4626 conversion rounds down. Reverts if:
    ///      - The asset market or custody period is unavailable, or DepositManager is disabled.
    ///      - The caller is unauthorized, `recipient_` is zero, or `amount_` is zero or exceeds
    ///        credited collateral.
    ///      - The resulting indebted position is unhealthy or custody returns zero assets.
    ///      - FLOAN collateral mutation or DepositManager withdrawal fails.
    /// @return tokenOut Collateral token returned.
    /// @return amountOut Actual amount returned after vault conversion.
    /// @return remainingCollateral Resulting credited collateral.
    /// @return healthFactor Resulting position health factor.
    function withdrawCollateral(
        address asset_,
        address onBehalfOf_,
        address recipient_,
        uint128 amount_
    )
        public
        returns (
            address tokenOut,
            uint256 amountOut,
            uint256 remainingCollateral,
            uint256 healthFactor
        )
    {
        BurnerLoansContext memory dependencies_ = _dependencies();
        (uint32 marketId_, ) = _getAssetMarket(dependencies_, asset_);
        _requireSenderAuthorized(onBehalfOf_);
        WithdrawParams memory params_ = WithdrawParams({
            marketId: marketId_,
            asset: asset_,
            onBehalfOf: onBehalfOf_,
            recipient: recipient_,
            amount: amount_
        });
        if (params_.amount == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();
        if (params_.recipient == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        validateCustodySupportFor(
            dependencies_.depositManager,
            params_.asset,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            false,
            address(this)
        );
        (, uint64 positionId, IFLOANv1.Position memory position) = BurnerLoansPositions
            .getWithIdOrEmpty(dependencies_.floan, params_.marketId, params_.onBehalfOf);
        if (params_.amount > position.collateral) {
            revert IBurnerLoans.BurnerLoans_InsufficientCollateral(
                params_.amount,
                position.collateral
            );
        }
        // Debit FLOAN before calculating action outputs so the returned collateral is the module's
        // authoritative value. Any later health or custody failure reverts this mutation atomically.
        remainingCollateral = dependencies_.floan.removeCollateral(positionId, params_.amount);
        healthFactor = BurnerLoansQuote.positionHealthFactor(
            dependencies_,
            params_.asset,
            remainingCollateral,
            position.principalDue
        );
        if (position.principalDue != 0 && healthFactor < _WAD) {
            revert IBurnerLoans.BurnerLoans_UnhealthyWithdrawal(healthFactor);
        }

        amountOut = withdraw(
            dependencies_.depositManager,
            params_.asset,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            params_.amount,
            params_.recipient
        );
        if (amountOut == 0) {
            revert IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal();
        }
        emit IBurnerLoans.CollateralWithdrawn(
            msg.sender,
            params_.asset,
            params_.onBehalfOf,
            params_.recipient,
            params_.amount
        );
        tokenOut = params_.asset;
    }

    /// @notice Validates custody support for an explicit operator.
    /// @dev Reverts with `BurnerLoans_InvalidDepositManager` when the manager, asset, or period is
    ///      unavailable.
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

    /// @notice Validates a deposit amount for an explicit operator.
    /// @dev Reverts when the amount is below the minimum or would exceed the operator deposit cap.
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

    /// @notice Quotes withdrawable collateral credited by a vault deposit.
    /// @param vault_ ERC-4626 vault, or zero for direct custody.
    /// @param amount_ Underlying amount supplied.
    /// @return Actual withdrawable credit, rounded according to the vault.
    function previewDepositAmount(address vault_, uint128 amount_) public view returns (uint128) {
        if (vault_ == address(0)) return amount_;
        IERC4626 vault = IERC4626(vault_);
        uint256 shares = vault.previewDeposit(amount_);
        return shares == 0 ? 0 : SafeCast.toUint128(vault.previewRedeem(shares));
    }

    /// @notice Quotes vault assets returned for a requested collateral debit.
    /// @param vault_ ERC-4626 vault, or zero for direct custody.
    /// @param amount_ Credited collateral amount.
    /// @return Actual underlying amount returned by the vault.
    function previewWithdrawAmount(address vault_, uint256 amount_) public view returns (uint256) {
        if (vault_ == address(0)) return amount_;
        IERC4626 vault = IERC4626(vault_);
        return vault.previewRedeem(vault.convertToShares(amount_));
    }

    /// @notice Transfers collateral into DepositManager custody.
    /// @dev Reverts on inexact receipt from the caller, DepositManager's exact-receipt rejection,
    ///      residual collateral, receipt approval failure, or another DepositManager error.
    /// @return depositedCollateral Actual collateral credited after vault rounding.
    function deposit(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint128 amount_
    ) public returns (uint128 depositedCollateral) {
        ERC20 asset = ERC20(asset_);
        uint256 startingBalance = asset.safeTransferFromExact(msg.sender, address(this), amount_);
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

        // IDepositManager permits different implementations and does not guarantee that a
        // successful call consumes the full requested amount. Do not credit collateral while
        // retaining any part of the user's transfer in Burner Loans.
        uint256 residualBalance = IERC20(asset_).balanceOf(address(this));
        if (residualBalance > startingBalance) {
            revert IBurnerLoans.BurnerLoans_ResidualCollateralBalance(
                asset_,
                residualBalance - startingBalance
            );
        }
        _approveReceiptBurn(depositManager_, asset_, depositPeriod_);
    }

    /// @notice Withdraws collateral from DepositManager custody.
    /// @dev Reverts with the underlying DepositManager error when withdrawal is unavailable.
    /// @return Actual amount transferred to the recipient.
    function withdraw(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint256 amount_,
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

    /// @notice Returns validated custody accounting for an asset and operator.
    /// @dev Reverts when custody support is invalid.
    function getAssetCollateralStatus(
        IDepositManager depositManager_,
        address asset_,
        address operator_
    ) public view returns (IBurnerLoans.AssetCollateralStatus memory) {
        validateCustodySupportFor(
            depositManager_,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            false,
            operator_
        );
        return BurnerLoansCustodyAccounting.status(depositManager_, asset_, operator_);
    }

    /// @notice Claims and distributes solvent custody yield for every registered asset atomically.
    /// @dev Reverts on invalid custody, insolvency, invalid recipient routing, or transfer failure
    ///      for any registered asset.
    function claimYield(
        EnumerableSet.AddressSet storage assets_,
        BurnerLoansDependencies.YieldRoutingState storage routing_
    ) public {
        uint256 assetCount = assets_.length();
        address recipient = routing_.recipient;
        for (uint256 i; i < assetCount; ++i) {
            address asset = assets_.at(i);
            _claimYield(asset, recipient, routing_.assetBps[asset]);
        }
    }

    /// @notice Claims and distributes solvent custody yield for one registered asset.
    /// @dev Reverts on invalid custody, insolvency, invalid recipient routing, or transfer failure.
    function _claimYield(
        address asset_,
        address recipient_,
        uint16 bps_
    ) private returns (uint256 claimed) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        IBurnerLoans.AssetCollateralStatus memory collateralStatus = getAssetCollateralStatus(
            dependencies_.depositManager,
            asset_,
            address(this)
        );
        if (!collateralStatus.solvent) {
            revert IBurnerLoans.BurnerLoans_CustodyShortfall(
                asset_,
                collateralStatus.liabilities,
                collateralStatus.assets,
                collateralStatus.borrowed
            );
        }
        if (bps_ != 0) {
            BurnerLoansDependencies.validateYieldRecipientAsset(
                Policy(address(this)).kernel(),
                dependencies_.depositManager,
                recipient_,
                asset_
            );
        }

        uint256 requestedAmount = collateralStatus.claimableYield;
        if (requestedAmount == 0) return 0;

        claimed = dependencies_.depositManager.claimYield(
            IERC20(asset_),
            address(this),
            requestedAmount
        );

        // claimed (asset decimals) * bps (4 decimals) / 10_000 (4 decimals)
        // = recipientAmount (asset decimals), rounded down in favor of TRSRY.
        uint256 recipientAmount = FullMath.mulDiv(claimed, bps_, BurnerLoansConstants.MAX_BPS);
        uint256 treasuryAmount = claimed - recipientAmount;
        if (recipientAmount != 0) ERC20(asset_).safeTransfer(recipient_, recipientAmount);
        if (treasuryAmount != 0) {
            ERC20(asset_).safeTransfer(dependencies_.treasury, treasuryAmount);
        }

        emit IBurnerLoans.YieldClaimed(
            asset_,
            recipient_,
            claimed,
            recipientAmount,
            treasuryAmount
        );
    }

    /// @notice Quotes claimable yield and validates current custody and routing state.
    /// @dev Reverts when custody or a nonzero recipient route is invalid.
    function previewClaimYield(
        address asset_,
        address recipient_,
        uint16 bps_
    ) public view returns (IBurnerLoans.ClaimYieldPreview memory preview) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        IBurnerLoans.AssetCollateralStatus memory collateralStatus = getAssetCollateralStatus(
            dependencies_.depositManager,
            asset_,
            address(this)
        );
        preview.amount = collateralStatus.claimableYield;
        preview.executable = collateralStatus.solvent;
        if (preview.executable && bps_ != 0) {
            BurnerLoansDependencies.validateYieldRecipientAsset(
                Policy(address(this)).kernel(),
                dependencies_.depositManager,
                recipient_,
                asset_
            );
        }
    }

    /// @notice Repays principal and transfers exact OHM to Burner Loans Inventory for settlement.
    /// @dev Reverts for a missing/debt-free position, excessive or same-block repayment, token
    ///      transfer failure, inexact Burner Loans Inventory receipt, or an underlying
    ///      FLOAN/Burner Loans Inventory failure.
    /// @return remainingDebtOhm Principal stored by FLOAN after repayment.
    /// @return healthFactor Max uint after full repayment; zero when debt remains because repayment
    ///         deliberately avoids a live PRICE read.
    function repay(
        uint32 marketId_,
        address asset_,
        address onBehalfOf_,
        uint128 repayOhm_
    ) public returns (uint256 remainingDebtOhm, uint256 healthFactor) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        if (!IEnabler(address(dependencies_.inventory)).isEnabled()) revert IEnabler.NotEnabled();
        (bool exists, uint64 positionId) = BurnerLoansPositions.find(
            dependencies_.floan,
            marketId_,
            onBehalfOf_
        );
        if (!exists) revert IBurnerLoans.BurnerLoans_NoCollateral();

        IFLOANv1.Position memory position = dependencies_.floan.getPosition(positionId);
        uint256 debtOhm = position.principalDue;
        if (debtOhm == 0) revert IBurnerLoans.BurnerLoans_NoDebt();
        if (repayOhm_ > debtOhm) {
            revert IBurnerLoans.BurnerLoans_RepayExceedsDebt(repayOhm_, debtOhm);
        }
        if (block.number <= position.lastBorrowBlock) {
            revert IBurnerLoans.BurnerLoans_SameBlockRepay(position.lastBorrowBlock);
        }
        // FLOAN returns the stored post-repayment position; use it for events and return values.
        IFLOANv1.Position memory resultingPosition = dependencies_.floan.decreaseDebt(
            positionId,
            repayOhm_,
            0
        );
        // Pull repayment OHM directly from the payer into Burner Loans Inventory. Burner Loans
        // never takes temporary custody and records settlement only after exact receipt.
        ERC20(address(dependencies_.ohm)).safeTransferFromExact(
            msg.sender,
            address(dependencies_.inventory),
            repayOhm_
        );
        dependencies_.inventory.settleRepayment(repayOhm_);

        emit IBurnerLoans.Repaid(
            msg.sender,
            asset_,
            onBehalfOf_,
            repayOhm_,
            resultingPosition.principalDue
        );
        remainingDebtOhm = resultingPosition.principalDue;
        healthFactor = remainingDebtOhm == 0 ? type(uint256).max : 0;
        return (remainingDebtOhm, healthFactor);
    }

    /// @notice Quotes and executes a fixed-term maturity extension.
    /// @dev Reverts for a missing position, invalid quote, excessive fee, transfer failure, or an
    ///      underlying FLOAN mutation failure.
    /// @return fee Actual extension fee charged.
    /// @return maturity Maturity stored by FLOAN.
    /// @return healthFactor Health factor calculated from FLOAN's resulting position.
    function extend(
        uint32 marketId_,
        address asset_,
        address onBehalfOf_,
        uint16 termCount_,
        uint256 maxFee_
    ) public returns (uint256 fee, uint48 maturity, uint256 healthFactor) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        (bool exists, uint64 positionId) = BurnerLoansPositions.find(
            dependencies_.floan,
            marketId_,
            onBehalfOf_
        );
        if (!exists) revert IBurnerLoans.BurnerLoans_NoCollateral();
        IBurnerLoans.ExtendPreview memory preview = BurnerLoansQuote.quoteExtend(
            dependencies_,
            asset_,
            termCount_,
            dependencies_.floan.getPosition(positionId)
        );
        if (preview.fee > maxFee_) {
            revert IBurnerLoans.BurnerLoans_FeeExceedsMax(preview.fee, maxFee_);
        }

        // Use FLOAN's returned position as the authoritative action result.
        IFLOANv1.Position memory resultingPosition = dependencies_.floan.extendMaturity(
            positionId,
            preview.maturity
        );
        if (preview.fee != 0) {
            // Asset admission already established exact transfer semantics during deposit.
            ERC20(asset_).safeTransferFrom(
                msg.sender,
                address(dependencies_.treasury),
                preview.fee
            );
        }

        healthFactor = BurnerLoansQuote.positionHealthFactor(
            dependencies_,
            asset_,
            resultingPosition.collateral,
            resultingPosition.principalDue
        );
        fee = preview.fee;
        maturity = resultingPosition.maturity;
        emit IBurnerLoans.Extended(msg.sender, asset_, onBehalfOf_, maturity, fee);
    }

    /// @notice Grants DepositManager unlimited approval to burn this operator's receipt token.
    /// @dev Reverts if an existing receipt manager rejects the approval.
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

    /// @notice Loads the Burner Loans dependency context from the calling policy.
    function _dependencies() private view returns (BurnerLoansContext memory) {
        return IBurnerLoansSeizureContext(address(this)).context();
    }

    /// @notice Returns the first compatible Burner Loans market and its decoded configuration.
    function _getAssetMarket(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) private view returns (uint32 marketId_, IBurnerLoans.AssetConfig memory config_) {
        marketId_ = BurnerLoansMarketConfig.firstMarketId(
            dependencies_.floan,
            address(this),
            asset_,
            address(dependencies_.ohm)
        );
        IFLOANv1.Market memory market = dependencies_.floan.getMarket(marketId_);
        config_ = BurnerLoansMarketConfig.assetConfig(
            marketId_,
            market,
            dependencies_.floan.getMarketConfigData(marketId_)
        );
    }

    /// @notice Returns the first compatible Burner Loans market with originations enabled.
    /// @dev Reverts when the market is unavailable, incompatible, or originations are disabled.
    function _requireAssetOriginationsEnabled(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) private view returns (uint32 marketId_) {
        IBurnerLoans.AssetConfig memory config;
        (marketId_, config) = _getAssetMarket(dependencies_, asset_);
        if (!config.originationsEnabled) {
            revert IBurnerLoans.BurnerLoans_AssetOriginationsDisabled(asset_);
        }
    }

    /// @notice Requires the caller to be authorized for the borrower account.
    function _requireSenderAuthorized(address onBehalfOf_) private view {
        if (!IOperatorAuth(address(this)).isSenderAuthorized(msg.sender, onBehalfOf_)) {
            revert IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf();
        }
    }
}
