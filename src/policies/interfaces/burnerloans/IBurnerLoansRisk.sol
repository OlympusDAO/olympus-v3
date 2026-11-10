// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

/// @notice Replaceable pricing and economic calculations; custody and positions remain at Core/FLOAN.
/// @dev Calculation inputs are operation-local values supplied by the caller, not stored or authenticated
///      price snapshots. Installed actions supply the canonical FLOAN market ID; Risk validates its OHM
///      debt token, without checking a Core facility or borrower authorization. Calculations never settle funds.
interface IBurnerLoansRisk {
    // ========== EVENTS ========== //

    /// @notice Emitted when the canonical backing oracle is initially bound or replaced.
    /// @param backingOracle New backing oracle address.
    event BackingOracleSet(address indexed backingOracle);

    /// @notice Emitted when the optional PriceCache is initially bound, replaced, or cleared.
    /// @param priceCache New PriceCache policy, or zero for direct PRICE mode.
    event PriceCacheSet(address indexed priceCache);

    /// @notice Emitted when the maximum accepted cached-price age is initialized or changed.
    /// @param priceCacheMaxAge New maximum cached-price age, in seconds.
    event PriceCacheMaxAgeSet(uint48 priceCacheMaxAge);

    /// @notice Emitted when the shared referral percentage changes.
    /// @param bps Share of the upfront fee, with 10,000 equal to 100%.
    event ReferralFeeBpsSet(uint16 bps);

    /// @notice Emitted when a referrer's eligibility changes.
    /// @param referrer Address receiving the referral allocation.
    /// @param allowed Whether new operations may name this referrer.
    event ReferrerAllowedSet(address indexed referrer, bool allowed);

    // ========== ERRORS ========== //

    /// @notice The proposed Core is zero or does not support the required interface.
    /// @param core Invalid Core address.
    error BurnerLoansRisk_InvalidCore(address core);

    /// @notice The OHM token is absent or its decimals are unreadable or unsupported.
    /// @param token Invalid OHM token.
    error BurnerLoansRisk_InvalidOhm(address token);

    /// @notice The market's debt token differs from this calculator's OHM binding.
    /// @param marketId Invalid FLOAN market.
    error BurnerLoansRisk_InvalidMarket(uint32 marketId);

    /// @notice A required asset price is zero or otherwise invalid.
    error BurnerLoans_InvalidPrice();

    /// @notice The configured backing oracle lacks IBackingOracle or IVersioned.
    /// @param backingOracle Invalid backing oracle address.
    error BurnerLoans_InvalidBackingOracle(address backingOracle);

    /// @notice The supplied PriceCache lacks required interfaces or readable Kernel metadata.
    /// @param priceCache Invalid PriceCache address.
    error BurnerLoans_InvalidPriceCache(address priceCache);

    /// @notice A basis-point value exceeds the permitted range.
    /// @param bps Invalid basis-point value.
    error BurnerLoans_InvalidBps(uint256 bps);

    /// @notice A utilization fee configuration violates the required bounds.
    error BurnerLoans_InvalidFeeConfig();

    /// @notice The proposed referral share exceeds 100%.
    /// @param bps Invalid share, in basis points.
    error BurnerLoansRisk_InvalidReferralFeeBps(uint16 bps);

    /// @notice A nonzero referrer is not eligible for a new operation.
    /// @param referrer Rejected referral recipient.
    error BurnerLoansRisk_ReferrerNotAllowed(address referrer);

    /// @notice An operation requires a healthy position but the current or resulting position is unhealthy.
    /// @param healthFactor Current or resulting health factor, scaled by 1e18.
    error BurnerLoans_UnhealthyPosition(uint256 healthFactor);

    /// @notice A proposed final position is below its required health factor.
    /// @param healthFactor Resulting health factor, scaled by 1e18.
    error BurnerLoans_UnhealthyFinalPosition(uint256 healthFactor);

    // ========== STRUCTS ========== //

    /// @notice Mutable risk and term fields for a Burner Loans collateral market.
    /// @dev `maxKeeperReward` matches the `uint128` width used by FLOAN market configuration;
    ///      every representable value is valid, so no separate upper-bound check is required.
    /// @param maxLtvBps Maximum loan-to-value ratio applied to collateral value.
    /// @param backingMultiplierBps Multiplier applied to the protocol backing floor.
    /// @param keeperRewardBps Share of underlying-denominated seized collateral awarded to the keeper.
    /// @param termLength Duration added to the current timestamp for a new maturity.
    /// @param maxMaturityHorizon Maximum permitted distance between maturity and current time.
    /// @param maxKeeperReward Maximum keeper reward, in underlying collateral decimals.
    struct AssetRiskConfigInput {
        uint16 maxLtvBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint128 maxKeeperReward;
    }

    /// @notice Piecewise-linear utilization fee configuration.
    /// @param baseFeeBps Fee charged at zero utilization.
    /// @param kinkBps Utilization at which the fee slope changes.
    /// @param preKinkSlopeBps Fee increase across the utilization range below the kink.
    /// @param postKinkSlopeBps Fee increase across the utilization range above the kink.
    struct AssetFeeConfig {
        uint16 baseFeeBps;
        uint16 kinkBps;
        uint16 preKinkSlopeBps;
        uint16 postKinkSlopeBps;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Returns the debt token used for pricing and decimal conversion.
    /// @return token OHM token supplied at construction.
    function ohm() external view returns (address token);

    /// @notice Uses a fresh cached pair when available, otherwise direct PRICE; does not refresh cache.
    /// @param asset Configured underlying collateral token to price against OHM.
    /// @return prices Captured pair prices and protocol backing for one operation.
    function snapshot(
        address asset
    ) external view returns (IBurnerLoansCore.PriceSnapshot memory prices);

    /// @notice Policies refresh prices before reading positions and validating settlement; permissionless cache maintenance.
    /// @param asset Configured underlying collateral token to price against OHM.
    /// @return snapshot Captured pair prices and protocol backing for one operation.
    function refreshSnapshot(
        address asset
    ) external returns (IBurnerLoansCore.PriceSnapshot memory snapshot);

    /// @notice WAD-scaled health; zero principal returns the maximum uint256.
    /// @dev Snapshot USD values share the current PRICE decimal scale, which need not be 18.
    ///      That scale cancels in the value/requirement ratio; health always uses 18 decimals.
    /// @param snapshot Operation-local prices and backing; this function does not reread either.
    /// @param marketId Canonical FLOAN market selected by the caller; must use this Risk's OHM.
    /// @param collateral Position collateral credit in underlying token units.
    /// @param debt Position principal in OHM units.
    /// @return healthFactor Health scaled by 1e18, or uint256.max when debt is zero.
    function health(
        IBurnerLoansCore.PriceSnapshot calldata snapshot,
        uint32 marketId,
        uint256 collateral,
        uint256 debt
    ) external view returns (uint256 healthFactor);

    /// @notice Validates current or final position health against the WAD threshold.
    /// @param snapshot Operation-local prices and backing, obtained from this Risk implementation.
    /// @param marketId Canonical FLOAN market selected by the caller; must use this Risk's OHM.
    /// @param collateral Proposed collateral credit in underlying token units.
    /// @param debt Proposed principal in OHM units.
    /// @param finalPosition Whether this validates a proposed final position (borrow or withdrawal) rather than the current position.
    /// @return healthFactor Accepted position health scaled by 1e18.
    function validateHealth(
        IBurnerLoansCore.PriceSnapshot calldata snapshot,
        uint32 marketId,
        uint256 collateral,
        uint256 debt,
        bool finalPosition
    ) external view returns (uint256 healthFactor);

    /// @notice Fee in collateral units, rounded up per term; utilization uses pre-settlement market debt.
    /// @param snapshot Operation-local prices and backing.
    /// @param marketId Canonical FLOAN market selected by the caller; must use this Risk's OHM.
    /// @param principal Principal being charged, in OHM units.
    /// @param terms Number of configured terms charged.
    /// @param referrer Referral recipient, or zero for protocol-only allocation.
    /// @return protocolFee Protocol remainder of the upfront fee, in underlying collateral units.
    /// @return referralFee Referral share rounded down, in underlying collateral units.
    function fee(
        IBurnerLoansCore.PriceSnapshot calldata snapshot,
        uint32 marketId,
        uint256 principal,
        uint16 terms,
        address referrer
    ) external view returns (uint256 protocolFee, uint256 referralFee);

    /// @notice Returns the shared referral share of upfront fees.
    /// @return bps Percentage in basis points, where 10,000 is 100%.
    function referralFeeBps() external view returns (uint16 bps);

    /// @notice Returns eligibility for a supplied referral recipient.
    /// @param referrer Address whose eligibility is queried.
    /// @return allowed Whether new operations may name this address.
    function isReferrerAllowed(address referrer) external view returns (bool allowed);

    /// @notice Updates the shared referral share of future upfront fees.
    /// @param bps Share in basis points, where 10,000 is 100%.
    function setReferralFeeBps(uint16 bps) external;

    /// @notice Updates eligibility for future borrow and extension referrals.
    /// @param referrer Nonzero referral recipient.
    /// @param allowed Whether new operations may name this address.
    function setReferrerAllowed(address referrer, bool allowed) external;

    /// @notice Returns the keeper allocation from actual redemption output, preserving underlying/share rounding.
    /// @param snapshot Prices and backing captured before batch settlement.
    /// @param marketId Canonical FLOAN market selected by the caller; must use this Risk's OHM.
    /// @param debt Principal defaulted by the position, in OHM units.
    /// @param collateral Position collateral redeemed, in underlying token units.
    /// @param output Actual underlying tokens or vault shares received from redemption.
    /// @param protocolCaller Whether the caller receives no keeper reward.
    /// @return reward Keeper allocation in the same token units as output.
    function keeperReward(
        IBurnerLoansCore.PriceSnapshot calldata snapshot,
        uint32 marketId,
        uint256 debt,
        uint256 collateral,
        uint256 output,
        bool protocolCaller
    ) external view returns (uint256 reward);

    /// @notice Validates a proposed market risk and term configuration.
    /// @param config Proposed risk, maturity and keeper reward parameters.
    function validateRiskConfig(AssetRiskConfigInput calldata config) external pure;

    /// @notice Validates a proposed piecewise utilization fee curve.
    /// @param config Proposed base fee, utilization kink and slopes, in basis points.
    function validateFeeConfig(AssetFeeConfig calldata config) external pure;

    /// @notice Returns the selected protocol backing calculator.
    /// @return oracle Current backing oracle, which reports backing with 18 decimals.
    function backingOracle() external view returns (address oracle);

    /// @notice Returns the optional pair-price cache.
    /// @return cache Configured PriceCache policy, or zero for direct PRICE reads.
    function priceCache() external view returns (address cache);

    /// @notice Returns the maximum accepted age of a cached price pair.
    /// @return maxAge Cache freshness bound in seconds.
    function priceCacheMaxAge() external view returns (uint48 maxAge);

    /// @notice OCG ADMIN replaces pricing dependencies; Config cannot change these addresses.
    /// @param oracle Replacement backing calculator.
    function setBackingOracle(address oracle) external;

    /// @notice Selects the optional price cache using OCG ADMIN authority.
    /// @param cache Replacement PriceCache policy, or zero to use PRICE directly.
    function setPriceCache(address cache) external;

    /// @notice Selected configuration operator or OCG ADMIN updates the cache age.
    /// @param maxAge Maximum accepted cached pair age in seconds.
    function setPriceCacheMaxAge(uint48 maxAge) external;

    /// @notice Validates that the current PRICE module supports an asset.
    /// @param asset Collateral or OHM token proposed for pricing.
    function validatePriceSupport(address asset) external view;
}
