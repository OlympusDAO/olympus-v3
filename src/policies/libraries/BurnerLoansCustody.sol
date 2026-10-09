// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";
import {BurnerLoansContext, IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCustodyAccounting} from "src/policies/libraries/BurnerLoansCustodyAccounting.sol";
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
    using SafeERC20 for ERC20;
    using SafeERC20Exact for ERC20;

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
    ///      - The quoted fee exceeds `maxFee_`. Burner Loans collects the fee after this call.
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
            revert IBurnerLoans.BurnerLoans_DependencyNotActive(address(dependencies_.inventory));
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
        (
            IBurnerLoans.BorrowPreview memory preview,
            BurnerLoansQuote.PricePair memory pricePair
        ) = BurnerLoansQuote.quoteBorrowForAction(
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
        dependencies_.inventory.draw(params_.recipient, params_.ohmAmount);

        uint256 healthFactor = BurnerLoansQuote.positionHealthFactorWithPricePair(
            dependencies_,
            params_.asset,
            resultingPosition.collateral,
            resultingPosition.principalDue,
            pricePair
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
    ///      - The amount is zero, below the DepositManager minimum, or exceeds its asset cap.
    ///      - The caller is unauthorized or DepositManager has no enabled custody period.
    ///      - The incoming transfer or DepositManager receipt is inexact, custody retains a
    ///        residual balance, or ERC-4626 rounding produces zero credit.
    ///      - FLOAN position creation or collateral mutation fails.
    /// @return depositedCollateral Actual collateral credited after vault rounding.
    /// @return totalCollateral Resulting position collateral.
    /// @return healthFactor Resulting position health factor.
    function depositCollateral(
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) public returns (uint256 depositedCollateral, uint256 totalCollateral, uint256 healthFactor) {
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
        validateMinimumDeposit(asset_, assetConfiguration, amount_);

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
        uint256 healthFactor_ = BurnerLoansQuote.positionHealthFactorForAction(
            dependencies_,
            asset_,
            totalCollateral_,
            dependencies_.floan.getPosition(positionId).principalDue
        );

        emit IBurnerLoans.CollateralDeposited(
            msg.sender,
            asset_,
            onBehalfOf_,
            amount_,
            depositedCollateral_
        );
        return (depositedCollateral_, totalCollateral_, healthFactor_);
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
        (uint32 marketId_, IBurnerLoans.AssetConfig memory assetConfig) = _getAssetMarket(
            dependencies_,
            asset_
        );
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
        healthFactor = BurnerLoansQuote.positionHealthFactorForAction(
            dependencies_,
            params_.asset,
            remainingCollateral,
            position.principalDue
        );
        if (position.principalDue != 0 && healthFactor < _WAD) {
            revert IBurnerLoans.BurnerLoans_UnhealthyPosition(healthFactor);
        }

        (tokenOut, amountOut) = withdraw(
            dependencies_.depositManager,
            params_.asset,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            params_.amount,
            params_.recipient,
            assetConfig.withdrawAsShares
        );
        if (amountOut == 0) {
            revert IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal();
        }
        emit IBurnerLoans.CollateralWithdrawn(
            msg.sender,
            params_.asset,
            params_.onBehalfOf,
            params_.recipient,
            params_.amount,
            tokenOut,
            amountOut
        );
    }

    /// @notice Validates custody support for an explicit operator.
    /// @dev Reverts if:
    ///      - DepositManager is disabled or the asset or requested period is unavailable.
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

    /// @notice Validates a deposit amount against the configured minimum.
    /// @dev DepositManager validates its aggregate asset cap using credited principal after vault
    ///      conversion. Repeating that check here against the raw input would reject valid deposits.
    ///      Reverts if:
    ///      - The amount is below the configured minimum deposit.
    function validateMinimumDeposit(
        address asset_,
        IDepositManager.AssetConfiguration memory assetConfiguration_,
        uint128 amount_
    ) public pure {
        if (amount_ < assetConfiguration_.minimumDeposit) {
            revert IAssetManager.AssetManager_MinimumDepositNotMet(
                asset_,
                amount_,
                assetConfiguration_.minimumDeposit
            );
        }
    }

    /// @notice Quotes withdrawable collateral credited by a DepositManager deposit.
    /// @dev Reverts if:
    ///      - DepositManager rejects the preview or the estimated credit exceeds `uint128`.
    /// @param depositManager_ DepositManager V1.1 implementation.
    /// @param asset_ Underlying collateral asset.
    /// @param amount_ Underlying amount supplied.
    /// @return Estimated withdrawable credit, rounded according to DepositManager.
    function previewDepositAmount(
        IDepositManager depositManager_,
        address asset_,
        uint128 amount_
    ) public view returns (uint128) {
        // Burner Loans credits only the asset-denominated estimate; the share estimate is
        // informational for callers that interact with DepositManager directly.
        // forge-lint: disable-start(unused-return)
        (uint256 estimatedCredit, ) = IDepositManagerV1_1(address(depositManager_)).previewDeposit(
            IERC20(asset_),
            amount_
        );
        // forge-lint: disable-end(unused-return)
        return SafeCast.toUint128(estimatedCredit);
    }

    /// @notice Quotes the DepositManager output for a requested collateral debit.
    /// @dev Reverts if:
    ///      - DepositManager rejects the preview.
    /// @param depositManager_ DepositManager V1.1 implementation.
    /// @param asset_ Underlying collateral asset.
    /// @param amount_ Credited collateral amount.
    /// @param withdrawAsShares_ Whether DepositManager returns vault shares.
    /// @return tokenOut Token expected from DepositManager.
    /// @return amountOut Amount expected in `tokenOut` decimals.
    function previewWithdrawAmount(
        IDepositManager depositManager_,
        address asset_,
        uint256 amount_,
        bool withdrawAsShares_
    ) public view returns (address tokenOut, uint256 amountOut) {
        (IERC20 outputToken, uint256 outputAmount) = IDepositManagerV1_1(address(depositManager_))
            .previewWithdraw(IERC20(asset_), amount_, withdrawAsShares_);
        return (address(outputToken), outputAmount);
    }

    /// @notice Transfers collateral into DepositManager custody.
    /// @dev Reverts if:
    ///      - The caller transfer or DepositManager receipt is inexact.
    ///      - Residual collateral remains, receipt approval fails, or DepositManager rejects deposit.
    /// @return depositedCollateral Actual collateral credited after vault rounding.
    function deposit(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint128 amount_
    ) public returns (uint128 depositedCollateral) {
        ERC20 asset = ERC20(asset_);
        uint256 startingBalance = asset.safeTransferFromExact(msg.sender, address(this), amount_);
        asset.forceApprove(address(depositManager_), amount_);

        uint256 depositedCollateralRaw;
        // Burner Loans accounts for credited collateral, not the DepositManager receipt-token ID.
        // forge-lint: disable-start(unused-return)
        (, depositedCollateralRaw) = depositManager_.deposit(
            IDepositManager.DepositParams({
                asset: IERC20(asset_),
                depositPeriod: depositPeriod_,
                depositor: address(this),
                amount: amount_,
                shouldWrap: false
            })
        );
        // forge-lint: disable-end(unused-return)
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
    /// @dev Reverts if:
    ///      - DepositManager rejects the withdrawal.
    /// @return tokenOut Token transferred to the recipient.
    /// @return amountOut Actual amount transferred in `tokenOut` decimals.
    function withdraw(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_,
        bool withdrawAsShares_
    ) public returns (address tokenOut, uint256 amountOut) {
        IERC20 outputToken;
        (outputToken, amountOut) = IDepositManagerV1_1(address(depositManager_)).withdraw(
            IDepositManager.WithdrawParams({
                asset: IERC20(asset_),
                depositPeriod: depositPeriod_,
                depositor: address(this),
                recipient: recipient_,
                amount: amount_,
                isWrapped: false
            }),
            withdrawAsShares_
        );
        tokenOut = address(outputToken);
    }

    /// @notice Returns validated custody accounting for an asset and operator.
    /// @dev Reverts if:
    ///      - Custody support is invalid.
    function getAssetCollateralStatus(
        IDepositManager depositManager_,
        address asset_,
        address operator_
    ) public view returns (IBurnerLoans.AssetCollateralStatus memory collateralStatus) {
        validateCustodySupportFor(
            depositManager_,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            false,
            operator_
        );
        IERC20 asset = IERC20(asset_);
        (collateralStatus.shares, collateralStatus.assets) = depositManager_.getOperatorAssets(
            asset,
            operator_
        );
        collateralStatus.borrowed = depositManager_.getBorrowedAmount(asset, operator_);
        collateralStatus.liabilities = depositManager_.getOperatorLiabilities(asset, operator_);
        collateralStatus.solvent = BurnerLoansCustodyAccounting.isSolvent(
            collateralStatus.assets,
            collateralStatus.borrowed,
            collateralStatus.liabilities
        );
        collateralStatus.claimableYield = depositManager_.maxClaimYield(asset, operator_);
    }

    /// @notice Returns custody accounting for a registered Burner Loans collateral asset.
    /// @dev Reverts if:
    ///      - The asset is not registered or custody support is invalid.
    function getRegisteredAssetCollateralStatus(
        EnumerableSet.AddressSet storage assets_,
        IDepositManager depositManager_,
        address asset_
    ) public view returns (IBurnerLoans.AssetCollateralStatus memory) {
        _requireAssetRegistered(assets_, asset_);
        return getAssetCollateralStatus(depositManager_, asset_, address(this));
    }

    /// @notice Claims solvent custody yield directly to the selected recipient.
    /// @dev Reverts if:
    ///      - The asset is unregistered, custody support is invalid, or custody is insolvent.
    ///      - The configured market or withdrawal route is invalid.
    ///      - DepositManager rejects the claim or its outgoing token transfer fails.
    function claimYield(
        EnumerableSet.AddressSet storage assets_,
        address asset_
    ) public returns (address tokenOut, uint256 amountOut) {
        _requireAssetRegistered(assets_, asset_);
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
        IBurnerLoans.AssetConfig memory assetConfig;
        (, assetConfig) = _getAssetMarket(dependencies_, asset_);
        uint256 requestedAmount = _claimableYieldRequest(
            collateralStatus,
            assetConfig.withdrawAsShares
        );
        if (requestedAmount == 0) {
            IAssetManagerV1_1 assetManager = IAssetManagerV1_1(
                address(dependencies_.depositManager)
            );
            assetManager.validateAssetWithdrawAsShares(
                IERC20(asset_),
                assetConfig.withdrawAsShares
            );
            IERC20 zeroClaimToken = assetManager.getAssetWithdrawalToken(
                IERC20(asset_),
                assetConfig.withdrawAsShares
            );
            return (address(zeroClaimToken), 0);
        }

        IERC20 outputToken;
        (outputToken, amountOut) = IDepositManagerV1_1(address(dependencies_.depositManager))
            .claimYield(
                IERC20(asset_),
                dependencies_.yieldRecipient,
                requestedAmount,
                assetConfig.withdrawAsShares
            );
        tokenOut = address(outputToken);

        if (amountOut != 0) {
            emit IBurnerLoansYieldClaim.YieldClaimed(
                asset_,
                requestedAmount,
                tokenOut,
                amountOut,
                dependencies_.yieldRecipient
            );
        }
    }

    /// @notice Quotes claimable yield and validates current custody and routing state.
    /// @dev Reverts if:
    ///      - The asset is unregistered or custody or its stored route is invalid.
    ///      - DepositManager rejects the withdrawal preview.
    function previewClaimYield(
        EnumerableSet.AddressSet storage assets_,
        address asset_
    ) public view returns (IBurnerLoans.ClaimYieldPreview memory preview) {
        _requireAssetRegistered(assets_, asset_);
        BurnerLoansContext memory dependencies_ = _dependencies();
        IBurnerLoans.AssetCollateralStatus memory collateralStatus = getAssetCollateralStatus(
            dependencies_.depositManager,
            asset_,
            address(this)
        );
        IBurnerLoans.AssetConfig memory assetConfig;
        (, assetConfig) = _getAssetMarket(dependencies_, asset_);
        preview.requestedAssetAmount = _claimableYieldRequest(
            collateralStatus,
            assetConfig.withdrawAsShares
        );
        IERC20 outputToken;
        (outputToken, preview.amountOut) = IDepositManagerV1_1(
            address(dependencies_.depositManager)
        ).previewWithdraw(
                IERC20(asset_),
                preview.requestedAssetAmount,
                assetConfig.withdrawAsShares
            );
        preview.tokenOut = address(outputToken);
        preview.recipient = dependencies_.yieldRecipient;
        preview.executable = collateralStatus.solvent;
    }

    /// @notice Returns the underlying-denominated yield request for the configured output mode.
    /// @dev Legacy underlying withdrawals retain DepositManager's one-unit redemption buffer.
    ///      Share withdrawals do not redeem, so the solvent surplus can include that final unit.
    ///      The request is capped by assets currently held because borrowed coverage is accounted
    ///      for but is not presently transferable from custody.
    ///      Reverts if:
    ///      - Adding held and borrowed asset amounts overflows.
    function _claimableYieldRequest(
        IBurnerLoans.AssetCollateralStatus memory status_,
        bool withdrawAsShares_
    ) private pure returns (uint256) {
        if (!withdrawAsShares_) return status_.claimableYield;

        uint256 coveredAssets = status_.assets + status_.borrowed;
        if (coveredAssets <= status_.liabilities) return 0;
        uint256 surplus = coveredAssets - status_.liabilities;
        return surplus < status_.assets ? surplus : status_.assets;
    }

    /// @dev Reverts if:
    ///      - The asset is absent from Config's append-only facility registry.
    function _requireAssetRegistered(
        EnumerableSet.AddressSet storage assets_,
        address asset_
    ) private view {
        if (!assets_.contains(asset_)) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
    }

    /// @notice Repays principal and transfers exact OHM to Burner Loans Inventory for settlement.
    /// @dev Reverts if:
    ///      - Inventory is disabled or the position is absent or debt-free.
    ///      - Repayment exceeds debt or occurs in the latest borrow block.
    ///      - The OHM transfer or Inventory receipt is inexact, or FLOAN or Inventory rejects settlement.
    ///      - Required PRICE data is unavailable when debt remains.
    /// @return remainingDebtOhm Principal stored by FLOAN after repayment.
    /// @return healthFactor Resulting position health factor; max uint after full repayment.
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

        remainingDebtOhm = resultingPosition.principalDue;
        healthFactor = BurnerLoansQuote.positionHealthFactorForAction(
            dependencies_,
            asset_,
            resultingPosition.collateral,
            remainingDebtOhm
        );

        emit IBurnerLoans.Repaid(
            msg.sender,
            asset_,
            onBehalfOf_,
            repayOhm_,
            resultingPosition.principalDue
        );
        return (remainingDebtOhm, healthFactor);
    }

    /// @notice Quotes and executes a fixed-term maturity extension.
    /// @dev Reverts if:
    ///      - The position is absent, the quote is invalid, or the fee exceeds the caller's maximum.
    ///      - FLOAN rejects the maturity change.
    ///      Burner Loans collects the fee after this library returns.
    /// @return fee Actual extension fee charged.
    /// @return maturity Maturity stored by FLOAN.
    /// @return healthFactor Quoted health factor preserved by the maturity-only FLOAN mutation.
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
        IBurnerLoans.ExtendPreview memory preview = BurnerLoansQuote.quoteExtendForAction(
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
        healthFactor = preview.healthFactor;
        fee = preview.fee;
        maturity = resultingPosition.maturity;
        emit IBurnerLoans.Extended(msg.sender, asset_, onBehalfOf_, maturity, fee);
    }

    /// @notice Grants DepositManager unlimited approval to burn this operator's receipt token.
    /// @dev Reverts if:
    ///      - An existing receipt manager rejects the approval.
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
    /// @dev Reverts if:
    ///      - The market is unavailable, incompatible, or originations are disabled.
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
