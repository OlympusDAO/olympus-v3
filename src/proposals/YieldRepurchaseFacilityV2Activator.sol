// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IBondAuctioneer} from "src/interfaces/IBondAuctioneer.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IYieldRepoV1} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepoV1.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2ConfigTimelock.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IYieldRepurchaseFacilityV2Write} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Write.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {toSubKeycode} from "src/Submodules.sol";
import {Deviation} from "src/libraries/Deviation.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ModuleWithSubmodules} from "src/Submodules.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title YieldRepurchaseFacilityV2Activator
/// @notice The one-use launcher of the YieldRepurchaseFacilityV2 stack. A single call of
///         `activate` from the governance timelock registers USDe in the PRICE module when it
///         is not registered, enables and binds the BackingOracle, its config timelock, the
///         configuration policy, its config timelock and the facility, shuts the
///         YieldRepurchaseFacility v1.2 down and continues its weekly cycle in the facility,
///         registers the sUSDS and sUSDe vaults, configures the Clearinghouses, and hands the
///         periodic task slot of the YieldRepurchaseFacility v1.2 in the Heart to the facility.
/// @dev The contracts and the launch values are fixed at construction and exposed through
///      `deployment` and `launchParameters`; the only value supplied at execution is the next
///      yield of the sUSDe vault, bounded by `MAX_SUSDE_NEXT_YIELD`.
///
///      The launcher calls functions gated to the `admin` role and `shutdown` of the
///      YieldRepurchaseFacility v1.2, gated to the `loop_daddy` role. It grants and revokes no
///      role: the caller grants both before `activate` and revokes them after it.
///
///      The state of the YieldRepurchaseFacility v1.2 (its epoch counter, its stored next yield,
///      its yield snapshots and its USDS and sUSDS balances) and the snapshots of the sUSDe
///      vault are read when `activate` runs. Everything else the launch relies on is a
///      precondition, checked by `checkPreconditions` and again by `activate`.
///
///      `shutdown` of the YieldRepurchaseFacility v1.2 burns the OHM it holds without a treasury
///      withdrawal, so the backing of that OHM stays in the treasury and does not enter the
///      buyback pool of the facility.
contract YieldRepurchaseFacilityV2Activator is IYieldRepurchaseFacilityV2Activator {
    // ============ CONSTANTS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    uint256 public constant override MAX_SUSDE_NEXT_YIELD = 100_000e18;

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    uint48 public constant override USDE_FEED_UPDATE_THRESHOLD = 1 days;

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    uint256 public constant override USDE_EXPECTED_PRICE = 1e18;

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    uint16 public constant override USDE_PRICE_TOLERANCE_BPS = 100;

    /// @notice The role `shutdown` of the YieldRepurchaseFacility v1.2 is gated to.
    bytes32 internal constant _LOOP_DADDY_ROLE = "loop_daddy";

    /// @notice The keycode of the PRICE submodule that reads Chainlink price feeds.
    bytes20 internal constant _CHAINLINK_SUBMODULE = "PRICE.CHAINLINK";

    /// @notice 100% in basis points.
    uint256 internal constant _ONE_HUNDRED_PERCENT_BPS = 10_000;

    /// @notice The base of the decimal scale of a token amount.
    uint256 internal constant _DECIMAL_BASE = 10;

    /// @notice The number of tokens `shutdown` of the YieldRepurchaseFacility v1.2 is asked to
    ///         transfer to the treasury: USDS and sUSDS.
    uint256 internal constant _V1_TOKEN_COUNT = 2;

    // ============ IMMUTABLES ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    // The name is the getter the interface declares
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable override timelock;

    address internal immutable _KERNEL;
    address internal immutable _BACKING_ORACLE;
    address internal immutable _BACKING_ORACLE_CONFIG_TIMELOCK;
    address internal immutable _CONFIG;
    address internal immutable _CONFIG_TIMELOCK;
    address internal immutable _FACILITY;
    address internal immutable _YIELD_REPO_V1;
    address internal immutable _HEART;
    address internal immutable _PRICE_CONFIG;
    address internal immutable _BOND_AUCTIONEER;
    address internal immutable _USDE_USD_PRICE_FEED;
    address internal immutable _OHM;
    address internal immutable _USDS;
    address internal immutable _SUSDS;
    address internal immutable _USDE;
    address internal immutable _SUSDE;

    /// @notice The backing value the BackingOracle is enabled with (USD per OHM, 18 decimals).
    uint256 internal immutable _BACKING;

    /// @notice The initial discount of the bond markets (`1e18` = 100%).
    uint256 internal immutable _INITIAL_DISCOUNT;

    /// @notice The maximum price premium of the bond markets (`1e18` = 100%).
    uint256 internal immutable _MAX_PRICE_PREMIUM;

    /// @notice The yield buyback share of the sUSDS vault (`1e18` = 100%).
    uint256 internal immutable _SUSDS_YIELD_BUYBACK_SHARE;

    /// @notice Whether the bond markets of the sUSDS vault pay out the vault shares.
    bool internal immutable _SUSDS_SELL_SHARES;

    /// @notice The yield buyback share of the sUSDe vault (`1e18` = 100%).
    uint256 internal immutable _SUSDE_YIELD_BUYBACK_SHARE;

    /// @notice Whether the bond markets of the sUSDe vault pay out the vault shares.
    bool internal immutable _SUSDE_SELL_SHARES;

    // ============ STATE ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    bool public override isActivated;

    /// @notice The launch values of the Clearinghouses, written by the constructor only.
    ClearinghouseParameters[] internal _clearinghouses;

    // ============ CONSTRUCTOR ============ //

    /// @notice Binds the launcher to the deployed contracts and to the launch values.
    /// @dev The stack does not have to be active in the Kernel yet: the constructor reads only
    ///      the bindings that the constructors of the bound contracts fix. The launch values
    ///      are stored as supplied; their bounds are enforced by the contracts that receive
    ///      them when `activate` runs.
    ///
    ///      Reverts if:
    ///      - `timelock_`, a member of `deployment_` or a listed Clearinghouse is the zero
    ///        address (`YieldRepurchaseFacilityV2Activator_ZeroAddress`).
    ///      - A member of `deployment_` holds no code
    ///        (`YieldRepurchaseFacilityV2Activator_NotAContract`).
    ///      - A Clearinghouse is listed twice
    ///        (`YieldRepurchaseFacilityV2Activator_DuplicateClearinghouse`).
    ///      - A binding listed at `_requireBindings` does not hold
    ///        (`YieldRepurchaseFacilityV2Activator_BindingMismatch`).
    /// @param timelock_ The governance timelock, the caller `activate` accepts.
    /// @param deployment_ The contracts the launch acts on.
    /// @param parameters_ The values the launch configures.
    // The timelock is rejected when zero by _requireNonZero, which the lint does not see
    // through. The first duplicate of the Clearinghouse list rejects the deployment.
    // forge-lint: disable-next-item(missing-zero-check,require-revert-in-loop)
    constructor(
        address timelock_,
        Deployment memory deployment_,
        LaunchParameters memory parameters_
    ) {
        _requireNonZero(timelock_, "timelock");
        _requireContract(deployment_.kernel, "kernel");
        _requireContract(deployment_.backingOracle, "backingOracle");
        _requireContract(deployment_.backingOracleConfigTimelock, "backingOracleConfigTimelock");
        _requireContract(deployment_.config, "config");
        _requireContract(deployment_.configTimelock, "configTimelock");
        _requireContract(deployment_.facility, "facility");
        _requireContract(deployment_.yieldRepoV1, "yieldRepoV1");
        _requireContract(deployment_.heart, "heart");
        _requireContract(deployment_.priceConfig, "priceConfig");
        _requireContract(deployment_.bondAuctioneer, "bondAuctioneer");
        _requireContract(deployment_.usdeUsdPriceFeed, "usdeUsdPriceFeed");
        _requireContract(deployment_.ohm, "ohm");
        _requireContract(deployment_.usds, "usds");
        _requireContract(deployment_.sUsds, "sUsds");
        _requireContract(deployment_.usde, "usde");
        _requireContract(deployment_.sUsde, "sUsde");

        timelock = timelock_;
        _KERNEL = deployment_.kernel;
        _BACKING_ORACLE = deployment_.backingOracle;
        _BACKING_ORACLE_CONFIG_TIMELOCK = deployment_.backingOracleConfigTimelock;
        _CONFIG = deployment_.config;
        _CONFIG_TIMELOCK = deployment_.configTimelock;
        _FACILITY = deployment_.facility;
        _YIELD_REPO_V1 = deployment_.yieldRepoV1;
        _HEART = deployment_.heart;
        _PRICE_CONFIG = deployment_.priceConfig;
        _BOND_AUCTIONEER = deployment_.bondAuctioneer;
        _USDE_USD_PRICE_FEED = deployment_.usdeUsdPriceFeed;
        _OHM = deployment_.ohm;
        _USDS = deployment_.usds;
        _SUSDS = deployment_.sUsds;
        _USDE = deployment_.usde;
        _SUSDE = deployment_.sUsde;

        _BACKING = parameters_.backing;
        _INITIAL_DISCOUNT = parameters_.initialDiscount;
        _MAX_PRICE_PREMIUM = parameters_.maxPricePremium;
        _SUSDS_YIELD_BUYBACK_SHARE = parameters_.sUsds.yieldBuybackShare;
        _SUSDS_SELL_SHARES = parameters_.sUsds.sellShares;
        _SUSDE_YIELD_BUYBACK_SHARE = parameters_.sUsde.yieldBuybackShare;
        _SUSDE_SELL_SHARES = parameters_.sUsde.sellShares;

        uint256 length = parameters_.clearinghouses.length;
        for (uint256 i = 0; i < length; ++i) {
            ClearinghouseParameters memory entry = parameters_.clearinghouses[i];
            _requireNonZero(entry.clearinghouse, "clearinghouse");
            if (_isListed(entry.clearinghouse))
                revert YieldRepurchaseFacilityV2Activator_DuplicateClearinghouse(
                    entry.clearinghouse
                );
            _clearinghouses.push(entry);
        }

        _requireBindings();
    }

    // ============ VIEWS ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    function deployment() external view override returns (Deployment memory deployment_) {
        deployment_.kernel = _KERNEL;
        deployment_.backingOracle = _BACKING_ORACLE;
        deployment_.backingOracleConfigTimelock = _BACKING_ORACLE_CONFIG_TIMELOCK;
        deployment_.config = _CONFIG;
        deployment_.configTimelock = _CONFIG_TIMELOCK;
        deployment_.facility = _FACILITY;
        deployment_.yieldRepoV1 = _YIELD_REPO_V1;
        deployment_.heart = _HEART;
        deployment_.priceConfig = _PRICE_CONFIG;
        deployment_.bondAuctioneer = _BOND_AUCTIONEER;
        deployment_.usdeUsdPriceFeed = _USDE_USD_PRICE_FEED;
        deployment_.ohm = _OHM;
        deployment_.usds = _USDS;
        deployment_.sUsds = _SUSDS;
        deployment_.usde = _USDE;
        deployment_.sUsde = _SUSDE;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    function launchParameters()
        external
        view
        override
        returns (LaunchParameters memory parameters)
    {
        parameters.backing = _BACKING;
        parameters.initialDiscount = _INITIAL_DISCOUNT;
        parameters.maxPricePremium = _MAX_PRICE_PREMIUM;
        parameters.sUsds = AssetParameters({
            yieldBuybackShare: _SUSDS_YIELD_BUYBACK_SHARE,
            sellShares: _SUSDS_SELL_SHARES
        });
        parameters.sUsde = AssetParameters({
            yieldBuybackShare: _SUSDE_YIELD_BUYBACK_SHARE,
            sellShares: _SUSDE_SELL_SHARES
        });
        parameters.clearinghouses = _clearinghouses;
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    /// @dev Reverts if:
    ///      - The launch has completed (`YieldRepurchaseFacilityV2Activator_AlreadyActivated`).
    ///      - A precondition listed at `_checkPreconditions` does not hold.
    function checkPreconditions() external view override {
        if (isActivated) revert YieldRepurchaseFacilityV2Activator_AlreadyActivated();
        _checkPreconditions();
    }

    // ============ ACTIVATION ============ //

    /// @inheritdoc IYieldRepurchaseFacilityV2Activator
    /// @dev The one-use flag is set before the first external call. A revert of any later step
    ///      reverts the flag together with every change of the launch.
    ///
    ///      Steps, in order:
    ///      1. Check the preconditions and the two roles of the launcher.
    ///      2. Register USDe in the PRICE module through the PriceConfig v2 policy, with the
    ///         USDe/USD feed, `USDE_FEED_UPDATE_THRESHOLD`, `USDE_EXPECTED_PRICE` and
    ///         `USDE_PRICE_TOLERANCE_BPS`; skipped when USDe is registered.
    ///      3. Name the BackingOracleConfigTimelock as the config operator of the BackingOracle,
    ///         enable the timelock, and enable the oracle with the backing of the launch.
    ///      4. Bind the configuration policy and the facility to each other, enable the
    ///         configuration policy, name the config timelock as its config operator, and
    ///         enable the timelock.
    ///      5. Enable the facility with the initial discount and the maximum price premium of
    ///         the launch and without next-yield seeds.
    ///      6. Read the epoch counter, the stored next yield, the two yield snapshots and the
    ///         USDS and sUSDS balances of the YieldRepurchaseFacility v1.2, and shut it down,
    ///         which transfers both balances to the treasury.
    ///      7. Register the sUSDS vault as the backing vault with the next yield and the
    ///         snapshots read in step 6, then the sUSDe vault with `sUSDeNextYield_` and with
    ///         snapshots read from the vault: the reserve value of the sUSDe shares the
    ///         treasury holds, and the reserve value of one whole share.
    ///      8. Include each Clearinghouse listed as included, and set each non-zero offset.
    ///      9. Seed the weekly cycle of the facility with the epoch counter read in step 6 and,
    ///         when it is not zero, with the USDS value of the balances read in step 6 as the
    ///         buyback pool of the sUSDS vault.
    ///      10. Replace the YieldRepurchaseFacility v1.2 with the facility at the same index of
    ///          the periodic tasks of the Heart.
    ///
    ///      Reverts if:
    ///      - The caller is not the timelock (`YieldRepurchaseFacilityV2Activator_NotTimelock`).
    ///      - The launch has completed (`YieldRepurchaseFacilityV2Activator_AlreadyActivated`).
    ///      - `sUSDeNextYield_` exceeds `MAX_SUSDE_NEXT_YIELD`
    ///        (`YieldRepurchaseFacilityV2Activator_NextYieldTooHigh`).
    ///      - A precondition listed at `_checkPreconditions` does not hold.
    ///      - The launcher does not hold the `admin` role or the `loop_daddy` role
    ///        (`YieldRepurchaseFacilityV2Activator_MissingRole`).
    ///      - A call of the steps 2 to 10 reverts.
    /// @param sUSDeNextYield_ The next yield the sUSDe vault is registered with, in USDe (18
    ///        decimals).
    function activate(uint256 sUSDeNextYield_) external override {
        if (msg.sender != timelock)
            revert YieldRepurchaseFacilityV2Activator_NotTimelock(msg.sender);
        if (isActivated) revert YieldRepurchaseFacilityV2Activator_AlreadyActivated();
        isActivated = true;

        if (sUSDeNextYield_ > MAX_SUSDE_NEXT_YIELD)
            revert YieldRepurchaseFacilityV2Activator_NextYieldTooHigh(
                sUSDeNextYield_,
                MAX_SUSDE_NEXT_YIELD
            );

        _checkPreconditions();
        Kernel kernel = Kernel(_KERNEL);
        _requireRoles(kernel);

        _registerUsde(kernel);
        _enableOracle();
        _enableFacility();
        (uint48 epoch, uint256 sUsdsNextYield, uint256 sUsdsPoolSeed) = _migrateV1();
        _registerSUsde(kernel, sUSDeNextYield_);
        _configureClearinghouses();
        _seedCycle(epoch, sUsdsPoolSeed);
        _replaceHeartTask();

        emit Activated(epoch, sUsdsNextYield, sUsdsPoolSeed, sUSDeNextYield_);
    }

    /// @notice Registers USDe in the PRICE module with one Chainlink feed, without a price
    ///         strategy and without a moving average. Returns without a call when USDe is
    ///         registered.
    function _registerUsde(Kernel kernel_) private {
        if (_price(kernel_).isAssetApproved(_USDE)) return;

        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode(_CHAINLINK_SUBMODULE),
            selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
            params: _usdeFeedParams()
        });
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: USDE_EXPECTED_PRICE,
            toleranceBps: USDE_PRICE_TOLERANCE_BPS
        });
        // A single feed is used directly: the strategy stays empty
        IPRICEv2.Component memory strategy;

        // The literals are the moving average flags of the registration
        // forge-lint: disable-start(boolean-cst)
        IPriceConfigv2(_PRICE_CONFIG).addAsset(
            _USDE,
            false, // storeMovingAverage
            false, // useMovingAverage
            0, // movingAverageDuration
            0, // lastObservationTime
            new uint256[](0), // observations
            strategy,
            feeds,
            expectations
        );
        // forge-lint: disable-end(boolean-cst)
    }

    /// @notice Names the oracle timelock as the config operator of the oracle, enables the
    ///         timelock, and enables the oracle with the backing of the launch.
    /// @dev The timelock requires being named before it is enabled.
    function _enableOracle() private {
        IConfigOperator(_BACKING_ORACLE).setConfigOperator(_BACKING_ORACLE_CONFIG_TIMELOCK);
        IEnabler(_BACKING_ORACLE_CONFIG_TIMELOCK).enable("");
        IEnabler(_BACKING_ORACLE).enable(abi.encode(_BACKING));
    }

    /// @notice Binds and enables the configuration policy, its config timelock and the
    ///         facility.
    /// @dev The facility accepts a configurator that names the facility, the configuration
    ///      policy is enabled once the facility names it, and its timelock once the policy
    ///      names the timelock. The facility is enabled without next-yield seeds, before any
    ///      vault is registered: its `enable` zeroes the next yield of every registered vault.
    function _enableFacility() private {
        IYieldRepurchaseFacilityV2Config(_CONFIG).setFacility(_FACILITY);
        IYieldRepurchaseFacilityV2Write(_FACILITY).setConfigurator(_CONFIG);
        IEnabler(_CONFIG).enable("");
        IConfigOperator(_CONFIG).setConfigOperator(_CONFIG_TIMELOCK);
        IEnabler(_CONFIG_TIMELOCK).enable("");
        IEnabler(_FACILITY).enable(
            abi.encode(
                _INITIAL_DISCOUNT,
                _MAX_PRICE_PREMIUM,
                new IYieldRepurchaseFacilityV2.NextYieldSeed[](0)
            )
        );
    }

    /// @notice Reads the weekly cycle of the YieldRepurchaseFacility v1.2, shuts it down, and
    ///         registers the sUSDS vault as the backing vault with the values read.
    /// @return epoch The epoch counter of the YieldRepurchaseFacility v1.2.
    /// @return nextYield The stored next yield of the YieldRepurchaseFacility v1.2, in USDS (18
    ///         decimals).
    /// @return poolSeed The USDS value the YieldRepurchaseFacility v1.2 held, in USDS (18
    ///         decimals).
    function _migrateV1() private returns (uint48 epoch, uint256 nextYield, uint256 poolSeed) {
        IYieldRepoV1 yieldRepoV1 = IYieldRepoV1(_YIELD_REPO_V1);
        epoch = yieldRepoV1.epoch();
        nextYield = yieldRepoV1.nextYield();
        uint256 lastReserveBalance = yieldRepoV1.lastReserveBalance();
        uint256 lastConversionRate = yieldRepoV1.lastConversionRate();
        // USDS balance (18 decimals) + USDS value of the sUSDS balance (18 decimals), which the
        // vault rounds down -> USDS (18 decimals)
        poolSeed =
            IERC20(_USDS).balanceOf(_YIELD_REPO_V1) +
            IERC4626(_SUSDS).previewRedeem(IERC20(_SUSDS).balanceOf(_YIELD_REPO_V1));

        address[] memory tokens = new address[](_V1_TOKEN_COUNT);
        tokens[0] = _USDS;
        tokens[1] = _SUSDS;
        yieldRepoV1.shutdown(tokens);

        // The literal designates the vault as the backing vault
        // forge-lint: disable-next-item(boolean-cst)
        IYieldRepurchaseFacilityV2Config(_CONFIG).addAsset(
            IYieldRepurchaseFacilityV2.AddAssetParams({
                vault: _SUSDS,
                yieldBuybackShare: _SUSDS_YIELD_BUYBACK_SHARE,
                initialReserveBalance: lastReserveBalance,
                initialConversionRate: lastConversionRate,
                nextYield: nextYield,
                sellShares: _SUSDS_SELL_SHARES,
                setAsBackingVault: true
            })
        );
    }

    /// @notice Registers the sUSDe vault with snapshots read from the vault.
    /// @param sUSDeNextYield_ The next yield of the registration, in USDe (18 decimals).
    function _registerSUsde(Kernel kernel_, uint256 sUSDeNextYield_) private {
        IERC4626 sUsde = IERC4626(_SUSDE);
        address treasury = address(kernel_.getModuleForKeycode(toKeycode("TRSRY")));
        // One whole share: 10 ** share decimals
        uint256 oneShare = _DECIMAL_BASE ** IERC20(_SUSDE).decimals();

        // The literal leaves the backing vault designation with the sUSDS vault
        // forge-lint: disable-next-item(boolean-cst)
        IYieldRepurchaseFacilityV2Config(_CONFIG).addAsset(
            IYieldRepurchaseFacilityV2.AddAssetParams({
                vault: _SUSDE,
                yieldBuybackShare: _SUSDE_YIELD_BUYBACK_SHARE,
                // Reserve value of the treasury shares, rounded down by the vault
                initialReserveBalance: sUsde.previewRedeem(IERC20(_SUSDE).balanceOf(treasury)),
                // Reserve value of one whole share, rounded down by the vault
                initialConversionRate: sUsde.previewRedeem(oneShare),
                nextYield: sUSDeNextYield_,
                sellShares: _SUSDE_SELL_SHARES,
                setAsBackingVault: false
            })
        );
    }

    /// @notice Includes each Clearinghouse listed as included and sets each non-zero offset.
    // The list is the constructor argument, and each entry needs its own call
    // forge-lint: disable-next-item(calls-loop)
    function _configureClearinghouses() private {
        IYieldRepurchaseFacilityV2Config config = IYieldRepurchaseFacilityV2Config(_CONFIG);
        uint256 length = _clearinghouses.length;
        for (uint256 i = 0; i < length; ++i) {
            ClearinghouseParameters memory entry = _clearinghouses[i];
            if (entry.included) config.includeClearinghouse(entry.clearinghouse);
            if (entry.offset != 0) config.setClearinghouseOffset(entry.clearinghouse, entry.offset);
        }
    }

    /// @notice Seeds the weekly cycle of the facility: the epoch counter, and the buyback pool
    ///         of the sUSDS vault when `poolSeed_` is not zero.
    /// @dev The facility rejects a zero seed, so a zero `poolSeed_` seeds the epoch counter
    ///      alone.
    function _seedCycle(uint48 epoch_, uint256 poolSeed_) private {
        IYieldRepurchaseFacilityV2.BuybackPoolSeed[] memory seeds;
        if (poolSeed_ != 0) {
            seeds = new IYieldRepurchaseFacilityV2.BuybackPoolSeed[](1);
            seeds[0] = IYieldRepurchaseFacilityV2.BuybackPoolSeed({
                vault: _SUSDS,
                amount: poolSeed_
            });
        }
        IYieldRepurchaseFacilityV2Write(_FACILITY).seedCycle(epoch_, seeds);
    }

    /// @notice Replaces the YieldRepurchaseFacility v1.2 with the facility at the same index of
    ///         the periodic tasks of the Heart.
    /// @dev The facility is added without a custom selector: the Heart calls its
    ///      `IPeriodicTask.execute`.
    function _replaceHeartTask() private {
        IPeriodicTaskManager heart = IPeriodicTaskManager(_HEART);
        uint256 index = heart.getPeriodicTaskIndex(_YIELD_REPO_V1);
        heart.removePeriodicTaskAtIndex(index);
        heart.addPeriodicTaskAtIndex(_FACILITY, bytes4(0), index);
    }

    // ============ PRECONDITIONS ============ //

    /// @notice Reverts unless the state of the chain allows the launch.
    /// @dev Reverts if, in this order:
    ///      - A binding listed at `_requireBindings` does not hold
    ///        (`YieldRepurchaseFacilityV2Activator_BindingMismatch`).
    ///      - One of the five policies of the stack is not an active policy of the Kernel
    ///        (`YieldRepurchaseFacilityV2Activator_PolicyNotActive`), or is enabled or has been
    ///        enabled before (`YieldRepurchaseFacilityV2Activator_PolicyAlreadyEnabled`).
    ///      - The configuration policy names a facility, the facility names a configurator, or
    ///        the configuration policy or the oracle names a config operator
    ///        (`YieldRepurchaseFacilityV2Activator_AlreadyBound`).
    ///      - The facility is not authorized as a market callback on the bond auctioneer
    ///        (`YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized`).
    ///      - The Heart is not an active policy of the Kernel
    ///        (`YieldRepurchaseFacilityV2Activator_PolicyNotActive`) or is disabled
    ///        (`YieldRepurchaseFacilityV2Activator_PolicyNotEnabled`).
    ///      - The YieldRepurchaseFacility v1.2 is not a periodic task of the Heart
    ///        (`YieldRepurchaseFacilityV2Activator_V1NotHeartTask`), or the facility is one
    ///        (`YieldRepurchaseFacilityV2Activator_FacilityAlreadyHeartTask`).
    ///      - The YieldRepurchaseFacility v1.2 is shut down
    ///        (`YieldRepurchaseFacilityV2Activator_V1ShutDown`) or reports a zero conversion
    ///        rate snapshot (`YieldRepurchaseFacilityV2Activator_V1ConversionRateUnset`). A
    ///        zero reserve balance snapshot is accepted.
    ///      - A condition listed at `_checkClearinghouses` or `_checkPrices` does not hold.
    function _checkPreconditions() private view {
        _requireBindings();
        Kernel kernel = Kernel(_KERNEL);

        _requireNeverEnabled(kernel, _BACKING_ORACLE);
        _requireNeverEnabled(kernel, _BACKING_ORACLE_CONFIG_TIMELOCK);
        _requireNeverEnabled(kernel, _CONFIG);
        _requireNeverEnabled(kernel, _CONFIG_TIMELOCK);
        _requireNeverEnabled(kernel, _FACILITY);

        _requireUnbound(
            "YieldRepurchaseFacilityV2Config facility",
            IYieldRepurchaseFacilityV2Config(_CONFIG).facility()
        );
        _requireUnbound(
            "YieldRepurchaseFacilityV2 configurator",
            IYieldRepurchaseFacilityV2View(_FACILITY).configurator()
        );
        _requireUnbound(
            "YieldRepurchaseFacilityV2Config configOperator",
            IConfigOperator(_CONFIG).configOperator()
        );
        _requireUnbound(
            "BackingOracle configOperator",
            IConfigOperator(_BACKING_ORACLE).configOperator()
        );

        if (!IBondAuctioneer(_BOND_AUCTIONEER).callbackAuthorized(_FACILITY))
            revert YieldRepurchaseFacilityV2Activator_CallbackNotAuthorized(_BOND_AUCTIONEER);

        _requireActiveAndEnabled(kernel, _HEART);
        if (IPeriodicTaskManager(_HEART).getPeriodicTaskIndex(_YIELD_REPO_V1) == type(uint256).max)
            revert YieldRepurchaseFacilityV2Activator_V1NotHeartTask();
        if (IPeriodicTaskManager(_HEART).hasPeriodicTask(_FACILITY))
            revert YieldRepurchaseFacilityV2Activator_FacilityAlreadyHeartTask();

        IYieldRepoV1 yieldRepoV1 = IYieldRepoV1(_YIELD_REPO_V1);
        if (yieldRepoV1.isShutdown()) revert YieldRepurchaseFacilityV2Activator_V1ShutDown();
        // The registration of a vault stores the conversion rate snapshot unchecked, and the
        // facility projects no vault yield from a zero one. A zero reserve balance snapshot
        // is accepted: the yield projected from it is zero.
        if (yieldRepoV1.lastConversionRate() == 0)
            revert YieldRepurchaseFacilityV2Activator_V1ConversionRateUnset();

        _checkClearinghouses(kernel);
        _checkPrices(kernel);
    }

    /// @notice Reverts unless the Clearinghouse list is the registry of the CHREG module and
    ///         the facility accepts each inclusion and each offset of the list.
    /// @dev The list holds no duplicate, which the constructor rejects, so equal counts and
    ///      every registry entry being listed mean that the two sets are equal.
    ///
    ///      Reverts if:
    ///      - The list and the registry differ in length, or a registry entry is not listed
    ///        (`YieldRepurchaseFacilityV2Activator_ClearinghouseRegistryMismatch`).
    ///      - The `principalReceivables` read of an included or offset Clearinghouse reverts
    ///        (`YieldRepurchaseFacilityV2Activator_ClearinghouseReceivablesNotReadable`).
    ///      - An offset exceeds the `principalReceivables` of its Clearinghouse
    ///        (`YieldRepurchaseFacilityV2Activator_ClearinghouseOffsetTooHigh`).
    // The registry and the list are walked entry by entry, and the first entry that fails a
    // condition rejects the launch
    // forge-lint: disable-next-item(calls-loop,require-revert-in-loop)
    function _checkClearinghouses(Kernel kernel_) private view {
        CHREGv1 chreg = CHREGv1(address(kernel_.getModuleForKeycode(toKeycode("CHREG"))));
        uint256 registryCount = chreg.registryCount();
        uint256 listedCount = _clearinghouses.length;
        if (registryCount != listedCount)
            revert YieldRepurchaseFacilityV2Activator_ClearinghouseRegistryMismatch(
                address(0),
                listedCount,
                registryCount
            );
        for (uint256 i = 0; i < registryCount; ++i) {
            address registered = chreg.registry(i);
            if (!_isListed(registered))
                revert YieldRepurchaseFacilityV2Activator_ClearinghouseRegistryMismatch(
                    registered,
                    listedCount,
                    registryCount
                );
        }

        for (uint256 i = 0; i < listedCount; ++i) {
            ClearinghouseParameters memory entry = _clearinghouses[i];
            if (!entry.included && entry.offset == 0) continue;

            // Every listed Clearinghouse is a registry entry at this point. A revert of the
            // read is reported with the error below; its revert data is not used.
            try IGenericClearinghouse(entry.clearinghouse).principalReceivables() returns (
                uint256 principalReceivables
            ) {
                if (entry.offset > principalReceivables)
                    revert YieldRepurchaseFacilityV2Activator_ClearinghouseOffsetTooHigh(
                        entry.clearinghouse,
                        entry.offset,
                        principalReceivables
                    );
            } catch {
                revert YieldRepurchaseFacilityV2Activator_ClearinghouseReceivablesNotReadable(
                    entry.clearinghouse
                );
            }
        }
    }

    /// @notice Reverts unless the PRICE module prices OHM in USDS and in USDe, where USDe
    ///         counts as priced when it is not registered and its feed passes the checks of
    ///         the registration.
    /// @dev The registration of a vault in the facility reads `getPriceIn(OHM, reserve)`. For
    ///      an unregistered USDe the feed is read through the Chainlink submodule of the PRICE
    ///      module with the parameters of the registration, and the price is compared the way
    ///      the PriceConfig v2 policy compares it.
    ///
    ///      Reverts if:
    ///      - `getPriceIn(OHM, USDS)` reverts or returns zero, or USDe is registered and
    ///        `getPriceIn(OHM, USDe)` does
    ///        (`YieldRepurchaseFacilityV2Activator_ReserveNotPriceable`).
    ///      - USDe is not registered and the PriceConfig v2 policy is not an active policy of
    ///        the Kernel (`YieldRepurchaseFacilityV2Activator_PolicyNotActive`) or is disabled
    ///        (`YieldRepurchaseFacilityV2Activator_PolicyNotEnabled`).
    ///      - USDe is not registered and the Chainlink submodule is not installed or reverts
    ///        on the feed, which includes an answer older than `USDE_FEED_UPDATE_THRESHOLD`
    ///        (`YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable`).
    ///      - USDe is not registered and the feed price is zero or deviates from
    ///        `USDE_EXPECTED_PRICE` by more than `USDE_PRICE_TOLERANCE_BPS`
    ///        (`YieldRepurchaseFacilityV2Activator_UsdePriceOutOfBounds`).
    function _checkPrices(Kernel kernel_) private view {
        IPRICEv2 price = _price(kernel_);
        _requirePriceable(price, _USDS);
        if (price.isAssetApproved(_USDE)) {
            _requirePriceable(price, _USDE);
            return;
        }

        _requireActiveAndEnabled(kernel_, _PRICE_CONFIG);

        address submodule = address(
            ModuleWithSubmodules(address(price)).getSubmoduleForKeycode(
                toSubKeycode(_CHAINLINK_SUBMODULE)
            )
        );
        // A call to an address without code reverts outside the try statement below
        if (submodule.code.length == 0)
            revert YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable(_USDE_USD_PRICE_FEED, "");

        try
            ChainlinkPriceFeeds(submodule).getOneFeedPrice(
                _USDE,
                price.decimals(),
                _usdeFeedParams()
            )
        returns (uint256 usdePrice) {
            // price (18 decimals) against the expected price (18 decimals), in basis points
            if (
                usdePrice == 0 ||
                Deviation.isDeviating(
                    usdePrice,
                    USDE_EXPECTED_PRICE,
                    USDE_PRICE_TOLERANCE_BPS,
                    _ONE_HUNDRED_PERCENT_BPS
                )
            )
                revert YieldRepurchaseFacilityV2Activator_UsdePriceOutOfBounds(
                    usdePrice,
                    USDE_EXPECTED_PRICE,
                    USDE_PRICE_TOLERANCE_BPS
                );
        } catch (bytes memory reason) {
            revert YieldRepurchaseFacilityV2Activator_UsdeFeedNotReadable(
                _USDE_USD_PRICE_FEED,
                reason
            );
        }
    }

    /// @notice Reverts unless each bound contract reports the binding the launch relies on.
    /// @dev Reverts with `YieldRepurchaseFacilityV2Activator_BindingMismatch` if:
    ///      - One of the five policies of the stack, the YieldRepurchaseFacility v1.2, the Heart
    ///        or the PriceConfig v2 policy does not report the bound Kernel.
    ///      - The BackingOracleConfigTimelock does not report the bound BackingOracle, or the
    ///        config timelock the bound configuration policy.
    ///      - The facility does not report the bound BackingOracle, bond auctioneer or OHM.
    ///      - The YieldRepurchaseFacility v1.2 does not report the bound sUSDS vault.
    ///      - The sUSDS vault does not report USDS as its asset, or the sUSDe vault USDe.
    function _requireBindings() private view {
        _requireKernel("BackingOracle kernel", _BACKING_ORACLE);
        _requireKernel("BackingOracleConfigTimelock kernel", _BACKING_ORACLE_CONFIG_TIMELOCK);
        _requireKernel("YieldRepurchaseFacilityV2Config kernel", _CONFIG);
        _requireKernel("YieldRepurchaseFacilityV2ConfigTimelock kernel", _CONFIG_TIMELOCK);
        _requireKernel("YieldRepurchaseFacilityV2 kernel", _FACILITY);
        _requireKernel("YieldRepurchaseFacility v1.2 kernel", _YIELD_REPO_V1);
        _requireKernel("Heart kernel", _HEART);
        _requireKernel("PriceConfig kernel", _PRICE_CONFIG);

        _requireBinding(
            "BackingOracleConfigTimelock backingOracle",
            address(IBackingOracleConfigTimelock(_BACKING_ORACLE_CONFIG_TIMELOCK).backingOracle()),
            _BACKING_ORACLE
        );
        _requireBinding(
            "YieldRepurchaseFacilityV2ConfigTimelock config",
            IYieldRepurchaseFacilityV2ConfigTimelock(_CONFIG_TIMELOCK).config(),
            _CONFIG
        );

        IYieldRepurchaseFacilityV2View facility = IYieldRepurchaseFacilityV2View(_FACILITY);
        _requireBinding(
            "YieldRepurchaseFacilityV2 backingOracle",
            facility.backingOracle(),
            _BACKING_ORACLE
        );
        _requireBinding(
            "YieldRepurchaseFacilityV2 bondAuctioneer",
            facility.bondAuctioneer(),
            _BOND_AUCTIONEER
        );
        _requireBinding("YieldRepurchaseFacilityV2 OHM", facility.context().ohm, _OHM);

        _requireBinding(
            "YieldRepurchaseFacility v1.2 sReserve",
            IYieldRepoV1(_YIELD_REPO_V1).sReserve(),
            _SUSDS
        );
        _requireBinding("sUSDS asset", IERC4626(_SUSDS).asset(), _USDS);
        _requireBinding("sUSDe asset", IERC4626(_SUSDE).asset(), _USDE);
    }

    /// @notice Reverts unless the launcher holds the `admin` and `loop_daddy` roles.
    function _requireRoles(Kernel kernel_) private view {
        ROLESv1 roles = ROLESv1(address(kernel_.getModuleForKeycode(toKeycode("ROLES"))));
        if (!roles.hasRole(address(this), ADMIN_ROLE))
            revert YieldRepurchaseFacilityV2Activator_MissingRole(ADMIN_ROLE);
        if (!roles.hasRole(address(this), _LOOP_DADDY_ROLE))
            revert YieldRepurchaseFacilityV2Activator_MissingRole(_LOOP_DADDY_ROLE);
    }

    // ============ HELPERS ============ //

    /// @notice Returns the PRICE module the Kernel reports.
    function _price(Kernel kernel_) private view returns (IPRICEv2) {
        return IPRICEv2(address(kernel_.getModuleForKeycode(toKeycode("PRICE"))));
    }

    /// @notice Returns the parameters of the USDe/USD feed for the Chainlink submodule.
    function _usdeFeedParams() private view returns (bytes memory) {
        return
            abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(_USDE_USD_PRICE_FEED),
                    updateThreshold: USDE_FEED_UPDATE_THRESHOLD
                })
            );
    }

    /// @notice Returns whether the Clearinghouse list holds the address.
    function _isListed(address clearinghouse_) private view returns (bool) {
        uint256 length = _clearinghouses.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_clearinghouses[i].clearinghouse == clearinghouse_) return true;
        }
        return false;
    }

    /// @notice Reverts unless the PRICE module returns a non-zero OHM price in the reserve.
    function _requirePriceable(IPRICEv2 price_, address reserve_) private view {
        // A revert of the read is reported with the error below; its revert data is not used
        try price_.getPriceIn(_OHM, reserve_) returns (uint256 ohmPrice) {
            if (ohmPrice != 0) return;
        } catch {}
        revert YieldRepurchaseFacilityV2Activator_ReserveNotPriceable(reserve_);
    }

    /// @notice Reverts unless the policy is an active policy of the Kernel, is disabled and
    ///         has never changed its enabled state.
    function _requireNeverEnabled(Kernel kernel_, address policy_) private view {
        _requireActive(kernel_, policy_);
        if (IEnabler(policy_).isEnabled() || IEnablerV2(policy_).lastTransitionAt() != 0)
            revert YieldRepurchaseFacilityV2Activator_PolicyAlreadyEnabled(policy_);
    }

    /// @notice Reverts unless the policy is an active policy of the Kernel and is enabled.
    function _requireActiveAndEnabled(Kernel kernel_, address policy_) private view {
        _requireActive(kernel_, policy_);
        if (!IEnabler(policy_).isEnabled())
            revert YieldRepurchaseFacilityV2Activator_PolicyNotEnabled(policy_);
    }

    function _requireActive(Kernel kernel_, address policy_) private view {
        if (!kernel_.isPolicyActive(Policy(policy_)))
            revert YieldRepurchaseFacilityV2Activator_PolicyNotActive(policy_);
    }

    function _requireUnbound(string memory binding_, address value_) private pure {
        if (value_ != address(0))
            revert YieldRepurchaseFacilityV2Activator_AlreadyBound(binding_, value_);
    }

    function _requireKernel(string memory binding_, address policy_) private view {
        _requireBinding(binding_, address(Policy(policy_).kernel()), _KERNEL);
    }

    function _requireBinding(
        string memory binding_,
        address actual_,
        address expected_
    ) private pure {
        if (actual_ != expected_)
            revert YieldRepurchaseFacilityV2Activator_BindingMismatch(binding_, actual_, expected_);
    }

    // The constructor rejects the first zero address of the Clearinghouse list from its loop
    // forge-lint: disable-next-item(require-revert-in-loop)
    function _requireNonZero(address value_, string memory parameter_) private pure {
        if (value_ == address(0)) revert YieldRepurchaseFacilityV2Activator_ZeroAddress(parameter_);
    }

    function _requireContract(address value_, string memory parameter_) private view {
        _requireNonZero(value_, parameter_);
        if (value_.code.length == 0)
            revert YieldRepurchaseFacilityV2Activator_NotAContract(parameter_, value_);
    }

    // ============ ERC165 ============ //

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IYieldRepurchaseFacilityV2Activator).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
