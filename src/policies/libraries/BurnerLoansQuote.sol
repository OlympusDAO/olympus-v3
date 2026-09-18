// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansContext, IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {BurnerLoansCalculator} from "src/policies/libraries/BurnerLoansCalculator.sol";
import {BurnerLoansCustodyAccounting} from "src/policies/libraries/BurnerLoansCustodyAccounting.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";

// Contracts
import {Policy} from "src/Kernel.sol";

/// @title Burner Loans Quote Library
/// @notice Shared pricing and health validation for Burner Loans previews and execution.
/// @dev Separately linked to keep the policy below EIP-170 without duplicating module state.
library BurnerLoansQuote {
    /// @dev Fixed-point scale for health and utilization values.
    uint256 internal constant _WAD = 1e18;

    /// @notice OHM and collateral USD prices resolved from one source for one operation.
    /// @param ohmUsdPrice OHM/USD price, in PRICE decimals.
    /// @param collateralUsdPrice Collateral/USD price, in PRICE decimals.
    struct PricePair {
        uint256 ohmUsdPrice;
        uint256 collateralUsdPrice;
    }

    /// @notice Price snapshot and derived collateral valuation for one quote.
    /// @param ohmUsdPrice OHM/USD price, in PRICE decimals.
    /// @param backingPerOhmUsd Backing per OHM, rescaled from 1e18 to PRICE decimals.
    /// @param collateralUsdPrice Collateral/USD price, in PRICE decimals.
    /// @param collateralValueUsd Gross collateral value, in PRICE decimals.
    struct Pricing {
        uint256 ohmUsdPrice;
        uint256 backingPerOhmUsd;
        uint256 collateralUsdPrice;
        uint256 collateralValueUsd;
    }

    /// @notice Cached inputs used to quote an extension.
    struct ExtensionContext {
        Pricing pricing;
        IBurnerLoans.AssetConfig config;
        uint256 health;
        uint128 debtOhm;
        uint48 currentMaturity;
        uint32 marketId;
        uint16 termCount;
        bool executable;
    }

    /// @notice Validated non-price inputs shared by borrow preview and execution.
    struct BorrowContext {
        IBurnerLoans.AssetConfig config;
        uint256 assetDebt;
        uint32 marketId;
    }

    /// @notice Returns whether the configured PriceCache can be used by the current policy.
    /// @dev Availability is determined explicitly. Faults from an active cache's enabled-state
    ///      query are not reinterpreted as cache unavailability.
    function _isPriceCacheOperational(
        BurnerLoansContext memory dependencies_
    ) private view returns (bool) {
        address priceCache = address(dependencies_.priceCache);
        if (priceCache == address(0)) return false;
        if (!Policy(address(this)).kernel().isPolicyActive(Policy(priceCache))) return false;
        return IEnabler(priceCache).isEnabled();
    }

    /// @notice Resolves prices for an ordinary non-mutating quote.
    /// @dev A missing or stale operational-cache snapshot falls back to direct PRICE.
    function resolveViewPricePair(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) public view returns (PricePair memory) {
        if (_isPriceCacheOperational(dependencies_)) {
            IPriceCache.CachedPrice memory cachedPrice = dependencies_.priceCache.getCachedPrice(
                address(dependencies_.ohm),
                asset_
            );
            if (!_isCachedPriceStale(cachedPrice, dependencies_.priceCacheMaxAge)) {
                return _cachedPricePair(cachedPrice);
            }
        }
        return _directPricePair(dependencies_, asset_);
    }

    /// @notice Resolves prices for a state-changing loan or seizure action.
    /// @dev An operational cache is called exactly once and its returned snapshot is consumed.
    function resolveActionPricePair(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) public returns (PricePair memory) {
        if (!_isPriceCacheOperational(dependencies_)) {
            return _directPricePair(dependencies_, asset_);
        }

        // Assumes cachePriceIfNecessary returns a snapshot within the supplied maximum age.
        // PriceCache satisfies this by returning a fresh snapshot or recaching from PRICE, whose
        // current-price timestamp is the current block timestamp.
        IPriceCache.CachedPrice memory cachedPrice = dependencies_.priceCache.cachePriceIfNecessary(
            address(dependencies_.ohm),
            asset_,
            dependencies_.priceCacheMaxAge
        );
        return _cachedPricePair(cachedPrice);
    }

    /// @notice Quotes a borrow for the first borrower position in a known market.
    /// @dev Reverts on invalid configuration, disabled originations, custody shortfall, cap breach,
    ///      stale pricing, matured debt, or unhealthy current/resulting debt.
    function previewBorrow(
        address asset_,
        uint128 ohmAmount_,
        uint32 marketId_,
        address borrower_
    ) public view returns (IBurnerLoans.BorrowPreview memory) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        IFLOANv1.Position memory position = BurnerLoansPositions.getOrEmpty(
            dependencies_.floan,
            marketId_,
            borrower_
        );
        BorrowContext memory context = _prepareBorrow(dependencies_, asset_, ohmAmount_, position);
        return
            _quoteBorrow(
                dependencies_,
                ohmAmount_,
                position,
                context,
                _pricing(dependencies_, asset_, position.collateral, context.config),
                false
            );
    }

    /// @notice Quotes a borrow using one cache refresh or direct-PRICE resolution.
    /// @return preview Borrow quote calculated from the resolved pair.
    /// @return pricePair Price legs consumed by the quote and final action result.
    function quoteBorrowForAction(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint128 ohmAmount_,
        IFLOANv1.Position memory position
    ) public returns (IBurnerLoans.BorrowPreview memory preview, PricePair memory pricePair) {
        BorrowContext memory context = _prepareBorrow(dependencies_, asset_, ohmAmount_, position);
        pricePair = resolveActionPricePair(dependencies_, asset_);
        preview = _quoteBorrow(
            dependencies_,
            ohmAmount_,
            position,
            context,
            _pricingFromPricePair(
                dependencies_.backingOracle,
                dependencies_.price,
                position.collateral,
                context.config,
                pricePair
            ),
            true
        );
    }

    function _prepareBorrow(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint128 ohmAmount_,
        IFLOANv1.Position memory position
    ) private view returns (BorrowContext memory context) {
        if (!IEnabler(address(dependencies_.inventory)).isEnabled()) revert IEnabler.NotEnabled();
        (context.marketId, context.config) = _requireAssetOriginationsEnabled(
            dependencies_.floan,
            dependencies_.facility,
            address(dependencies_.ohm),
            asset_
        );
        if (ohmAmount_ == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();

        BurnerLoansCustodyAccounting.requireSolvent(
            dependencies_.depositManager,
            asset_,
            dependencies_.facility
        );

        if (position.collateral == 0) revert IBurnerLoans.BurnerLoans_NoCollateral();
        _validateActiveBorrowPosition(position);

        context.assetDebt = _validateCaps(
            dependencies_.floan,
            dependencies_.inventory.availableCapacity(),
            asset_,
            context.marketId,
            ohmAmount_,
            context.config.debtCap
        );
    }

    function _quoteBorrow(
        BurnerLoansContext memory dependencies_,
        uint128 ohmAmount_,
        IFLOANv1.Position memory position,
        BorrowContext memory context_,
        Pricing memory pricing,
        bool enforceHealth_
    ) private view returns (IBurnerLoans.BorrowPreview memory preview) {
        preview.fee = _borrowFee(
            dependencies_.ohmDecimals,
            dependencies_.floan,
            context_.marketId,
            ohmAmount_,
            context_.assetDebt,
            pricing,
            context_.config
        );
        preview.executable = true;
        if (position.principalDue != 0) {
            uint256 currentHealth = _health(
                dependencies_.ohmDecimals,
                position.principalDue,
                pricing,
                context_.config
            );
            if (currentHealth < _WAD) {
                if (enforceHealth_) {
                    revert IBurnerLoans.BurnerLoans_UnhealthyPosition(currentHealth);
                }
                preview.executable = false;
            }
        }

        preview.resultingDebtOhm = position.principalDue + ohmAmount_;
        preview.resultingHealthFactor = _health(
            dependencies_.ohmDecimals,
            preview.resultingDebtOhm,
            pricing,
            context_.config
        );
        if (preview.resultingHealthFactor < _WAD) {
            if (enforceHealth_) {
                revert IBurnerLoans.BurnerLoans_UnhealthyBorrow(preview.resultingHealthFactor);
            }
            preview.executable = false;
        }
        preview.maturity = position.principalDue == 0
            ? SafeCast.toUint48(block.timestamp + context_.config.termLength)
            : position.maturity;
    }

    /// @notice Quotes an extension for the first borrower position in a known market.
    /// @dev Reverts on invalid configuration, disabled originations, custody shortfall, missing
    ///      debt, stale pricing, unhealthy debt, or an invalid resulting maturity.
    function previewExtend(
        address asset_,
        uint16 termCount_,
        uint32 marketId_,
        address borrower_
    ) public view returns (IBurnerLoans.ExtendPreview memory) {
        BurnerLoansContext memory dependencies_ = _dependencies();
        IFLOANv1.Position memory position = BurnerLoansPositions.getOrEmpty(
            dependencies_.floan,
            marketId_,
            borrower_
        );
        ExtensionContext memory context = _prepareExtension(
            dependencies_,
            asset_,
            termCount_,
            position
        );
        return
            _quoteExtension(
                dependencies_,
                context,
                _pricing(dependencies_, asset_, position.collateral, context.config),
                false
            );
    }

    /// @notice Calculates current health for supplied collateral and debt.
    /// @dev Returns max uint for zero debt and otherwise reverts when configuration or prices are
    ///      unavailable.
    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) public view returns (uint256) {
        return positionHealthFactor(_dependencies(), asset_, collateral_, debtOhm_);
    }

    /// @notice Calculates current health from an already-loaded dependency context.
    /// @dev Returns max uint for zero debt and otherwise reverts when configuration or prices are
    ///      unavailable.
    function positionHealthFactor(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) public view returns (uint256) {
        if (debtOhm_ == 0) return type(uint256).max;
        (, IBurnerLoans.AssetConfig memory config) = _requireAssetConfigured(
            dependencies_.floan,
            dependencies_.facility,
            address(dependencies_.ohm),
            asset_
        );
        return
            _health(
                dependencies_.ohmDecimals,
                debtOhm_,
                _pricing(dependencies_, asset_, collateral_, config),
                config
            );
    }

    /// @notice Calculates health for an action after resolving one price pair.
    /// @dev Zero debt remains price-free.
    function positionHealthFactorForAction(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) public returns (uint256 healthFactor) {
        if (debtOhm_ == 0) return type(uint256).max;
        return
            positionHealthFactorWithPricePair(
                dependencies_,
                asset_,
                collateral_,
                debtOhm_,
                resolveActionPricePair(dependencies_, asset_)
            );
    }

    /// @notice Calculates health using price legs already resolved for the current action.
    function positionHealthFactorWithPricePair(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_,
        PricePair memory pricePair_
    ) public view returns (uint256) {
        if (debtOhm_ == 0) return type(uint256).max;
        (, IBurnerLoans.AssetConfig memory config) = _requireAssetConfigured(
            dependencies_.floan,
            dependencies_.facility,
            address(dependencies_.ohm),
            asset_
        );
        return
            _health(
                dependencies_.ohmDecimals,
                debtOhm_,
                _pricingFromPricePair(
                    dependencies_.backingOracle,
                    dependencies_.price,
                    collateral_,
                    config,
                    pricePair_
                ),
                config
            );
    }

    /// @notice Quotes an extension using one cache refresh or direct-PRICE resolution.
    /// @return preview Extension quote calculated from the resolved pair.
    function quoteExtendForAction(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint16 termCount_,
        IFLOANv1.Position memory position_
    ) public returns (IBurnerLoans.ExtendPreview memory preview) {
        ExtensionContext memory context = _prepareExtension(
            dependencies_,
            asset_,
            termCount_,
            position_
        );
        preview = _quoteExtension(
            dependencies_,
            context,
            _pricingFromPricePair(
                dependencies_.backingOracle,
                dependencies_.price,
                position_.collateral,
                context.config,
                resolveActionPricePair(dependencies_, asset_)
            ),
            true
        );
    }

    function _prepareExtension(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint16 termCount_,
        IFLOANv1.Position memory position_
    ) private view returns (ExtensionContext memory context) {
        (context.marketId, context.config) = _requireAssetOriginationsEnabled(
            dependencies_.floan,
            dependencies_.facility,
            address(dependencies_.ohm),
            asset_
        );
        if (termCount_ == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();
        if (position_.principalDue == 0) revert IBurnerLoans.BurnerLoans_NoDebt();

        BurnerLoansCustodyAccounting.requireSolvent(
            dependencies_.depositManager,
            asset_,
            dependencies_.facility
        );

        context.debtOhm = position_.principalDue;
        context.currentMaturity = position_.maturity;
        context.termCount = termCount_;
    }

    function _quoteExtension(
        BurnerLoansContext memory dependencies_,
        ExtensionContext memory context,
        Pricing memory pricing_,
        bool enforceHealth_
    ) private view returns (IBurnerLoans.ExtendPreview memory preview) {
        uint256 health = _health(
            dependencies_.ohmDecimals,
            context.debtOhm,
            pricing_,
            context.config
        );
        bool executable = health >= _WAD;
        if (enforceHealth_ && !executable) {
            revert IBurnerLoans.BurnerLoans_UnhealthyPosition(health);
        }

        context.pricing = pricing_;
        context.health = health;
        context.executable = executable;
        preview = _quoteExtensionTerms(dependencies_, context);
    }

    function _validateCaps(
        IFLOANv1 floan_,
        uint256 globalRoom_,
        address asset_,
        uint32 marketId_,
        uint128 ohmAmount_,
        uint256 assetCap_
    ) private view returns (uint256 assetDebt) {
        if (ohmAmount_ > globalRoom_) {
            revert IBurnerLoans.BurnerLoans_GlobalDebtCapExceeded(ohmAmount_, globalRoom_);
        }

        assetDebt = floan_.getMarketPrincipalDue(marketId_);
        uint256 assetRoom = assetDebt <= assetCap_ ? assetCap_ - assetDebt : 0;
        if (ohmAmount_ > assetRoom) {
            revert IBurnerLoans.BurnerLoans_AssetDebtCapExceeded(asset_, ohmAmount_, assetRoom);
        }
    }

    function _pricing(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint256 collateral_,
        IBurnerLoans.AssetConfig memory config_
    ) private view returns (Pricing memory pricing) {
        PricePair memory pricePair = resolveViewPricePair(dependencies_, asset_);
        return
            _pricingFromPricePair(
                dependencies_.backingOracle,
                dependencies_.price,
                collateral_,
                config_,
                pricePair
            );
    }

    function _pricingFromPricePair(
        address backingOracle_,
        IPRICEv2 price_,
        uint256 collateral_,
        IBurnerLoans.AssetConfig memory config_,
        PricePair memory pricePair_
    ) private view returns (Pricing memory pricing) {
        pricing.ohmUsdPrice = pricePair_.ohmUsdPrice;
        pricing.backingPerOhmUsd = _backingPerOhmUsd(backingOracle_, price_);
        pricing.collateralUsdPrice = pricePair_.collateralUsdPrice;
        pricing.collateralValueUsd = BurnerLoansCalculator.collateralValueUsd(
            collateral_,
            pricing.collateralUsdPrice,
            config_.collateralDecimals
        );
    }

    function _health(
        uint8 ohmDecimals_,
        uint256 debtOhm_,
        Pricing memory pricing_,
        IBurnerLoans.AssetConfig memory config_
    ) private pure returns (uint256) {
        uint256 debtValueUsd = BurnerLoansCalculator.debtValueUsd(
            debtOhm_,
            pricing_.ohmUsdPrice,
            ohmDecimals_
        );
        uint256 requiredUsd = BurnerLoansCalculator.requiredCollateralUsd(
            debtValueUsd,
            debtOhm_,
            pricing_.backingPerOhmUsd,
            ohmDecimals_,
            config_.maxLtvBps,
            config_.backingMultiplierBps
        );
        return BurnerLoansCalculator.healthFactor(pricing_.collateralValueUsd, requiredUsd);
    }

    function _borrowFee(
        uint8 ohmDecimals_,
        IFLOANv1 floan_,
        uint32 marketId_,
        uint128 ohmAmount_,
        uint256 assetDebt_,
        Pricing memory pricing_,
        IBurnerLoans.AssetConfig memory config_
    ) private view returns (uint256) {
        uint256 debtValueUsd = BurnerLoansCalculator.debtValueUsd(
            ohmAmount_,
            pricing_.ohmUsdPrice,
            ohmDecimals_
        );
        uint256 requiredUsd = BurnerLoansCalculator.requiredCollateralUsd(
            debtValueUsd,
            ohmAmount_,
            pricing_.backingPerOhmUsd,
            ohmDecimals_,
            config_.maxLtvBps,
            config_.backingMultiplierBps
        );
        uint256 requiredAsset = BurnerLoansCalculator.requiredCollateralAsset(
            requiredUsd,
            pricing_.collateralUsdPrice,
            config_.collateralDecimals
        );
        uint256 feeRate = _feeRate(floan_, marketId_, assetDebt_, config_.debtCap);
        return BurnerLoansCalculator.borrowFee(requiredAsset, feeRate);
    }

    function _feeRate(
        IFLOANv1 floan_,
        uint32 marketId_,
        uint256 assetDebt_,
        uint256 debtCap_
    ) private view returns (uint256) {
        uint256 utilization = BurnerLoansCalculator.assetUtilizationWad(assetDebt_, debtCap_);
        if (utilization == type(uint256).max || utilization > _WAD) {
            revert IBurnerLoans.BurnerLoans_InvalidCap();
        }
        IBurnerLoans.AssetFeeConfig memory feeConfig = BurnerLoansMarketConfig.feeConfig(
            marketId_,
            floan_.getMarket(marketId_),
            floan_.getMarketConfigData(marketId_)
        );
        return
            BurnerLoansCalculator.feeRateWad(
                utilization,
                feeConfig.baseFeeBps,
                feeConfig.kinkBps,
                feeConfig.preKinkSlopeBps,
                feeConfig.postKinkSlopeBps
            );
    }

    function _quoteExtensionTerms(
        BurnerLoansContext memory dependencies_,
        ExtensionContext memory context_
    ) private view returns (IBurnerLoans.ExtendPreview memory) {
        uint256 requestedMaturity = uint256(context_.currentMaturity) +
            uint256(context_.config.termLength) *
            context_.termCount;
        // Extension maturity uses chain time and tolerates normal validator drift.
        // forge-lint: disable-next-line(block-timestamp)
        if (requestedMaturity <= block.timestamp) {
            revert IBurnerLoans.BurnerLoans_ExtensionMaturityNotFuture(
                requestedMaturity,
                block.timestamp
            );
        }
        _validateMaturityHorizon(requestedMaturity, context_.config.maxMaturityHorizon);

        return
            IBurnerLoans.ExtendPreview({
                fee: _extensionFee(dependencies_, context_),
                // forge-lint: disable-next-line(unsafe-typecast)
                maturity: uint48(requestedMaturity),
                healthFactor: context_.health,
                executable: context_.executable
            });
    }

    function _validateMaturityHorizon(
        uint256 requestedMaturity_,
        uint48 maxMaturityHorizon_
    ) private view {
        uint256 maximumMaturity = block.timestamp + uint256(maxMaturityHorizon_);
        // This derived chain-time bound is only clamped to the uint48 storage range.
        // forge-lint: disable-next-line(block-timestamp)
        if (maximumMaturity > type(uint48).max) maximumMaturity = type(uint48).max;
        // Maturity horizons span protocol timeframes and tolerate normal validator drift.
        // forge-lint: disable-next-line(block-timestamp)
        if (requestedMaturity_ > maximumMaturity) {
            revert IBurnerLoans.BurnerLoans_MaturityHorizonExceeded(
                requestedMaturity_,
                maximumMaturity
            );
        }
    }

    function _validateActiveBorrowPosition(IFLOANv1.Position memory position_) private view {
        if (position_.principalDue == 0) return;

        // Loan maturity uses chain time and tolerates normal validator drift.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= position_.maturity) {
            revert IBurnerLoans.BurnerLoans_PositionMatured(position_.maturity);
        }
    }

    function _extensionFee(
        BurnerLoansContext memory dependencies_,
        ExtensionContext memory context_
    ) private view returns (uint256) {
        uint256 requiredUsd = BurnerLoansCalculator.requiredCollateralUsd(
            BurnerLoansCalculator.debtValueUsd(
                context_.debtOhm,
                context_.pricing.ohmUsdPrice,
                dependencies_.ohmDecimals
            ),
            context_.debtOhm,
            context_.pricing.backingPerOhmUsd,
            dependencies_.ohmDecimals,
            context_.config.maxLtvBps,
            context_.config.backingMultiplierBps
        );
        uint256 requiredAsset = BurnerLoansCalculator.requiredCollateralAsset(
            requiredUsd,
            context_.pricing.collateralUsdPrice,
            context_.config.collateralDecimals
        );
        uint256 feeRate = _feeRate(
            dependencies_.floan,
            context_.marketId,
            dependencies_.floan.getMarketPrincipalDue(context_.marketId),
            context_.config.debtCap
        );
        return BurnerLoansCalculator.borrowFee(requiredAsset, feeRate) * context_.termCount;
    }

    function _freshPrice(
        IPRICEv2 price_,
        address asset_,
        uint48 frequency_
    ) private view returns (uint256 price) {
        uint48 timestamp;
        (price, timestamp) = price_.getPrice(asset_, IPRICEv2.Variant.CURRENT);
        if (
            price == 0 ||
            timestamp == 0 ||
            // Price freshness windows tolerate normal validator timestamp drift.
            // forge-lint: disable-next-line(block-timestamp)
            block.timestamp > uint256(timestamp) + uint256(frequency_)
        ) {
            revert IBurnerLoans.BurnerLoans_InvalidPrice();
        }
    }

    function _directPricePair(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) private view returns (PricePair memory pricePair) {
        uint48 frequency = dependencies_.price.observationFrequency();
        pricePair.ohmUsdPrice = _freshPrice(
            dependencies_.price,
            address(dependencies_.ohm),
            frequency
        );
        pricePair.collateralUsdPrice = _freshPrice(dependencies_.price, asset_, frequency);
    }

    function _cachedPricePair(
        IPriceCache.CachedPrice memory cachedPrice_
    ) private pure returns (PricePair memory pricePair) {
        if (cachedPrice_.assetPriceUsd == 0 || cachedPrice_.quotePriceUsd == 0) {
            revert IBurnerLoans.BurnerLoans_InvalidPrice();
        }
        pricePair.ohmUsdPrice = cachedPrice_.assetPriceUsd;
        pricePair.collateralUsdPrice = cachedPrice_.quotePriceUsd;
    }

    function _isCachedPriceStale(
        IPriceCache.CachedPrice memory cachedPrice_,
        uint48 maxAge_
    ) private view returns (bool) {
        return
            cachedPrice_.updatedAt == 0 ||
            // Cache freshness windows tolerate normal validator timestamp drift.
            // forge-lint: disable-next-line(block-timestamp)
            block.timestamp > uint256(cachedPrice_.updatedAt) + uint256(maxAge_);
    }

    function _backingPerOhmUsd(address oracle_, IPRICEv2 price_) private view returns (uint256) {
        if (oracle_ == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        uint256 backing18 = IOlympusBackingOracle(oracle_).backing();
        if (backing18 == 0) revert IBurnerLoans.BurnerLoans_InvalidPrice();
        return FullMath.mulDivUp(backing18, BurnerLoansCalculator.scale(price_.decimals()), _WAD);
    }

    function _requireAssetConfigured(
        IFLOANv1 floan_,
        address facility_,
        address debtToken_,
        address asset_
    ) private view returns (uint32 marketId_, IBurnerLoans.AssetConfig memory config) {
        marketId_ = BurnerLoansMarketConfig.firstMarketId(floan_, facility_, asset_, debtToken_);
        IFLOANv1.Market memory market = floan_.getMarket(marketId_);
        config = BurnerLoansMarketConfig.assetConfig(
            marketId_,
            market,
            floan_.getMarketConfigData(marketId_)
        );
    }

    function _requireAssetOriginationsEnabled(
        IFLOANv1 floan_,
        address facility_,
        address debtToken_,
        address asset_
    ) private view returns (uint32 marketId_, IBurnerLoans.AssetConfig memory config) {
        (marketId_, config) = _requireAssetConfigured(floan_, facility_, debtToken_, asset_);
        if (!config.originationsEnabled)
            revert IBurnerLoans.BurnerLoans_AssetOriginationsDisabled(asset_);
    }

    function _dependencies() private view returns (BurnerLoansContext memory) {
        return IBurnerLoansSeizureContext(address(this)).context();
    }
}
