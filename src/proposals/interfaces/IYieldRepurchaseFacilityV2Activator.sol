// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";

/// @title IYieldRepurchaseFacilityV2Activator
/// @notice The interface of the one-use launcher of the YieldRepurchaseFacilityV2 stack: the
///         facility, its configuration policy, its config timelock, and the BackingOracle with
///         its config timelock. One call of `activate` migrates the weekly cycle of the
///         YieldRepurchaseFacility v1.2 into the facility and brings the five policies into
///         service.
/// @dev The launcher is bound at construction to the deployed contracts and to the launch
///      values, and exposes both through `deployment` and `launchParameters`. `activate` is
///      intended to be callable once, by the governance timelock, while the launcher holds the
///      `admin` and `loop_daddy` roles; the caller is expected to grant both roles before the
///      call and to revoke them after it.
///
///      `checkPreconditions` reports whether the state of the chain allows the launch. It reads
///      everything `activate` requires except the two roles of the launcher.
interface IYieldRepurchaseFacilityV2Activator is IERC165 {
    // ============ EVENTS ============ //

    /// @notice Emitted when the launch completes.
    /// @param epoch The epoch counter of the YieldRepurchaseFacility v1.2, at which the facility
    ///        resumes the weekly cycle.
    /// @param sUsdsNextYield The stored next yield of the YieldRepurchaseFacility v1.2, which the
    ///        sUSDS vault is registered with, in USDS (18 decimals).
    /// @param sUsdsPoolSeed The USDS value the YieldRepurchaseFacility v1.2 held, which seeds the
    ///        buyback pool of the sUSDS vault for the running week, in USDS (18 decimals).
    /// @param sUsdeNextYield The next yield the sUSDe vault is registered with, in USDe (18
    ///        decimals).
    event Activated(
        uint48 epoch,
        uint256 sUsdsNextYield,
        uint256 sUsdsPoolSeed,
        uint256 sUsdeNextYield
    );

    // ============ ERRORS ============ //

    /// @notice Thrown when a constructor argument is the zero address.
    /// @param parameter The name of the argument.
    error YieldRepurchaseFacilityV2Activator_ZeroAddress(string parameter);

    /// @notice Thrown when a constructor argument that has to be a contract holds no code.
    /// @param parameter The name of the argument.
    /// @param target The address without code.
    error YieldRepurchaseFacilityV2Activator_NotAContract(string parameter, address target);

    /// @notice Thrown when a bound contract does not report the binding the launch relies on.
    /// @param binding The name of the binding.
    /// @param actual The value the bound contract reports.
    /// @param expected The bound value it was compared with.
    error YieldRepurchaseFacilityV2Activator_BindingMismatch(
        string binding,
        address actual,
        address expected
    );

    /// @notice Thrown when the Clearinghouse list supplied at construction names the same
    ///         Clearinghouse twice.
    /// @param clearinghouse The Clearinghouse listed twice.
    error YieldRepurchaseFacilityV2Activator_DuplicateClearinghouse(address clearinghouse);

    /// @notice Thrown when `activate` is called by an account other than the timelock.
    /// @param caller The rejected caller.
    error YieldRepurchaseFacilityV2Activator_NotTimelock(address caller);

    /// @notice Thrown when the launch has already completed.
    error YieldRepurchaseFacilityV2Activator_AlreadyActivated();

    /// @notice Thrown when the next yield supplied for the sUSDe vault exceeds
    ///         `MAX_SUSDE_NEXT_YIELD`.
    /// @param nextYield The supplied next yield, in USDe (18 decimals).
    /// @param maximum The largest accepted next yield, in USDe (18 decimals).
    error YieldRepurchaseFacilityV2Activator_NextYieldTooHigh(uint256 nextYield, uint256 maximum);

    /// @notice Thrown when the launcher does not hold a role the launch requires.
    /// @param role The missing role.
    error YieldRepurchaseFacilityV2Activator_MissingRole(bytes32 role);

    /// @notice Thrown when a policy the launch relies on is not an active policy of the Kernel.
    /// @param policy The policy.
    error YieldRepurchaseFacilityV2Activator_PolicyNotActive(address policy);

    /// @notice Thrown when a policy the launch relies on being enabled is disabled.
    /// @param policy The policy.
    error YieldRepurchaseFacilityV2Activator_PolicyNotEnabled(address policy);

    /// @notice Thrown when a policy of the stack is enabled or has been enabled before.
    /// @param policy The policy.
    error YieldRepurchaseFacilityV2Activator_PolicyAlreadyEnabled(address policy);

    /// @notice Thrown when a binding the launch establishes is already set.
    /// @param binding The name of the binding.
    /// @param value The value found.
    error YieldRepurchaseFacilityV2Activator_AlreadyBound(string binding, address value);

    /// @notice Thrown when the facility is not authorized as a market callback on its bond
    ///         auctioneer.
    /// @param bondAuctioneer The bond auctioneer.
    error YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized(address bondAuctioneer);

    /// @notice Thrown when the YieldRepurchaseFacility v1.2 is shut down.
    error YieldRepurchaseFacilityV2Activator_V1ShutDown();

    /// @notice Thrown when the YieldRepurchaseFacility v1.2 reports a zero conversion rate
    ///         snapshot.
    error YieldRepurchaseFacilityV2Activator_V1ConversionRateUnset();

    /// @notice Thrown when the YieldRepurchaseFacility v1.2 is not a periodic task of the Heart.
    error YieldRepurchaseFacilityV2Activator_V1NotHeartTask();

    /// @notice Thrown when the facility is already a periodic task of the Heart.
    error YieldRepurchaseFacilityV2Activator_FacilityAlreadyHeartTask();

    /// @notice Thrown when the Clearinghouse list of the launcher is not the registry of the
    ///         CHREG module: the counts differ, or a registry entry is not listed.
    /// @param clearinghouse The registry entry that is not listed, or the zero address when the
    ///        counts differ.
    /// @param listedCount The number of Clearinghouses the launcher lists.
    /// @param registryCount The number of Clearinghouses in the registry.
    error YieldRepurchaseFacilityV2Activator_ClearinghouseRegistryMismatch(
        address clearinghouse,
        uint256 listedCount,
        uint256 registryCount
    );

    /// @notice Thrown when the `principalReceivables` of a Clearinghouse that the launch includes
    ///         or offsets cannot be read.
    /// @param clearinghouse The Clearinghouse.
    error YieldRepurchaseFacilityV2Activator_ClearinghouseReceivablesNotReadable(
        address clearinghouse
    );

    /// @notice Thrown when the receivables offset of a Clearinghouse exceeds its
    ///         `principalReceivables`.
    /// @param clearinghouse The Clearinghouse.
    /// @param offset The offset of the launch, in the units of the receivables.
    /// @param principalReceivables The `principalReceivables` read.
    error YieldRepurchaseFacilityV2Activator_ClearinghouseOffsetTooHigh(
        address clearinghouse,
        uint256 offset,
        uint256 principalReceivables
    );

    /// @notice Thrown when the PRICE module does not price OHM in a reserve token: the read
    ///         reverts or returns zero.
    /// @param reserve The reserve token.
    error YieldRepurchaseFacilityV2Activator_ReserveNotPriceable(address reserve);

    /// @notice Thrown when the USDe/USD price feed cannot be read with the registration
    ///         parameters, which includes an answer older than `USDE_FEED_UPDATE_THRESHOLD`.
    /// @param feed The price feed.
    /// @param reason The revert data of the failed read.
    error YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable(address feed, bytes reason);

    /// @notice Thrown when the USDe price of the feed deviates from `USDE_EXPECTED_PRICE` by
    ///         more than `USDE_PRICE_TOLERANCE_BPS`.
    /// @param price The USDe price read, in 18 decimals.
    /// @param expectedPrice The expected USDe price, in 18 decimals.
    /// @param toleranceBps The tolerance, in basis points.
    error YieldRepurchaseFacilityV2Activator_UsdePriceOutOfBounds(
        uint256 price,
        uint256 expectedPrice,
        uint16 toleranceBps
    );

    // ============ STRUCTS ============ //

    /// @notice The contracts the launch acts on.
    /// @param kernel The Kernel.
    /// @param backingOracle The BackingOracle policy.
    /// @param backingOracleConfigTimelock The BackingOracleConfigTimelock policy.
    /// @param config The YieldRepurchaseFacilityV2Config policy.
    /// @param configTimelock The YieldRepurchaseFacilityV2ConfigTimelock policy.
    /// @param facility The YieldRepurchaseFacilityV2 policy.
    /// @param yieldRepoV1 The YieldRepurchaseFacility v1.2 policy.
    /// @param heart The Heart policy.
    /// @param priceConfig The PriceConfig v2 policy.
    /// @param bondAuctioneer The Bond Protocol auctioneer of the facility.
    /// @param usdeUsdPriceFeed The Chainlink USDe/USD price feed.
    /// @param ohm The OHM token.
    /// @param usds The USDS token.
    /// @param sUsds The sUSDS vault.
    /// @param usde The USDe token.
    /// @param sUsde The sUSDe vault.
    struct Deployment {
        address kernel;
        address backingOracle;
        address backingOracleConfigTimelock;
        address config;
        address configTimelock;
        address facility;
        address yieldRepoV1;
        address heart;
        address priceConfig;
        address bondAuctioneer;
        address usdeUsdPriceFeed;
        address ohm;
        address usds;
        address sUsds;
        address usde;
        address sUsde;
    }

    /// @notice The launch values of a vault.
    /// @param yieldBuybackShare The share of the projected yield routed to buybacks (`1e18` =
    ///        100%).
    /// @param sellShares Whether the bond markets of the vault pay out the vault shares instead
    ///        of the reserve.
    struct AssetParameters {
        uint256 yieldBuybackShare;
        bool sellShares;
    }

    /// @notice The launch values of a Clearinghouse.
    /// @param clearinghouse The Clearinghouse address.
    /// @param included Whether the Clearinghouse is included in the backing yield regardless of
    ///        its reserve token.
    /// @param offset The cumulative receivables offset, in the units of the receivables.
    struct ClearinghouseParameters {
        address clearinghouse;
        bool included;
        uint256 offset;
    }

    /// @notice The values the launch configures.
    /// @param backing The backing value the BackingOracle is enabled with (USD per OHM, 18
    ///        decimals).
    /// @param initialDiscount The discount applied to the oracle price when a bond market opens
    ///        (`1e18` = 100%).
    /// @param maxPricePremium The premium over the oracle price at which the minimum price of a
    ///        bond market is placed (`1e18` = 100%).
    /// @param sUsds The launch values of the sUSDS vault, which becomes the backing vault.
    /// @param sUsde The launch values of the sUSDe vault.
    /// @param clearinghouses The launch values of the Clearinghouses.
    struct LaunchParameters {
        uint256 backing;
        uint256 initialDiscount;
        uint256 maxPricePremium;
        AssetParameters sUsds;
        AssetParameters sUsde;
        ClearinghouseParameters[] clearinghouses;
    }

    // ============ FUNCTIONS ============ //

    /// @notice Returns the largest next yield `activate` accepts for the sUSDe vault.
    /// @return maximum The largest next yield, in USDe (18 decimals).
    // solhint-disable-next-line func-name-mixedcase
    function MAX_SUSDE_NEXT_YIELD() external view returns (uint256 maximum);

    /// @notice Returns the update threshold the launch registers the USDe/USD price feed with
    ///         in the PRICE module.
    /// @return threshold The largest accepted age of the feed answer, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function USDE_FEED_UPDATE_THRESHOLD() external view returns (uint48 threshold);

    /// @notice Returns the USDe price the launch expects of the feed at registration.
    /// @return price The expected price, in 18 decimals.
    // solhint-disable-next-line func-name-mixedcase
    function USDE_EXPECTED_PRICE() external view returns (uint256 price);

    /// @notice Returns the tolerance of the feed price around `USDE_EXPECTED_PRICE` at
    ///         registration.
    /// @return toleranceBps The tolerance, in basis points.
    // solhint-disable-next-line func-name-mixedcase
    function USDE_PRICE_TOLERANCE_BPS() external view returns (uint16 toleranceBps);

    /// @notice Returns the account that `activate` accepts as its caller.
    /// @return timelock_ The timelock address.
    function timelock() external view returns (address timelock_);

    /// @notice Returns whether the launch has completed.
    /// @return activated Whether `activate` has completed.
    function isActivated() external view returns (bool activated);

    /// @notice Returns the contracts the launch acts on.
    /// @return deployment_ The bound contracts.
    function deployment() external view returns (Deployment memory deployment_);

    /// @notice Returns the values the launch configures.
    /// @return parameters The launch values.
    function launchParameters() external view returns (LaunchParameters memory parameters);

    /// @notice Reverts unless the state of the chain allows the launch.
    /// @dev The check covers everything `activate` requires except the roles of the launcher:
    ///      the bindings of the bound contracts, the five policies of the stack being active in
    ///      the Kernel, never enabled and unbound, the authorization of the facility as a
    ///      market callback, the Heart being active and enabled with the
    ///      YieldRepurchaseFacility v1.2 among its periodic tasks, the YieldRepurchaseFacility
    ///      v1.2 not being shut down and reporting a non-zero conversion rate snapshot, the
    ///      Clearinghouse list matching the registry of the CHREG module, and the PRICE module
    ///      pricing the reserves of both vaults, where USDe counts as priced when its feed
    ///      passes the registration checks.
    function checkPreconditions() external view;

    /// @notice Launches the stack, once: registers USDe in the PRICE module when it is not
    ///         registered, enables and binds the five policies, shuts the
    ///         YieldRepurchaseFacility v1.2 down and continues its weekly cycle in the facility,
    ///         registers the sUSDS and sUSDe vaults, configures the Clearinghouses, and hands
    ///         the periodic task slot of the YieldRepurchaseFacility v1.2 to the facility.
    /// @dev Intended to be callable by the timelock, while the launcher holds the `admin` and
    ///      `loop_daddy` roles.
    /// @param sUSDeNextYield_ The next yield the sUSDe vault is registered with, in USDe (18
    ///        decimals); at most `MAX_SUSDE_NEXT_YIELD`.
    function activate(uint256 sUSDeNextYield_) external;
}
