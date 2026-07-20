// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansContext, IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {BurnerLoansCalculator} from "src/policies/libraries/BurnerLoansCalculator.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";
import {BURNER_LOANS_SEIZER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Seizure Library
/// @notice Separately linked batch validation, scanning, default settlement, and reward routing.
library BurnerLoansSeizure {
    using TransferHelper for ERC20;

    uint256 internal constant MAX_BATCH_SIZE = 50;
    uint256 private constant _BPS = 10_000;
    uint256 private constant _WAD = 1e18;

    struct Pricing {
        uint256 ohmUsdPrice;
        uint256 backingPerOhmUsd;
        uint256 collateralUsdPrice;
    }

    struct Batch {
        IBurnerLoans.SeizePreview preview;
        IBurnerLoans.AssetConfig config;
        Pricing pricing;
        uint64[] positionIds;
        uint128[] debts;
        uint128[] collaterals;
        uint256 creditedCollateral;
    }

    struct BatchContext {
        uint32 marketId;
        IBurnerLoans.AssetConfig config;
        Pricing pricing;
    }

    struct ScanParams {
        uint32 marketId;
        uint256 cursor;
        uint256 checkLimit;
        uint256 returnLimit;
    }

    struct ScanRequest {
        address asset;
        uint256 startIndex;
        uint256 maxBorrowersToCheck;
        uint256 maxBorrowersToReturn;
    }

    struct ScanResult {
        address[] borrowers;
        uint256 nextIndex;
        uint256 seizedDebt;
        uint256 seizedCollateral;
        IBurnerLoans.AssetConfig config;
        Pricing pricing;
    }

    function previewSeize(
        address asset_,
        address[] memory borrowers_
    ) public view returns (IBurnerLoans.SeizePreview memory) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        return
            _quoteBatch(dependencies_, asset_, borrowers_, _isProtocolCaller(dependencies_))
                .preview;
    }

    function seize(
        address asset_,
        address[] memory borrowers_
    ) public returns (IBurnerLoans.SeizePreview memory preview) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        bool isProtocolCaller = _isProtocolCaller(dependencies_);
        Batch memory batch = _quoteBatch(dependencies_, asset_, borrowers_, isProtocolCaller);

        for (uint256 i; i < batch.positionIds.length; ++i) {
            dependencies_.floan.defaultPosition(batch.positionIds[i]);
        }

        uint256 startingBalance = IERC20(asset_).balanceOf(address(this));
        uint256 amountOut;
        if (batch.creditedCollateral != 0) {
            amountOut = BurnerLoansCustody.withdraw(
                dependencies_.depositManager,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                batch.creditedCollateral,
                address(this)
            );
            if (amountOut == 0) revert IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal();
        }

        preview = _previewAmounts(
            dependencies_.ohmDecimals,
            batch.config,
            batch.pricing,
            batch.preview.seizedDebtOhm,
            amountOut,
            isProtocolCaller
        );

        if (preview.keeperReward != 0) {
            ERC20(asset_).safeTransfer(msg.sender, preview.keeperReward);
        }
        if (preview.collateralToTreasury != 0) {
            ERC20(asset_).safeTransfer(dependencies_.treasury, preview.collateralToTreasury);
        }

        uint256 finalBalance = IERC20(asset_).balanceOf(address(this));
        if (finalBalance != startingBalance) {
            revert IBurnerLoans.BurnerLoans_ResidualCollateralBalance(
                asset_,
                finalBalance > startingBalance
                    ? finalBalance - startingBalance
                    : startingBalance - finalBalance
            );
        }

        for (uint256 i; i < borrowers_.length; ++i) {
            emit IBurnerLoans.Seized(
                msg.sender,
                asset_,
                borrowers_[i],
                batch.debts[i],
                batch.collaterals[i]
            );
        }
        emit IBurnerLoans.SeizureBatchSettled(
            msg.sender,
            asset_,
            borrowers_.length,
            preview.seizedDebtOhm,
            preview.seizedCollateral,
            preview.keeperReward,
            preview.collateralToTreasury
        );
    }

    function getSeizableBorrowers(
        ScanRequest memory request_
    )
        public
        view
        returns (address[] memory borrowers, uint256 nextIndex, uint256 expectedKeeperReward)
    {
        BurnerLoansContext memory dependencies_ = _dependencies();
        ScanResult memory result = _scanRequest(dependencies_, request_);
        return
            _scanResponse(dependencies_, request_.asset, result, _isProtocolCaller(dependencies_));
    }

    function _scanRequest(
        BurnerLoansContext memory dependencies_,
        ScanRequest memory request_
    ) private view returns (ScanResult memory result) {
        if (request_.maxBorrowersToReturn > MAX_BATCH_SIZE) {
            revert IBurnerLoans.BurnerLoans_InvalidBatch();
        }
        uint32 marketId = BurnerLoansMarketConfig.marketId(
            dependencies_.floan,
            dependencies_.facility,
            request_.asset,
            address(dependencies_.ohm)
        );
        result.config = _assetConfigForMarket(dependencies_.floan, marketId, request_.asset);
        uint256 activeCount = dependencies_.floan.activeBorrowerCount(marketId);
        if (activeCount == 0) {
            result.borrowers = new address[](0);
            return result;
        }

        uint256 cursor = request_.startIndex % activeCount;
        if (request_.maxBorrowersToCheck == 0 || request_.maxBorrowersToReturn == 0) {
            result.borrowers = new address[](0);
            result.nextIndex = cursor;
            return result;
        }

        result.pricing = _pricing(dependencies_, request_.asset);
        ScanResult memory scanned = _scan(
            dependencies_,
            result.config,
            result.pricing,
            ScanParams({
                marketId: marketId,
                cursor: cursor,
                checkLimit: request_.maxBorrowersToCheck < activeCount
                    ? request_.maxBorrowersToCheck
                    : activeCount,
                returnLimit: request_.maxBorrowersToReturn
            })
        );
        scanned.config = result.config;
        scanned.pricing = result.pricing;
        return scanned;
    }

    function _scanResponse(
        BurnerLoansContext memory dependencies_,
        address asset_,
        ScanResult memory result_,
        bool isProtocolCaller_
    )
        private
        view
        returns (address[] memory borrowers, uint256 nextIndex, uint256 expectedKeeperReward)
    {
        borrowers = result_.borrowers;
        nextIndex = result_.nextIndex;
        if (borrowers.length == 0) return (borrowers, nextIndex, 0);

        IDepositManager.AssetConfiguration memory custody = BurnerLoansCustody
            .validateCustodySupportFor(
                dependencies_.depositManager,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                false,
                dependencies_.facility
            );
        uint256 amountOut = BurnerLoansCustody.previewWithdrawAmount(
            custody.vault,
            result_.seizedCollateral
        );
        expectedKeeperReward = _keeperReward(
            dependencies_.ohmDecimals,
            result_.config,
            result_.pricing,
            result_.seizedDebt,
            amountOut,
            isProtocolCaller_
        );
    }

    function _scan(
        BurnerLoansContext memory dependencies_,
        IBurnerLoans.AssetConfig memory config_,
        Pricing memory pricing_,
        ScanParams memory params_
    ) private view returns (ScanResult memory result) {
        address[] memory candidates = new address[](params_.returnLimit);
        uint256 returned;
        uint256 checked;
        uint256 activeCount = dependencies_.floan.activeBorrowerCount(params_.marketId);
        while (checked < params_.checkLimit && returned < params_.returnLimit) {
            address borrower = dependencies_.floan.activeBorrowerAt(
                params_.marketId,
                params_.cursor
            );
            params_.cursor = params_.cursor + 1 == activeCount ? 0 : params_.cursor + 1;
            ++checked;

            IFLOANv1.Position memory position = dependencies_.floan.getPositionForBorrower(
                params_.marketId,
                borrower
            );
            if (!_isSeizable(dependencies_.ohmDecimals, position, config_, pricing_)) continue;

            candidates[returned++] = borrower;
            result.seizedDebt += position.principalDue;
            result.seizedCollateral += position.collateral;
        }

        result.borrowers = new address[](returned);
        for (uint256 i; i < returned; ++i) result.borrowers[i] = candidates[i];
        result.nextIndex = params_.cursor;
    }

    function _quoteBatch(
        BurnerLoansContext memory dependencies_,
        address asset_,
        address[] memory borrowers_,
        bool isProtocolCaller_
    ) private view returns (Batch memory batch) {
        uint256 borrowerCount = borrowers_.length;
        if (borrowerCount == 0 || borrowerCount > MAX_BATCH_SIZE) {
            revert IBurnerLoans.BurnerLoans_InvalidBatch();
        }

        BatchContext memory context;
        context.marketId = BurnerLoansMarketConfig.marketId(
            dependencies_.floan,
            dependencies_.facility,
            asset_,
            address(dependencies_.ohm)
        );
        context.config = _assetConfigForMarket(dependencies_.floan, context.marketId, asset_);
        context.pricing = _pricing(dependencies_, asset_);
        batch = _validateBatch(dependencies_, borrowers_, context);

        IDepositManager.AssetConfiguration memory custody = BurnerLoansCustody
            .validateCustodySupportFor(
                dependencies_.depositManager,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                false,
                dependencies_.facility
            );
        uint256 amountOut;
        if (batch.creditedCollateral != 0) {
            amountOut = BurnerLoansCustody.previewWithdrawAmount(
                custody.vault,
                batch.creditedCollateral
            );
            if (amountOut == 0) revert IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal();
        }
        batch.preview = _previewAmounts(
            dependencies_.ohmDecimals,
            batch.config,
            batch.pricing,
            batch.preview.seizedDebtOhm,
            amountOut,
            isProtocolCaller_
        );
    }

    function _validateBatch(
        BurnerLoansContext memory dependencies_,
        address[] memory borrowers_,
        BatchContext memory context_
    ) private view returns (Batch memory batch) {
        uint256 borrowerCount = borrowers_.length;
        batch.config = context_.config;
        batch.pricing = context_.pricing;
        batch.positionIds = new uint64[](borrowerCount);
        batch.debts = new uint128[](borrowerCount);
        batch.collaterals = new uint128[](borrowerCount);

        for (uint256 i; i < borrowerCount; ++i) {
            address borrower = borrowers_[i];
            _requireUniqueBorrower(borrowers_, i, borrower);
            (uint64 positionId, IFLOANv1.Position memory position) = _validatedPosition(
                dependencies_,
                context_,
                borrower
            );

            batch.positionIds[i] = positionId;
            batch.debts[i] = position.principalDue;
            batch.collaterals[i] = position.collateral;
            batch.preview.seizedDebtOhm += position.principalDue;
            batch.creditedCollateral += position.collateral;
        }
    }

    function _validatedPosition(
        BurnerLoansContext memory dependencies_,
        BatchContext memory context_,
        address borrower_
    ) private view returns (uint64 positionId, IFLOANv1.Position memory position) {
        if (borrower_ == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        bool exists;
        (exists, positionId) = dependencies_.floan.getPositionId(context_.marketId, borrower_);
        if (!exists) revert IBurnerLoans.BurnerLoans_NoDebt();
        position = dependencies_.floan.getPosition(positionId);
        if (position.defaulted) revert IBurnerLoans.BurnerLoans_PositionSeized();
        if (position.principalDue == 0) revert IBurnerLoans.BurnerLoans_NoDebt();
        if (!_isSeizable(dependencies_.ohmDecimals, position, context_.config, context_.pricing))
            revert IBurnerLoans.BurnerLoans_PositionNotSeizable(borrower_);
    }

    function _requireUniqueBorrower(
        address[] memory borrowers_,
        uint256 index_,
        address borrower_
    ) private pure {
        for (uint256 i; i < index_; ++i) {
            if (borrowers_[i] == borrower_) {
                revert IBurnerLoans.BurnerLoans_DuplicateBorrower(borrower_);
            }
        }
    }

    function _previewAmounts(
        uint8 ohmDecimals_,
        IBurnerLoans.AssetConfig memory config_,
        Pricing memory pricing_,
        uint256 seizedDebt_,
        uint256 seizedCollateral_,
        bool isProtocolCaller_
    ) private pure returns (IBurnerLoans.SeizePreview memory preview) {
        uint256 reward = _keeperReward(
            ohmDecimals_,
            config_,
            pricing_,
            seizedDebt_,
            seizedCollateral_,
            isProtocolCaller_
        );
        return
            IBurnerLoans.SeizePreview({
                seizedDebtOhm: seizedDebt_,
                seizedCollateral: seizedCollateral_,
                collateralToTreasury: seizedCollateral_ - reward,
                keeperReward: reward,
                executable: true
            });
    }

    function _keeperReward(
        uint8 ohmDecimals_,
        IBurnerLoans.AssetConfig memory config_,
        Pricing memory pricing_,
        uint256 seizedDebt_,
        uint256 seizedCollateral_,
        bool isProtocolCaller_
    ) private pure returns (uint256) {
        if (isProtocolCaller_ || config_.keeperRewardBps == 0 || config_.maxKeeperReward == 0)
            return 0;

        uint256 configuredReward = FullMath.mulDiv(
            seizedCollateral_,
            config_.keeperRewardBps,
            _BPS
        );
        if (configuredReward > config_.maxKeeperReward) {
            configuredReward = config_.maxKeeperReward;
        }

        uint256 requiredBackingUsd = BurnerLoansCalculator.requiredBackingUsd(
            seizedDebt_,
            pricing_.backingPerOhmUsd,
            ohmDecimals_,
            config_.backingMultiplierBps
        );
        uint256 requiredBackingAsset = BurnerLoansCalculator.requiredCollateralAsset(
            requiredBackingUsd,
            pricing_.collateralUsdPrice,
            config_.collateralDecimals
        );
        uint256 surplus = seizedCollateral_ > requiredBackingAsset
            ? seizedCollateral_ - requiredBackingAsset
            : 0;
        return configuredReward < surplus ? configuredReward : surplus;
    }

    function _isSeizable(
        uint8 ohmDecimals_,
        IFLOANv1.Position memory position_,
        IBurnerLoans.AssetConfig memory config_,
        Pricing memory pricing_
    ) private view returns (bool) {
        if (position_.principalDue == 0 || position_.defaulted) return false;
        if (block.timestamp >= position_.maturity) return true;

        uint256 collateralUsd = BurnerLoansCalculator.collateralValueUsd(
            position_.collateral,
            pricing_.collateralUsdPrice,
            config_.collateralDecimals
        );
        uint256 riskAdjustedCollateralUsd = BurnerLoansCalculator.riskAdjustedCollateralUsd(
            collateralUsd,
            config_.collateralFactorBps
        );
        uint256 debtValueUsd = BurnerLoansCalculator.debtValueUsd(
            position_.principalDue,
            pricing_.ohmUsdPrice,
            ohmDecimals_
        );
        uint256 requiredCollateralUsd = BurnerLoansCalculator.requiredCollateralUsd(
            debtValueUsd,
            position_.principalDue,
            pricing_.backingPerOhmUsd,
            ohmDecimals_,
            config_.minCollateralRatioBps,
            config_.backingMultiplierBps
        );
        return
            BurnerLoansCalculator.healthFactor(riskAdjustedCollateralUsd, requiredCollateralUsd) <
            _WAD;
    }

    function _pricing(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) private view returns (Pricing memory pricing) {
        uint48 frequency = dependencies_.price.observationFrequency();
        pricing.ohmUsdPrice = _freshPrice(
            dependencies_.price,
            address(dependencies_.ohm),
            frequency
        );
        pricing.collateralUsdPrice = _freshPrice(dependencies_.price, asset_, frequency);

        if (dependencies_.backingOracle == address(0)) {
            revert IBurnerLoans.BurnerLoans_ZeroAddress();
        }
        uint256 backing18 = IOlympusBackingOracle(dependencies_.backingOracle).backing();
        if (backing18 == 0) revert IBurnerLoans.BurnerLoans_InvalidPrice();
        pricing.backingPerOhmUsd = FullMath.mulDivUp(
            backing18,
            BurnerLoansCalculator.scale(dependencies_.price.decimals()),
            _WAD
        );
    }

    function _freshPrice(
        IPRICEv2 price_,
        address asset_,
        uint48 frequency_
    ) private view returns (uint256 value) {
        uint48 timestamp;
        (value, timestamp) = price_.getPrice(asset_, IPRICEv2.Variant.CURRENT);
        if (
            value == 0 ||
            timestamp == 0 ||
            block.timestamp > uint256(timestamp) + uint256(frequency_)
        ) revert IBurnerLoans.BurnerLoans_InvalidPrice();
    }

    function _assetConfig(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) private view returns (IBurnerLoans.AssetConfig memory) {
        uint32 marketId = BurnerLoansMarketConfig.marketId(
            dependencies_.floan,
            dependencies_.facility,
            asset_,
            address(dependencies_.ohm)
        );
        return _assetConfigForMarket(dependencies_.floan, marketId, asset_);
    }

    function _assetConfigForMarket(
        IFLOANv1 floan_,
        uint32 marketId_,
        address asset_
    ) private view returns (IBurnerLoans.AssetConfig memory) {
        IFLOANv1.Market memory market = floan_.getMarket(marketId_);
        if (market.configId != BurnerLoansMarketConfig.CONFIG_ID) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
        return BurnerLoansMarketConfig.assetConfig(market, floan_.getMarketConfigData(marketId_));
    }

    function _dependencies() private view returns (BurnerLoansContext memory) {
        return IBurnerLoansSeizureContext(address(this)).context();
    }

    function _isProtocolCaller(
        BurnerLoansContext memory dependencies_
    ) private view returns (bool) {
        return dependencies_.roles.hasRole(msg.sender, BURNER_LOANS_SEIZER_ROLE);
    }
}
