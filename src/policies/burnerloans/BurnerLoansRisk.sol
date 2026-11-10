// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {LoanMath} from "src/policies/burnerloans/libraries/LoanMath.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {LoanToken} from "src/policies/burnerloans/libraries/LoanToken.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @notice OCG-replaceable pricing and arithmetic. Owns oracle/cache bindings and cache age; no custody, positions or user authorization.
/// @dev Captures oracle inputs once, then evaluates caller-supplied snapshots against current FLOAN
///      market terms. Core is an immutable same-Kernel identity; its activity and enablement are independent.
contract BurnerLoansRisk is
    Policy,
    PolicyEnablerV2,
    ReEnablerGracePeriod,
    ConfigOperatorSingleStep,
    IBurnerLoansCoreBound,
    IBurnerLoansRisk,
    IVersioned
{
    /// @notice Permanent system identity used when Core admits this Risk implementation.
    /// @dev Risk does not call Core or depend on its lifecycle.
    address internal immutable _CORE;

    /// @notice Debt token used to validate markets and normalize principal values.
    address internal immutable _OHM;

    /// @notice Canonical market definitions and configuration resolved from the Kernel.
    IFLOANv1 internal _FLOAN;

    /// @notice Current Kernel price module, updated through configureDependencies.
    IPRICEv2 internal _PRICE;

    /// @inheritdoc IBurnerLoansRisk
    address public override backingOracle;

    /// @inheritdoc IBurnerLoansRisk
    address public override priceCache;

    /// @inheritdoc IBurnerLoansRisk
    uint48 public override priceCacheMaxAge;

    /// @inheritdoc IBurnerLoansRisk
    uint16 public override referralFeeBps;

    mapping(address referrer => bool allowed) internal _referrersAllowed;

    /// @notice Native OHM precision captured at deployment for principal conversions.
    uint8 internal immutable _OHM_DECIMALS;

    /// @notice Decimal scale used for backing observations and health factors.
    uint256 internal constant _WAD = 1e18;

    /// @notice Basis-point scale used for ratios and fees.
    uint256 internal constant _BPS = 10_000;

    /// @notice Binds Kernel, OHM and pricing dependencies; starts disabled.
    /// @dev Reverts if:
    ///      - Core is zero, lacks its interface, reports another Kernel or has unreadable Kernel metadata.
    ///      - OHM has no code, its decimals cannot be read or exceed the supported token precision.
    ///      - The backing oracle or nonzero cache fails interface/Kernel validation.
    /// @param kernel_ Kernel providing ROLES, PRICE and FLOAN.
    /// @param ohm_ Debt token priced and used by this calculator's markets.
    /// @param backingOracle_ Canonical backing oracle.
    /// @param priceCache_ Optional same-Kernel price cache; zero uses PRICE directly.
    /// @param maxAge_ Maximum cached-price age in seconds.
    /// @param core_ Deployed same-Kernel Core identity; its activity and enablement are not queried.
    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        // The oracle validator rejects zero via code-length and interface checks.
        // forge-lint: disable-next-line(missing-zero-check)
        address backingOracle_,
        // Zero intentionally clears the optional cache and selects live PRICE reads.
        // forge-lint: disable-next-line(missing-zero-check)
        address priceCache_,
        uint48 maxAge_,
        address core_
    ) Policy(kernel_) ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD) {
        if (core_ == address(0)) revert BurnerLoansRisk_InvalidCore(core_);
        _validateCore(core_);
        _CORE = core_;
        (bool validOhm, uint8 decimals) = LoanToken.readDecimals(address(ohm_));
        if (!validOhm) revert BurnerLoansRisk_InvalidOhm(address(ohm_));
        _OHM = address(ohm_);
        _OHM_DECIMALS = decimals;
        _validateBackingOracle(backingOracle_);
        _validatePriceCache(priceCache_);
        backingOracle = backingOracle_;
        priceCache = priceCache_;
        priceCacheMaxAge = maxAge_;
        emit BackingOracleSet(backingOracle_);
        emit PriceCacheSet(priceCache_);
        emit PriceCacheMaxAgeSet(maxAge_);
    }

    /// @inheritdoc IBurnerLoansCoreBound
    function core() public view override returns (address) {
        return _CORE;
    }

    /// @inheritdoc IBurnerLoansRisk
    function ohm() external view returns (address) {
        return _OHM;
    }

    /// @notice Resolves Kernel modules used for authorization, prices and market reads.
    /// @dev Reverts if:
    ///      - A required module is missing or has an incompatible version.
    ///      - PRICE decimals cannot be represented as a uint256 decimal scale.
    /// @return dependencies ROLES, PRICE and FLOAN keycodes.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("FLOAN");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        _PRICE = IPRICEv2(getModuleAddress(dependencies[1]));
        _FLOAN = IFLOANv1(getModuleAddress(dependencies[2]));
        // Only the module major version determines compatibility.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        (uint8 priceMajor, uint8 priceMinor) = Module(address(_PRICE)).VERSION();
        // Only the module major version determines compatibility.
        // forge-lint: disable-next-line(unused-return)
        (uint8 loanMajor, ) = Module(address(_FLOAN)).VERSION();
        bool compatiblePrice = priceMajor == 2 || (priceMajor == 1 && priceMinor == 2);
        if (rolesMajor != 1 || !compatiblePrice || loanMajor != 1)
            revert Policy_WrongModuleVersion(abi.encode([1, 2, 1]));
        LoanMath.scale(_PRICE.decimals());
    }

    /// @notice Declares no module write permissions; Risk reads canonical market state.
    /// @return Permissions[] Empty permission array.
    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }

    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    modifier onlyOperational() {
        _requireOperational();
        _;
    }

    function _requireOperational() private view {
        _requireActive();
        _requireEnabled();
    }

    /// @notice Requires this policy active before configuration or enablement.
    /// @dev Reverts if:
    ///      - The subject policy is Kernel-inactive; the error identifies that policy.
    function _requireActive() private view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - A required dependency read or numeric conversion fails.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function snapshot(
        address asset_
    ) external view onlyOperational returns (IBurnerLoansCore.PriceSnapshot memory prices) {
        IPRICEv2 price = _PRICE;
        address cache = priceCache;
        bool cached;
        if (_cacheOperational(cache)) {
            IPriceCache.CachedPrice memory pair = IPriceCache(cache).getCachedPrice(_OHM, asset_);
            if (
                // Chain time defines this maturity/freshness boundary; its equality behavior is intentional.
                // forge-lint: disable-next-line(block-timestamp)
                pair.updatedAt != 0 && block.timestamp <= uint256(pair.updatedAt) + priceCacheMaxAge
            ) {
                (prices.ohmUsdPrice, prices.collateralUsdPrice) = _cachedPrices(pair);
                cached = true;
            }
        }
        if (!cached) {
            // Missing, disabled or stale cache data falls back to PRICE without mutating the cache.
            // An invalid price in a selected fresh pair above is an error, not a fallback condition.
            prices.ohmUsdPrice = _freshPrice(price, _OHM);
            prices.collateralUsdPrice = _freshPrice(price, asset_);
        }
        return _completeSnapshot(price, prices);
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - A required dependency read or numeric conversion fails.
    ///      Permissionless cache maintenance, like PriceCache; calculators never refresh or reread backing.
    function refreshSnapshot(
        address asset_
    ) external onlyOperational returns (IBurnerLoansCore.PriceSnapshot memory snapshot) {
        IPRICEv2 price = _PRICE;
        address cache = priceCache;
        // Execution may refresh the shared pair; snapshot() is the read-only alternative. Both paths
        // attach backing in the same PRICE scale before any downstream health or fee calculation.
        if (_cacheOperational(cache)) {
            IPriceCache.CachedPrice memory pair = IPriceCache(cache).cachePriceIfNecessary(
                _OHM,
                asset_,
                priceCacheMaxAge
            );
            (snapshot.ohmUsdPrice, snapshot.collateralUsdPrice) = _cachedPrices(pair);
        } else {
            snapshot.ohmUsdPrice = _freshPrice(price, _OHM);
            snapshot.collateralUsdPrice = _freshPrice(price, asset_);
        }
        return _completeSnapshot(price, snapshot);
    }

    /// @notice Adds a scaled canonical backing value to the captured price pair.
    /// @dev Reverts if:
    ///      - A required asset price is zero or otherwise invalid.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param price_ Current PRICE module.
    /// @param snapshot_ Captured operation price/backing values, all in the same PRICE decimal scale.
    /// @return IBurnerLoansCore.PriceSnapshot Captured OHM/collateral prices and backing, all in PRICE decimals.
    function _completeSnapshot(
        IPRICEv2 price_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_
    ) private view returns (IBurnerLoansCore.PriceSnapshot memory) {
        _requireBackingOracleReady();
        uint256 backing18 = IBackingOracle(backingOracle).backing();
        if (backing18 == 0) revert IBurnerLoansRisk.BurnerLoans_InvalidPrice();
        // backing: 18 decimals -> PRICE decimals, rounded up in favor of the protocol.
        snapshot_.backingPerOhmUsd = Math.mulDiv(
            backing18,
            LoanMath.scale(price_.decimals()),
            _WAD,
            Math.Rounding.Ceil
        );
        return snapshot_;
    }

    /// @notice Checks whether the selected cache is active and enabled.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param cache_ Optional price cache address.
    /// @return bool Whether the configured cache is active and enabled.
    function _cacheOperational(address cache_) private view returns (bool) {
        return
            cache_ != address(0) &&
            kernel.isPolicyActive(Policy(cache_)) &&
            IEnabler(cache_).isEnabled();
    }

    /// @notice Reads a nonzero PRICE observation within its configured freshness window.
    /// @dev Reverts if:
    ///      - A required asset price is zero or otherwise invalid.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param price_ Current PRICE module.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @return price Nonzero fresh USD price in current PRICE decimals.
    function _freshPrice(IPRICEv2 price_, address asset_) private view returns (uint256 price) {
        uint48 timestamp;
        (price, timestamp) = price_.getPrice(asset_, IPRICEv2.Variant.CURRENT);
        if (
            price == 0 ||
            timestamp == 0 ||
            // Chain time defines this maturity/freshness boundary; its equality behavior is intentional.
            // forge-lint: disable-next-line(block-timestamp)
            block.timestamp > uint256(timestamp) + price_.observationFrequency()
        ) revert IBurnerLoansRisk.BurnerLoans_InvalidPrice();
    }

    /// @notice Validates the cached pair and returns its nonzero prices.
    /// @dev Reverts if:
    ///      - A required asset price is zero or otherwise invalid.
    ///      No external state or token calls; checked arithmetic errors propagate.
    /// @param pair_ Cached OHM/collateral price pair.
    /// @return uint256 OHM USD price in PRICE decimals.
    /// @return uint256 Collateral USD price in the same PRICE decimals.
    function _cachedPrices(
        IPriceCache.CachedPrice memory pair_
    ) private pure returns (uint256, uint256) {
        if (pair_.assetPriceUsd == 0 || pair_.quotePriceUsd == 0)
            revert IBurnerLoansRisk.BurnerLoans_InvalidPrice();
        return (pair_.assetPriceUsd, pair_.quotePriceUsd);
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - A required dependency read or numeric conversion fails.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function health(
        IBurnerLoansCore.PriceSnapshot calldata snapshot_,
        uint32 marketId_,
        uint256 collateral_,
        uint256 debt_
    ) external view onlyOperational returns (uint256) {
        return _health(snapshot_, marketId_, collateral_, debt_);
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - A proposed final position is below its required health factor.
    ///      - An operation requires a healthy position but the current or resulting position is unhealthy.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function validateHealth(
        IBurnerLoansCore.PriceSnapshot calldata snapshot_,
        uint32 marketId_,
        uint256 collateral_,
        uint256 debt_,
        bool finalPosition_
    ) external view onlyOperational returns (uint256 healthFactor) {
        healthFactor = _health(snapshot_, marketId_, collateral_, debt_);
        if (healthFactor < _WAD) {
            if (finalPosition_)
                revert IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition(healthFactor);
            revert IBurnerLoansRisk.BurnerLoans_UnhealthyPosition(healthFactor);
        }
    }

    /// @notice Computes WAD-scaled health from captured prices and canonical market parameters.
    /// @dev The shared PRICE scale cancels in the ratio; the result has 18 decimals.
    /// @dev Debt-free positions return max uint without querying market configuration.
    /// @dev Reverts if:
    ///      - A debt-bearing position has an invalid canonical market configuration.
    ///      - The collateral-value or required-value calculation overflows or has an invalid denominator.
    ///
    /// @param snapshot_ Captured operation price/backing values, all in the same PRICE decimal scale.
    /// @param marketId_ Canonical FLOAN market.
    /// @param collateral_ Asset-denominated position collateral.
    /// @param debt_ Outstanding principal in OHM units.
    /// @return uint256 Health ratio scaled by 1e18 and rounded down; max uint when debt-free.
    function _health(
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        uint32 marketId_,
        uint256 collateral_,
        uint256 debt_
    ) private view returns (uint256) {
        if (debt_ == 0) return type(uint256).max;
        (IBurnerLoansCore.AssetConfig memory cfg, ) = _configuration(marketId_);
        uint256 collateralUsd = LoanMath.collateralValue(
            collateral_,
            snapshot_.collateralUsdPrice,
            cfg.collateralDecimals
        );
        return LoanMath.healthFactor(collateralUsd, _requiredUsd(snapshot_, cfg, debt_));
    }

    /// @notice Computes the larger market-LTV and backing collateral requirement.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param snapshot_ Captured operation price/backing values, all in the same PRICE decimal scale.
    /// @param cfg_ Decoded canonical market configuration.
    /// @param debt_ Outstanding principal in OHM units.
    /// @return uint256 Required collateral value in PRICE-decimal USD, rounded up.
    function _requiredUsd(
        IBurnerLoansCore.PriceSnapshot memory snapshot_,
        IBurnerLoansCore.AssetConfig memory cfg_,
        uint256 debt_
    ) private view returns (uint256) {
        _requireBackingOracleReady();
        uint8 decimals = _OHM_DECIMALS;
        return
            LoanMath.requiredCollateralValue(
                LoanMath.debtValue(debt_, snapshot_.ohmUsdPrice, decimals),
                debt_,
                snapshot_.backingPerOhmUsd,
                decimals,
                cfg_.maxLtvBps,
                cfg_.backingMultiplierBps
            );
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - A debt cap is invalid for the requested operation.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function fee(
        IBurnerLoansCore.PriceSnapshot calldata snapshot_,
        uint32 marketId_,
        uint256 principal_,
        uint16 terms_,
        address referrer_
    ) external view onlyOperational returns (uint256 protocolFee, uint256 referralFee) {
        (
            IBurnerLoansCore.AssetConfig memory cfg,
            IBurnerLoansRisk.AssetFeeConfig memory curve
        ) = _configuration(marketId_);
        uint256 debt = _FLOAN.getMarketPrincipalDue(marketId_);
        // Price inputs are fixed by the supplied snapshot, while utilization comes from live market
        // debt. For a borrow action this is the utilization before Core adds the requested principal.
        uint256 utilization = LoanMath.assetUtilizationWad(debt, cfg.debtCap);
        if (utilization > _WAD) revert IBurnerLoansErrors.BurnerLoans_InvalidCap();
        uint256 feeRate = LoanMath.feeRateWad(
            utilization,
            curve.baseFeeBps,
            curve.kinkBps,
            curve.preKinkSlopeBps,
            curve.postKinkSlopeBps
        );
        if (snapshot_.collateralUsdPrice == 0) revert BurnerLoans_InvalidPrice();
        uint256 requiredAssets = LoanMath.requiredCollateralAsset(
            _requiredUsd(snapshot_, cfg, principal_),
            snapshot_.collateralUsdPrice,
            cfg.collateralDecimals
        );
        // Required collateral units times WAD fee; round each term up before multiplying.
        uint256 totalFee = LoanMath.borrowFee(requiredAssets, feeRate) * terms_;
        if (referrer_ != address(0)) {
            if (!_referrersAllowed[referrer_]) revert BurnerLoansRisk_ReferrerNotAllowed(referrer_);
            // Raw collateral units * BPS / BPS = raw collateral units. Full precision avoids
            // phantom overflow; flooring leaves the residual with the protocol.
            referralFee = Math.mulDiv(totalFee, referralFeeBps, _BPS);
        }
        protocolFee = totalFee - referralFee;
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - A required dependency read or numeric conversion fails.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function keeperReward(
        IBurnerLoansCore.PriceSnapshot calldata snapshot_,
        uint32 marketId_,
        uint256 debt_,
        uint256 collateral_,
        uint256 output_,
        bool protocolCaller_
    ) external view onlyOperational returns (uint256 reward) {
        (IBurnerLoansCore.AssetConfig memory cfg, ) = _configuration(marketId_);
        if (protocolCaller_ || cfg.keeperRewardBps == 0 || cfg.maxKeeperReward == 0) return 0;
        _requireBackingOracleReady();
        // Configure and cap rewards in underlying collateral units even when redemption pays shares.
        // Protect backing first, then convert the permitted reward to actual output units below.
        uint256 rewardBasis = cfg.withdrawAsShares ? collateral_ : output_;
        reward = Math.mulDiv(rewardBasis, cfg.keeperRewardBps, _BPS);
        if (reward > cfg.maxKeeperReward) reward = cfg.maxKeeperReward;
        uint256 requiredBackingUsd = LoanMath.requiredBackingValue(
            debt_,
            snapshot_.backingPerOhmUsd,
            _OHM_DECIMALS,
            cfg.backingMultiplierBps
        );
        uint256 requiredBackingAssets = LoanMath.requiredCollateralAsset(
            requiredBackingUsd,
            snapshot_.collateralUsdPrice,
            cfg.collateralDecimals
        );
        uint256 surplus = rewardBasis > requiredBackingAssets
            ? rewardBasis - requiredBackingAssets
            : 0;
        if (reward > surplus) reward = surplus;
        // Underlying units -> output shares, round down so the remainder goes to Treasury.
        return
            cfg.withdrawAsShares
                ? (collateral_ == 0 ? 0 : Math.mulDiv(output_, reward, collateral_))
                : reward;
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Validates locally without external calls.
    /// @dev Reverts if:
    ///      - maxLtvBps is zero or exceeds 10,000.
    ///      - backingMultiplierBps is outside the permitted backing-multiplier range.
    ///      - keeperRewardBps exceeds 10,000.
    ///      - termLength is zero or exceeds the maximum term length.
    ///      - maxMaturityHorizon does not exceed termLength.
    ///      - maxMaturityHorizon exceeds the maximum horizon.
    function validateRiskConfig(
        IBurnerLoansRisk.AssetRiskConfigInput calldata config_
    ) external pure {
        if (config_.maxLtvBps == 0 || config_.maxLtvBps > _BPS)
            revert IBurnerLoansRisk.BurnerLoans_InvalidBps(config_.maxLtvBps);
        if (
            config_.backingMultiplierBps < _BPS ||
            config_.backingMultiplierBps > LoanParameters._MAX_BACKING_MULTIPLIER_BPS
        ) revert IBurnerLoansErrors.BurnerLoans_InvalidParam();
        if (config_.keeperRewardBps > _BPS)
            revert IBurnerLoansRisk.BurnerLoans_InvalidBps(config_.keeperRewardBps);
        if (
            config_.termLength == 0 ||
            config_.termLength > LoanParameters._MAX_TERM_LENGTH ||
            config_.maxMaturityHorizon <= config_.termLength ||
            config_.maxMaturityHorizon > LoanParameters._MAX_MATURITY_HORIZON
        ) revert IBurnerLoansErrors.BurnerLoans_InvalidParam();
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Validates locally without external calls.
    /// @dev Reverts if:
    ///      - baseFeeBps exceeds 10,000.
    ///      - preKinkSlopeBps exceeds 10,000.
    ///      - postKinkSlopeBps exceeds 10,000.
    ///      - kinkBps is at least 10,000.
    ///      - kinkBps is zero and either utilization slope is nonzero.
    ///      - The base fee and both utilization slopes sum to more than 10,000.
    function validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig calldata config_) external pure {
        if (config_.baseFeeBps > _BPS)
            revert IBurnerLoansRisk.BurnerLoans_InvalidBps(config_.baseFeeBps);
        if (config_.preKinkSlopeBps > _BPS)
            revert IBurnerLoansRisk.BurnerLoans_InvalidBps(config_.preKinkSlopeBps);
        if (config_.postKinkSlopeBps > _BPS)
            revert IBurnerLoansRisk.BurnerLoans_InvalidBps(config_.postKinkSlopeBps);
        if (
            config_.kinkBps >= _BPS ||
            (config_.kinkBps == 0 &&
                (config_.preKinkSlopeBps != 0 || config_.postKinkSlopeBps != 0)) ||
            uint256(config_.baseFeeBps) + config_.preKinkSlopeBps + config_.postKinkSlopeBps > _BPS
        ) revert IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig();
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - A required asset price is zero or otherwise invalid.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function validatePriceSupport(address asset_) external view onlyOperational {
        IPRICEv2 price = _PRICE;
        if (
            !IERC165(address(price)).supportsInterface(type(IPRICEv2).interfaceId) ||
            !price.isAssetApproved(asset_)
        ) revert IBurnerLoansRisk.BurnerLoans_InvalidPrice();
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    ///      - The oracle has no code, lacks IBackingOracle/IEnabler or reports a different Kernel.
    ///      - The oracle Kernel metadata is invalid.
    function setBackingOracle(
        // The oracle validator rejects zero via code-length and interface checks.
        // forge-lint: disable-next-line(missing-zero-check)
        address oracle_
    ) external {
        _onlyAdmin();
        if (oracle_ == backingOracle)
            revert IBurnerLoansErrors.BurnerLoans_UnchangedAddress(oracle_);
        _validateBackingOracle(oracle_);
        backingOracle = oracle_;
        emit IBurnerLoansRisk.BackingOracleSet(oracle_);
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    ///      - A nonzero cache lacks IPriceCache/IEnabler/IVersioned or reports another Kernel.
    ///      - The cache Kernel getter fails or returns malformed data.
    function setPriceCache(
        // Zero intentionally clears the optional cache and selects live PRICE reads.
        // forge-lint: disable-next-line(missing-zero-check)
        address cache_
    ) external {
        _onlyAdmin();
        if (cache_ == priceCache) revert IBurnerLoansErrors.BurnerLoans_UnchangedAddress(cache_);
        _validatePriceCache(cache_);
        priceCache = cache_;
        emit IBurnerLoansRisk.PriceCacheSet(cache_);
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is inactive or locally disabled.
    ///      - Caller is neither the selected nonzero config operator nor ADMIN.
    function setPriceCacheMaxAge(uint48 age_) external {
        _requireConfigAuthority();
        if (priceCacheMaxAge == age_) return;
        priceCacheMaxAge = age_;
        emit IBurnerLoansRisk.PriceCacheMaxAgeSet(age_);
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - The caller is neither ADMIN nor the current nonzero config operator.
    ///      - The referral share exceeds 10,000 basis points.
    function setReferralFeeBps(uint16 bps_) external {
        _requireConfigAuthority();
        if (bps_ > _BPS) revert BurnerLoansRisk_InvalidReferralFeeBps(bps_);
        if (referralFeeBps == bps_) return;
        referralFeeBps = bps_;
        emit ReferralFeeBpsSet(bps_);
    }

    /// @inheritdoc IBurnerLoansRisk
    function isReferrerAllowed(address referrer_) external view returns (bool) {
        return _referrersAllowed[referrer_];
    }

    /// @inheritdoc IBurnerLoansRisk
    /// @dev Reverts if:
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - The caller is neither ADMIN nor the current nonzero config operator.
    ///      - The referrer is the zero address.
    function setReferrerAllowed(address referrer_, bool allowed_) external {
        _requireConfigAuthority();
        if (referrer_ == address(0)) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
        if (_referrersAllowed[referrer_] == allowed_) return;
        _referrersAllowed[referrer_] = allowed_;
        emit ReferrerAllowedSet(referrer_, allowed_);
    }

    /// @notice Requires local readiness and either selected operator or direct governance authority.
    /// @dev Reverts if:
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - The caller is neither ADMIN nor the current nonzero config operator.
    function _requireConfigAuthority() private view {
        _requireActive();
        _requireEnabled();
        if ((msg.sender != configOperator || configOperator == address(0)) && !_isAdmin(msg.sender))
            revert IPolicyAdmin.NotAuthorised();
    }

    /// @inheritdoc ConfigOperatorSingleStep
    /// @dev Reverts if:
    ///      - Risk is inactive or the caller lacks ADMIN.
    ///      Does not query the upstream controller's identity or lifecycle.
    function _authorizeSetConfigOperator() internal view override returns (bool) {
        _onlyAdmin();
        return true;
    }

    /// @notice Requires governance ADMIN authority.
    /// @dev Reverts if:
    ///      - The caller lacks the required Kernel role.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function _onlyAdmin() private view {
        _requireActive();
        _requireRole(msg.sender, ADMIN_ROLE);
    }

    /// @notice Validates backing-oracle interfaces and Kernel binding without requiring readiness.
    /// @dev Reverts if:
    ///      - The configured backing oracle lacks IBackingOracle or IEnabler.
    ///      - Its Kernel metadata is invalid or reports a different Kernel.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param oracle_ Canonical backing-oracle dependency.
    function _validateBackingOracle(address oracle_) private view {
        if (
            oracle_.code.length == 0 ||
            !ERC165Checker.supportsInterface(oracle_, type(IBackingOracle).interfaceId) ||
            !ERC165Checker.supportsInterface(oracle_, type(IEnabler).interfaceId)
        ) revert IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle(oracle_);
        PolicyDependency.requireSameKernel(oracle_, address(kernel));
    }

    /// @notice Revalidates the operational backing policy before consuming current or captured backing.
    /// @dev Reverts for invalid metadata, a foreign Kernel, inactivity or local disablement.
    function _requireBackingOracleReady() private view {
        PolicyDependency.requireActiveAndEnabled(backingOracle, address(kernel));
    }

    /// @notice Validates optional cache interfaces and Kernel binding.
    /// @dev Reverts if:
    ///      - The supplied PriceCache does not implement the required interfaces.
    ///      - A dependency reports a Kernel different from Burner Loans' Kernel.
    ///      Failed or malformed Kernel reads use InvalidPriceCache.
    /// @param cache_ Optional price cache address.
    function _validatePriceCache(address cache_) private view {
        if (cache_ == address(0)) return;
        if (
            !ERC165Checker.supportsInterface(cache_, type(IPriceCache).interfaceId) ||
            !ERC165Checker.supportsInterface(cache_, type(IEnabler).interfaceId) ||
            !ERC165Checker.supportsInterface(cache_, type(IVersioned).interfaceId)
        ) revert IBurnerLoansRisk.BurnerLoans_InvalidPriceCache(cache_);
        // Cache activity is checked when consumed; stale old-Kernel membership cannot prove this binding.
        PolicyDependency.requireSameKernel(cache_, address(kernel));
    }

    /// @notice Reads risk and fee configuration directly from the canonical FLOAN market.
    /// @dev Reverts if:
    ///      - The market is missing, uses another debt token or has incompatible config data.
    /// @param marketId_ Canonical market selected by the public action.
    /// @return IBurnerLoansCore.AssetConfig Canonical risk configuration.
    /// @return IBurnerLoansRisk.AssetFeeConfig Canonical fee configuration.
    function _configuration(
        uint32 marketId_
    )
        private
        view
        returns (IBurnerLoansCore.AssetConfig memory, IBurnerLoansRisk.AssetFeeConfig memory)
    {
        IFLOANv1.Market memory stored = _FLOAN.getMarket(marketId_);
        if (stored.debtToken != _OHM) revert BurnerLoansRisk_InvalidMarket(marketId_);
        bytes memory data = _FLOAN.getMarketConfigData(marketId_);
        return (
            LoanMarket.assetConfig(marketId_, stored, data),
            LoanMarket.feeConfig(marketId_, stored, data)
        );
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Payload is nonempty.
    ///      - Risk is inactive or Core/oracle/cache bindings are invalid.
    ///      An inactive/disabled optional cache is allowed: pricing falls back to PRICE.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
        _validateActivation();
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///      Deactivation or broken dependencies cannot prevent a pause.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @dev Construction and activation require Core compatibility without operational readiness.
    function _validateCore(address core_) private view {
        if (!ERC165Checker.supportsInterface(core_, type(IBurnerLoansCore).interfaceId))
            revert BurnerLoansRisk_InvalidCore(core_);
        PolicyDependency.requireSameKernel(core_, address(kernel));
    }

    /// @notice Validates Risk's own policy state, Core compatibility and direct pricing bindings.
    /// @dev Reverts if:
    ///      - Risk is Kernel-inactive.
    ///      - Core interface or Kernel compatibility is invalid.
    ///      - The backing oracle binding is incompatible, inactive or disabled.
    ///      - A nonzero price-cache binding is incompatible.
    function _validateActivation() private view {
        _requireActive();
        _validateCore(_CORE);
        _validateBackingOracle(backingOracle);
        _requireBackingOracleReady();
        _validatePriceCache(priceCache);
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The inclusive grace deadline exceeds uint48.
    ///      - The inclusive grace deadline has expired.
    ///      - Risk is Kernel-inactive.
    ///      - Core interface or Kernel compatibility is invalid.
    ///      - The backing oracle binding is incompatible, inactive or disabled.
    ///      - A nonzero price-cache binding is incompatible.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateActivation();
    }

    /// @notice Authorizes fast re-enablement.
    /// @dev Reverts if:
    ///      - Caller has neither ADMIN nor the Burner Loans admin role.
    function _authorizeReEnable() internal view override {
        if (!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE))
            revert NotAuthorised();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override {
        _requireActive();
        super.setGracePeriod(period_);
    }

    /// @dev The public setter first applies activity and local enablement checks.
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The widened deadline cannot fit uint48 (SafeCast overflow).
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansRisk).interfaceId ||
            interfaceId_ == type(IBurnerLoansCoreBound).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
