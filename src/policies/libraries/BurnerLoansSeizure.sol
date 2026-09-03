// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansContext, IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {BurnerLoansCalculator} from "src/policies/libraries/BurnerLoansCalculator.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Seizure Library
/// @notice Separately linked batch validation, scanning, default settlement, and reward routing.
library BurnerLoansSeizure {
    using TransferHelper for ERC20;
    using SafeCast for uint256;

    /// @notice Maximum number of positions in one seizure batch.
    uint256 internal constant MAX_BATCH_SIZE = 50;

    /// @dev Basis-point denominator.
    uint256 private constant _BPS = 10_000;

    /// @dev Fixed-point scale for valuation calculations.
    uint256 private constant _WAD = 1e18;

    /// @notice Price snapshot shared across a seizure batch.
    /// @param ohmUsdPrice OHM/USD price, in PRICE decimals.
    /// @param backingPerOhmUsd Backing per OHM, rescaled from 1e18 to PRICE decimals.
    /// @param collateralUsdPrice Collateral/USD price, in PRICE decimals.
    struct Pricing {
        uint256 ohmUsdPrice;
        uint256 backingPerOhmUsd;
        uint256 collateralUsdPrice;
    }

    /// @notice Validated seizure batch and its position-level accounting.
    struct Batch {
        IBurnerLoans.SeizePreview preview;
        IBurnerLoans.AssetConfig config;
        Pricing pricing;
        uint64[] positionIds;
        uint128[] debts;
        uint128[] collaterals;
        uint256 creditedCollateral;
    }

    /// @notice Market configuration and pricing shared during batch validation.
    struct BatchContext {
        uint32 marketId;
        IBurnerLoans.AssetConfig config;
        Pricing pricing;
    }

    /// @notice Bounded active-borrower scan parameters.
    struct ScanParams {
        uint32 marketId;
        uint256 cursor;
        uint256 checkLimit;
        uint256 returnLimit;
    }

    /// @notice Caller-supplied active-borrower scan request.
    struct ScanRequest {
        address asset;
        uint256 startIndex;
        uint256 maxBorrowersToCheck;
        uint256 maxBorrowersToReturn;
    }

    /// @notice Accumulated active-borrower scan result.
    struct ScanResult {
        address[] borrowers;
        uint256 nextIndex;
        uint256 seizedDebt;
        uint256 seizedCollateral;
        IBurnerLoans.AssetConfig config;
        Pricing pricing;
    }

    /// @notice Quotes seizure of a homogeneous borrower batch.
    /// @dev Reverts for invalid batches, invalid configuration/custody/prices, duplicate borrowers,
    ///      missing debt, or any position that is not seizable.
    function previewSeize(
        address asset_,
        address[] memory borrowers_
    ) public view returns (IBurnerLoans.SeizePreview memory) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        return
            _quoteBatch(dependencies_, asset_, borrowers_, _isProtocolCaller(dependencies_))
                .preview;
    }

    /// @notice Defaults a homogeneous borrower batch and routes withdrawn collateral.
    /// @dev Applies the same validation as preview, then atomically defaults FLOAN positions,
    ///      withdraws collateral, pays any keeper reward, and transfers the remainder to treasury.
    /// @return keeperReward Actual collateral paid to the keeper.
    /// @return collateralToTreasury Actual collateral routed to Treasury.
    function seize(
        address asset_,
        address[] memory borrowers_
    ) public returns (uint256 keeperReward, uint256 collateralToTreasury) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        bool isProtocolCaller = _isProtocolCaller(dependencies_);
        Batch memory batch = _quoteBatch(dependencies_, asset_, borrowers_, isProtocolCaller);

        uint256 actualDebtOhm;
        uint256 actualCollateral;
        for (uint256 i; i < batch.positionIds.length; ++i) {
            // FLOAN owns position accounting. Capture each mutation result so settlement, events,
            // and action return values are based on stored outcomes rather than the earlier quote.
            (uint128 debtDefaulted, , uint128 collateralSeized) = dependencies_
                .floan
                .defaultPosition(batch.positionIds[i]);
            batch.debts[i] = debtDefaulted;
            batch.collaterals[i] = collateralSeized;
            actualDebtOhm += debtDefaulted;
            actualCollateral += collateralSeized;
        }
        dependencies_.inventory.recordDefault(actualDebtOhm.toUint128());

        uint256 startingBalance = IERC20(asset_).balanceOf(address(this));
        uint256 amountOut;
        if (actualCollateral != 0) {
            amountOut = BurnerLoansCustody.withdraw(
                dependencies_.depositManager,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                actualCollateral,
                address(this)
            );
            if (amountOut == 0) revert IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal();
        }

        IBurnerLoans.SeizePreview memory result = _previewAmounts(
            dependencies_.ohmDecimals,
            batch.config,
            batch.pricing,
            actualDebtOhm,
            amountOut,
            isProtocolCaller
        );

        if (result.keeperReward != 0) {
            ERC20(asset_).safeTransfer(msg.sender, result.keeperReward);
        }
        if (result.collateralToTreasury != 0) {
            ERC20(asset_).safeTransfer(dependencies_.treasury, result.collateralToTreasury);
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
            result.seizedDebtOhm,
            result.seizedCollateral,
            result.keeperReward,
            result.collateralToTreasury
        );

        return (result.keeperReward, result.collateralToTreasury);
    }

    /// @notice Scans active borrowers and returns a bounded set of seizable addresses.
    /// @dev Reverts for an excessive return limit or unavailable market configuration/pricing.
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

    /// @notice Resolves market state and performs the bounded borrower scan requested by a caller.
    /// @dev Returns early without PRICE reads when the market is empty or either scan limit is zero.
    function _scanRequest(
        BurnerLoansContext memory dependencies_,
        ScanRequest memory request_
    ) private view returns (ScanResult memory result) {
        if (request_.maxBorrowersToReturn > MAX_BATCH_SIZE) {
            revert IBurnerLoans.BurnerLoans_InvalidBatch();
        }
        uint32 marketId = BurnerLoansMarketConfig.firstMarketId(
            dependencies_.floan,
            dependencies_.facility,
            request_.asset,
            address(dependencies_.ohm)
        );
        result.config = _assetConfigForMarket(dependencies_.floan, marketId);
        uint256 activeCount = dependencies_.floan.getActiveBorrowerCount(marketId);
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

    /// @notice Converts accumulated scan accounting into the external response shape.
    /// @dev Custody is only previewed when at least one borrower is returned.
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

    /// @notice Scans active borrowers from a circular cursor until either bound is reached.
    /// @dev The cursor advances for every inspected borrower, including non-seizable positions.
    function _scan(
        BurnerLoansContext memory dependencies_,
        IBurnerLoans.AssetConfig memory config_,
        Pricing memory pricing_,
        ScanParams memory params_
    ) private view returns (ScanResult memory result) {
        address[] memory candidates = new address[](params_.returnLimit);
        uint256 returned;
        uint256 checked;
        uint256 activeCount = dependencies_.floan.getActiveBorrowerCount(params_.marketId);
        while (checked < params_.checkLimit && returned < params_.returnLimit) {
            address borrower = dependencies_.floan.getActiveBorrowerAt(
                params_.marketId,
                params_.cursor
            );
            params_.cursor = params_.cursor + 1 == activeCount ? 0 : params_.cursor + 1;
            ++checked;

            IFLOANv1.Position memory position = BurnerLoansPositions.getOrEmpty(
                dependencies_.floan,
                params_.marketId,
                borrower
            );
            if (!_isSeizable(dependencies_.ohmDecimals, position, config_, pricing_)) continue;

            candidates[returned++] = borrower;
            result.seizedDebt += position.principalDue;
            result.seizedCollateral += position.collateral;
        }

        result.borrowers = new address[](returned);
        for (uint256 i; i < returned; ++i) {
            result.borrowers[i] = candidates[i];
        }
        result.nextIndex = params_.cursor;
    }

    /// @notice Validates a seizure batch and calculates its expected custody output and routing.
    /// @dev Reverts for disabled Inventory, invalid batch input, unsupported custody, or zero output.
    function _quoteBatch(
        BurnerLoansContext memory dependencies_,
        address asset_,
        address[] memory borrowers_,
        bool isProtocolCaller_
    ) private view returns (Batch memory batch) {
        if (!IEnabler(address(dependencies_.inventory)).isEnabled()) revert IEnabler.NotEnabled();
        uint256 borrowerCount = borrowers_.length;
        if (borrowerCount == 0 || borrowerCount > MAX_BATCH_SIZE) {
            revert IBurnerLoans.BurnerLoans_InvalidBatch();
        }

        BatchContext memory context;
        context.marketId = BurnerLoansMarketConfig.firstMarketId(
            dependencies_.floan,
            dependencies_.facility,
            asset_,
            address(dependencies_.ohm)
        );
        context.config = _assetConfigForMarket(dependencies_.floan, context.marketId);
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

    /// @notice Validates every borrower and accumulates quoted debt and collateral.
    /// @dev Duplicate borrowers are rejected before their position contributes to the totals.
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

    /// @notice Resolves one borrower's live position and requires it to be seizable.
    function _validatedPosition(
        BurnerLoansContext memory dependencies_,
        BatchContext memory context_,
        address borrower_
    ) private view returns (uint64 positionId, IFLOANv1.Position memory position) {
        if (borrower_ == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        bool exists;
        (exists, positionId) = BurnerLoansPositions.find(
            dependencies_.floan,
            context_.marketId,
            borrower_
        );
        if (!exists) revert IBurnerLoans.BurnerLoans_NoDebt();
        position = dependencies_.floan.getPosition(positionId);
        if (position.principalDue == 0) revert IBurnerLoans.BurnerLoans_NoDebt();
        if (!_isSeizable(dependencies_.ohmDecimals, position, context_.config, context_.pricing)) {
            revert IBurnerLoans.BurnerLoans_PositionNotSeizable(borrower_);
        }
    }

    /// @notice Rejects a borrower already present earlier in the batch.
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

    /// @notice Splits seized collateral between the keeper and Treasury.
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

    /// @notice Calculates the keeper reward capped by configuration and excess backing.
    /// @dev Protocol callers receive no reward. All values use their native token decimal scales.
    function _keeperReward(
        uint8 ohmDecimals_,
        IBurnerLoans.AssetConfig memory config_,
        Pricing memory pricing_,
        uint256 seizedDebt_,
        uint256 seizedCollateral_,
        bool isProtocolCaller_
    ) internal pure returns (uint256) {
        if (isProtocolCaller_ || config_.keeperRewardBps == 0 || config_.maxKeeperReward == 0) {
            return 0;
        }

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

    /// @notice Returns whether a live position is matured or below the minimum health factor.
    /// @dev Mature positions avoid PRICE-dependent arithmetic after the supplied snapshot is built.
    function _isSeizable(
        uint8 ohmDecimals_,
        IFLOANv1.Position memory position_,
        IBurnerLoans.AssetConfig memory config_,
        Pricing memory pricing_
    ) private view returns (bool) {
        if (position_.principalDue == 0) return false;
        if (block.timestamp >= position_.maturity) return true;

        uint256 collateralUsd = BurnerLoansCalculator.collateralValueUsd(
            position_.collateral,
            pricing_.collateralUsdPrice,
            config_.collateralDecimals
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
            config_.maxLtvBps,
            config_.backingMultiplierBps
        );
        return BurnerLoansCalculator.healthFactor(collateralUsd, requiredCollateralUsd) < _WAD;
    }

    /// @notice Loads fresh OHM and collateral prices plus canonical backing for a seizure.
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

    /// @notice Loads a nonzero current price that is no older than one observation frequency.
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
        ) {
            revert IBurnerLoans.BurnerLoans_InvalidPrice();
        }
    }

    /// @notice Decodes the Burner Loans configuration stored on a FLOAN market.
    function _assetConfigForMarket(
        IFLOANv1 floan_,
        uint32 marketId_
    ) private view returns (IBurnerLoans.AssetConfig memory) {
        IFLOANv1.Market memory market = floan_.getMarket(marketId_);
        return
            BurnerLoansMarketConfig.assetConfig(
                marketId_,
                market,
                floan_.getMarketConfigData(marketId_)
            );
    }

    /// @notice Loads the Burner Loans dependency context from the calling policy.
    function _dependencies() private view returns (BurnerLoansContext memory) {
        return IBurnerLoansSeizureContext(address(this)).context();
    }

    /// @notice Returns whether the caller is a protocol-operated seizure task.
    function _isProtocolCaller(
        BurnerLoansContext memory dependencies_
    ) private view returns (bool) {
        return
            dependencies_.roles.hasRole(msg.sender, BURNER_LOANS_SEIZER_ROLE) ||
            dependencies_.roles.hasRole(msg.sender, HEART_ROLE);
    }
}
