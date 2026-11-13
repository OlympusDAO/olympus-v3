// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Test
import {Test} from "@forge-std-1.16.2/Test.sol";

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {AggregatorV2V3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IPriceConfigv2} from "src/policies/interfaces/IPriceConfigv2.sol";
import {IYieldRepurchaseFacilityV2Activator} from "src/proposals/interfaces/IYieldRepurchaseFacilityV2Activator.sol";

// Libraries
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {toSubKeycode} from "src/Submodules.sol";

// Bond Protocol
import {RolesAuthority, Authority as SolmateAuthority} from "@solmate-6.2.0/auth/authorities/RolesAuthority.sol";
import {BondAggregator} from "src/test/lib/bonds/BondAggregator.sol";
import {BondFixedTermSDA} from "src/test/lib/bonds/BondFixedTermSDA.sol";
import {BondFixedTermTeller} from "src/test/lib/bonds/BondFixedTermTeller.sol";

// Mocks
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";
import {MockClearinghouse} from "src/test/mocks/MockClearinghouse.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockPriceFeed} from "src/test/mocks/MockPriceFeed.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {OlympusClearinghouseRegistry} from "src/modules/CHREG/OlympusClearinghouseRegistry.sol";
import {OlympusPricev1_2} from "src/modules/PRICE/OlympusPrice.v1_2.sol";
import {ChainlinkPriceFeeds} from "src/modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {BackingOracleConfigTimelock} from "src/policies/BackingOracleConfigTimelock.sol";
import {PriceConfigv2} from "src/policies/price/PriceConfig.v2.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {YieldRepurchaseFacility} from "src/policies/YieldRepurchaseFacility.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {YieldRepurchaseFacilityV2Config} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Config.sol";
import {YieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2ConfigTimelock.sol";
import {YieldRepurchaseFacilityV2Activator} from "src/proposals/YieldRepurchaseFacilityV2Activator.sol";

/// @notice Shared rig of the `YieldRepurchaseFacilityV2Activator` suites: a local Kernel with the
///         deployed contracts of the launch, that is the five policies of the stack and the
///         YieldRepurchaseFacility v1.2, in the state the launch proposal finds them in.
/// @dev    Real: the ROLES, TRSRY, CHREG and PRICE 1.2 modules with the Chainlink feed
///         submodule, RolesAdmin, PriceConfig v2, the Bond Protocol auctioneer, teller and
///         aggregator of the test library, the YieldRepurchaseFacility v1.2 and the five
///         policies of the stack. Mocked: the tokens and the two ERC4626 vaults, the three
///         price feeds, the three Clearinghouses, and the Heart, which is the periodic task
///         manager without the beat reward.
///
///         `setUp` leaves the YieldRepurchaseFacility v1.2 in the middle of a week: it has
///         run its weekly reset and two daily cycles, so it holds USDS and sUSDS, and its
///         epoch counter is `V1_EPOCH`. The five policies are active in the Kernel and have
///         never been enabled, the facility is authorized as a market callback, and the
///         activator holds the `admin` and `loop_daddy` roles, the state the proposal
///         establishes before it calls `activate`.
// solhint-disable-next-line max-states-count
abstract contract YieldRepurchaseFacilityV2ActivatorTest is Test {
    using ModuleTestFixtureGenerator for OlympusClearinghouseRegistry;

    // ========== CONSTANTS ========== //

    bytes32 internal constant ADMIN_ROLE = "admin";
    bytes32 internal constant LOOP_DADDY_ROLE = "loop_daddy";
    bytes32 internal constant HEART_ROLE = "heart";
    bytes32 internal constant EMERGENCY_ROLE = "emergency";

    /// @notice The launch values the activator is constructed with.
    uint256 internal constant BACKING = 12.04e18;
    uint256 internal constant INITIAL_DISCOUNT = 3e16;
    uint256 internal constant MAX_PRICE_PREMIUM = 10e16;
    uint256 internal constant SUSDS_YIELD_BUYBACK_SHARE = 1e18;
    uint256 internal constant SUSDE_YIELD_BUYBACK_SHARE = 5e17;

    /// @notice The receivables of the three Clearinghouses and the offset of the second one,
    ///         in the units of the receivables (18 decimals).
    uint256 internal constant CLEARINGHOUSE_ONE_RECEIVABLES = 35_930e18;
    uint256 internal constant CLEARINGHOUSE_TWO_RECEIVABLES = 4_514_144e18;
    uint256 internal constant CLEARINGHOUSE_THREE_RECEIVABLES = 177_173e18;
    uint256 internal constant CLEARINGHOUSE_TWO_OFFSET = 2_000_000e18;

    /// @notice The next yield the tests register the sUSDe vault with, in USDe (18 decimals).
    uint256 internal constant SUSDE_NEXT_YIELD = 20_000e18;

    /// @notice The deployment parameters of the stack.
    uint32 internal constant GRACE_PERIOD = 5 days;
    uint32 internal constant STEP_GAS_LIMIT = 2_000_000;
    uint48 internal constant TIMELOCK_DELAY = 1 days;

    /// @notice The feed answers, in the 8 decimals of the feeds: OHM at 20 USD, USDS at 1 USD,
    ///         USDe at 0.9995 USD.
    uint8 internal constant FEED_DECIMALS = 8;
    int256 internal constant OHM_FEED_ANSWER = 20e8;
    int256 internal constant USDS_FEED_ANSWER = 1e8;
    int256 internal constant USDE_FEED_ANSWER = 99_950_000;
    uint48 internal constant FEED_UPDATE_THRESHOLD = 1 days;

    /// @notice The observation frequency of the PRICE module, in seconds.
    uint32 internal constant OBSERVATION_FREQUENCY = 8 hours;
    uint16 internal constant FEED_TOLERANCE_BPS = 100;

    /// @notice The treasury holdings: USDS deposited into sUSDS and USDe deposited into sUSDe.
    uint256 internal constant TREASURY_USDS = 10_000_000e18;
    uint256 internal constant TREASURY_USDE = 5_000_000e18;

    /// @notice The yield the YieldRepurchaseFacility v1.2 is initialized with, in USDS (18
    ///         decimals), withdrawn by its first weekly reset.
    uint256 internal constant V1_INITIAL_YIELD = 70_000e18;

    /// @notice The epoch counter of the YieldRepurchaseFacility v1.2 after `setUp`: the weekly
    ///         reset wrapped it to zero, and eight further beats followed.
    uint48 internal constant V1_EPOCH = 8;

    /// @notice The index of the YieldRepurchaseFacility v1.2 among the periodic tasks.
    uint256 internal constant V1_TASK_INDEX = 1;
    uint256 internal constant TASK_COUNT = 3;

    uint256 internal constant ONE_SHARE = 1e18;

    /// @notice The number of bound policies whose Kernel the activator compares.
    uint256 internal constant KERNEL_BOUND_COUNT = 8;

    // ========== CONTRACTS ========== //

    Kernel internal kernel;
    OlympusRoles internal roles;
    OlympusTreasury internal treasury;
    OlympusClearinghouseRegistry internal chreg;
    OlympusPricev1_2 internal price;
    ChainlinkPriceFeeds internal chainlinkFeeds;
    RolesAdmin internal rolesAdmin;
    PriceConfigv2 internal priceConfig;
    MockPeriodicTaskManager internal heart;
    MockPeriodicTask internal taskBefore;
    MockPeriodicTask internal taskAfter;

    MockOhm internal ohm;
    MockERC20 internal usds;
    MockERC20 internal usde;
    MockERC4626 internal sUsds;
    MockERC4626 internal sUsde;

    MockPriceFeed internal ohmUsdFeed;
    MockPriceFeed internal usdsUsdFeed;
    MockPriceFeed internal usdeUsdFeed;

    BondAggregator internal bondAggregator;
    BondFixedTermTeller internal bondTeller;
    BondFixedTermSDA internal bondAuctioneer;

    MockClearinghouse internal clearinghouseOne;
    MockClearinghouse internal clearinghouseTwo;
    MockClearinghouse internal clearinghouseThree;

    YieldRepurchaseFacility internal yieldRepoV1;
    BackingOracle internal backingOracle;
    BackingOracleConfigTimelock internal backingOracleConfigTimelock;
    YieldRepurchaseFacilityV2Config internal config;
    YieldRepurchaseFacilityV2ConfigTimelock internal configTimelock;
    YieldRepurchaseFacilityV2 internal facility;

    YieldRepurchaseFacilityV2Activator internal activator;

    // ========== ACCOUNTS ========== //

    /// @notice The governance timelock: the caller of `activate` and a holder of `admin`.
    address internal ocgTimelock;
    address internal daoMS;
    address internal emergencyMS;
    address internal bondGuardian;
    /// @notice A policy with the permission to activate a Clearinghouse in the CHREG module.
    address internal chregWriter;

    // ========== SETUP ========== //

    function setUp() public virtual {
        // A timestamp well above the update thresholds of the feeds
        vm.warp(1_800_000_000);

        ocgTimelock = makeAddr("ocgTimelock");
        daoMS = makeAddr("daoMS");
        emergencyMS = makeAddr("emergencyMS");
        bondGuardian = makeAddr("bondGuardian");

        _deployTokens();
        _deployBondSystem();
        _deployKernel();
        _deployStack();
        _configureRoles();
        _configurePrice();
        _configureHeart();
        _fundTreasury();
        _runV1();

        activator = _deployActivator(_deployment(), _launchParameters());

        vm.prank(bondGuardian);
        bondAuctioneer.setCallbackAuthStatus(address(facility), true);

        rolesAdmin.grantRole(ADMIN_ROLE, address(activator));
        rolesAdmin.grantRole(LOOP_DADDY_ROLE, address(activator));
    }

    function _deployTokens() internal {
        ohm = new MockOhm("Olympus", "OHM", 9);
        vm.label(address(ohm), "OHM");
        usds = new MockERC20("USDS", "USDS", 18);
        vm.label(address(usds), "USDS");
        usde = new MockERC20("USDe", "USDe", 18);
        vm.label(address(usde), "USDe");
        sUsds = new MockERC4626(usds, "Savings USDS", "sUSDS");
        vm.label(address(sUsds), "sUSDS");
        sUsde = new MockERC4626(usde, "Staked USDe", "sUSDe");
        vm.label(address(sUsde), "sUSDe");

        ohmUsdFeed = _deployFeed(OHM_FEED_ANSWER, "ohmUsdFeed");
        usdsUsdFeed = _deployFeed(USDS_FEED_ANSWER, "usdsUsdFeed");
        usdeUsdFeed = _deployFeed(USDE_FEED_ANSWER, "usdeUsdFeed");
    }

    function _deployFeed(int256 answer_, string memory label_) internal returns (MockPriceFeed) {
        MockPriceFeed feed = new MockPriceFeed();
        vm.label(address(feed), label_);
        feed.setDecimals(FEED_DECIMALS);
        feed.setLatestAnswer(answer_);
        feed.setTimestamp(vm.getBlockTimestamp());
        feed.setRoundId(1);
        feed.setAnsweredInRound(1);
        return feed;
    }

    function _deployBondSystem() internal {
        RolesAuthority authority = new RolesAuthority(bondGuardian, SolmateAuthority(address(0)));
        vm.label(address(authority), "bondAuthority");
        bondAggregator = new BondAggregator(bondGuardian, authority);
        vm.label(address(bondAggregator), "bondAggregator");
        bondTeller = new BondFixedTermTeller(bondGuardian, bondAggregator, bondGuardian, authority);
        vm.label(address(bondTeller), "bondTeller");
        bondAuctioneer = _deployAuctioneer("bondAuctioneer");
    }

    function _deployAuctioneer(string memory label_) internal returns (BondFixedTermSDA) {
        BondFixedTermSDA auctioneer = new BondFixedTermSDA(
            bondTeller,
            bondAggregator,
            bondGuardian,
            bondAggregator.authority()
        );
        vm.label(address(auctioneer), label_);
        vm.prank(bondGuardian);
        bondAggregator.registerAuctioneer(auctioneer);
        return auctioneer;
    }

    /// @notice Deploys the Kernel with its modules, RolesAdmin, PriceConfig v2 and the Heart.
    ///         The test contract is the Kernel executor.
    function _deployKernel() internal {
        kernel = new Kernel();
        vm.label(address(kernel), "Kernel");

        roles = new OlympusRoles(kernel);
        vm.label(address(roles), "ROLES");
        treasury = new OlympusTreasury(kernel);
        vm.label(address(treasury), "TRSRY");
        price = new OlympusPricev1_2(kernel, address(ohm), OBSERVATION_FREQUENCY, 10e18);
        vm.label(address(price), "PRICE");
        chainlinkFeeds = new ChainlinkPriceFeeds(price);
        vm.label(address(chainlinkFeeds), "ChainlinkPriceFeeds");

        clearinghouseOne = _deployClearinghouse(CLEARINGHOUSE_ONE_RECEIVABLES, "clearinghouseOne");
        clearinghouseTwo = _deployClearinghouse(CLEARINGHOUSE_TWO_RECEIVABLES, "clearinghouseTwo");
        clearinghouseThree = _deployClearinghouse(
            CLEARINGHOUSE_THREE_RECEIVABLES,
            "clearinghouseThree"
        );
        // No active Clearinghouse: the three are registry entries only
        address[] memory inactive = new address[](3);
        inactive[0] = address(clearinghouseOne);
        inactive[1] = address(clearinghouseTwo);
        inactive[2] = address(clearinghouseThree);
        chreg = new OlympusClearinghouseRegistry(kernel, address(0), inactive);
        vm.label(address(chreg), "CHREG");
        chregWriter = chreg.generateFunctionFixture(CHREGv1.activateClearinghouse.selector);
        vm.label(chregWriter, "chregWriter");

        rolesAdmin = new RolesAdmin(kernel);
        vm.label(address(rolesAdmin), "RolesAdmin");
        priceConfig = new PriceConfigv2(kernel);
        vm.label(address(priceConfig), "PriceConfigv2");
        heart = new MockPeriodicTaskManager(kernel);
        vm.label(address(heart), "Heart");

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(price));
        kernel.executeAction(Actions.InstallModule, address(chreg));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(heart));
        kernel.executeAction(Actions.ActivatePolicy, chregWriter);
    }

    function _deployClearinghouse(
        uint256 receivables_,
        string memory label_
    ) internal returns (MockClearinghouse) {
        MockClearinghouse clearinghouse = new MockClearinghouse(address(usds), address(sUsds));
        vm.label(address(clearinghouse), label_);
        clearinghouse.setPrincipalReceivables(receivables_);
        return clearinghouse;
    }

    /// @notice Deploys the YieldRepurchaseFacility v1.2 and the five policies of the stack and
    ///         activates them in the Kernel, the state the DAO MS leaves before the proposal.
    function _deployStack() internal {
        yieldRepoV1 = new YieldRepurchaseFacility(
            kernel,
            address(ohm),
            address(sUsds),
            address(bondTeller),
            address(bondAuctioneer)
        );
        vm.label(address(yieldRepoV1), "YieldRepurchaseFacility v1.2");

        backingOracle = new BackingOracle(kernel);
        vm.label(address(backingOracle), "BackingOracle");
        backingOracleConfigTimelock = new BackingOracleConfigTimelock(kernel, backingOracle);
        vm.label(address(backingOracleConfigTimelock), "BackingOracleConfigTimelock");
        config = new YieldRepurchaseFacilityV2Config(kernel, GRACE_PERIOD);
        vm.label(address(config), "YieldRepurchaseFacilityV2Config");
        configTimelock = new YieldRepurchaseFacilityV2ConfigTimelock(
            kernel,
            address(config),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );
        vm.label(address(configTimelock), "YieldRepurchaseFacilityV2ConfigTimelock");
        facility = new YieldRepurchaseFacilityV2(
            kernel,
            address(ohm),
            address(backingOracle),
            address(bondAuctioneer),
            GRACE_PERIOD,
            STEP_GAS_LIMIT
        );
        vm.label(address(facility), "YieldRepurchaseFacilityV2");

        kernel.executeAction(Actions.ActivatePolicy, address(yieldRepoV1));
        kernel.executeAction(Actions.ActivatePolicy, address(backingOracle));
        kernel.executeAction(Actions.ActivatePolicy, address(backingOracleConfigTimelock));
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(configTimelock));
        kernel.executeAction(Actions.ActivatePolicy, address(facility));
    }

    /// @notice Grants the roles of the live system: `admin` to the governance timelock,
    ///         `emergency` to the Emergency MS, `heart` to the Heart, and `loop_daddy` to the
    ///         DAO MS and the governance timelock. The test contract administers RolesAdmin
    ///         and holds `admin` for the setup calls.
    function _configureRoles() internal {
        rolesAdmin.grantRole(ADMIN_ROLE, address(this));
        rolesAdmin.grantRole(ADMIN_ROLE, ocgTimelock);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergencyMS);
        rolesAdmin.grantRole(HEART_ROLE, address(heart));
        rolesAdmin.grantRole(LOOP_DADDY_ROLE, daoMS);
        rolesAdmin.grantRole(LOOP_DADDY_ROLE, ocgTimelock);
    }

    /// @notice Installs the Chainlink submodule and registers OHM and USDS in the PRICE module,
    ///         each with one feed. USDe is left unregistered. PriceConfig v2 is enabled from
    ///         its construction.
    function _configurePrice() internal {
        priceConfig.installSubmodule(address(chainlinkFeeds));
        // OHM at 20 USD and USDS at 1 USD, in the 18 decimals of the PRICE module. OHM stores
        // observations, which the last price read by v1.2 requires.
        _registerAsset(address(ohm), ohmUsdFeed, 20e18, true);
        _registerAsset(address(usds), usdsUsdFeed, 1e18, false);
    }

    function _registerAsset(
        address asset_,
        MockPriceFeed feed_,
        uint256 expectedPrice_,
        bool storeObservations_
    ) internal {
        IPRICEv2.Component[] memory feeds = new IPRICEv2.Component[](1);
        feeds[0] = IPRICEv2.Component({
            target: toSubKeycode("PRICE.CHAINLINK"),
            selector: ChainlinkPriceFeeds.getOneFeedPrice.selector,
            params: abi.encode(
                ChainlinkPriceFeeds.OneFeedParams({
                    feed: AggregatorV2V3Interface(address(feed_)),
                    updateThreshold: FEED_UPDATE_THRESHOLD
                })
            )
        });
        IPriceConfigv2.PriceFeedExpectation[]
            memory expectations = new IPriceConfigv2.PriceFeedExpectation[](1);
        expectations[0] = IPriceConfigv2.PriceFeedExpectation({
            expectedPrice: expectedPrice_,
            toleranceBps: FEED_TOLERANCE_BPS
        });
        IPRICEv2.Component memory strategy;

        // Two observations at the expected price cover a moving average of two observation
        // periods; an asset that stores none takes neither
        uint256[] memory observations = new uint256[](storeObservations_ ? 2 : 0);
        for (uint256 i = 0; i < observations.length; ++i) observations[i] = expectedPrice_;

        priceConfig.addAsset(
            asset_,
            storeObservations_,
            false,
            storeObservations_ ? uint32(2 * OBSERVATION_FREQUENCY) : 0,
            storeObservations_ ? uint48(vm.getBlockTimestamp()) : 0,
            observations,
            strategy,
            feeds,
            expectations
        );
    }

    /// @notice Enables the Heart and gives it three periodic tasks, with the
    ///         YieldRepurchaseFacility v1.2 between two others at `V1_TASK_INDEX`.
    function _configureHeart() internal {
        taskBefore = new MockPeriodicTask();
        vm.label(address(taskBefore), "taskBefore");
        taskAfter = new MockPeriodicTask();
        vm.label(address(taskAfter), "taskAfter");

        heart.enable("");
        heart.addPeriodicTask(address(taskBefore));
        heart.addPeriodicTaskAtIndex(
            address(yieldRepoV1),
            YieldRepurchaseFacility.endEpoch.selector,
            V1_TASK_INDEX
        );
        heart.addPeriodicTask(address(taskAfter));
    }

    /// @notice Gives the treasury sUSDS and sUSDe, and raises the rate of both vaults above
    ///         one by a transfer of the reserve into the vault.
    function _fundTreasury() internal {
        _depositFor(usds, sUsds, address(treasury), TREASURY_USDS);
        _depositFor(usde, sUsde, address(treasury), TREASURY_USDE);
        // 10,000,000 USDS of deposits + 500,000 USDS -> 1.05 USDS per sUSDS
        usds.mint(address(sUsds), 500_000e18);
        // 5,000,000 USDe of deposits + 1,000,000 USDe -> 1.2 USDe per sUSDe
        usde.mint(address(sUsde), 1_000_000e18);
    }

    function _depositFor(
        MockERC20 token_,
        MockERC4626 vault_,
        address receiver_,
        uint256 amount_
    ) internal {
        token_.mint(address(this), amount_);
        token_.approve(address(vault_), amount_);
        vault_.deposit(amount_, receiver_);
    }

    /// @notice Initializes the YieldRepurchaseFacility v1.2 and beats it through its weekly
    ///         reset and to the epoch counter `V1_EPOCH`.
    /// @dev The first beat wraps the epoch counter from 20 to 0 and withdraws
    ///      `V1_INITIAL_YIELD`; the beats that bring the counter to 3 and to 6 run a daily
    ///      cycle each. No bond is purchased, so the withdrawn funds stay on the facility: the
    ///      part redeemed for the markets in USDS, the rest in sUSDS.
    function _runV1() internal {
        uint256 reserveBalance = sUsds.previewRedeem(sUsds.balanceOf(address(treasury)));
        uint256 conversionRate = sUsds.previewRedeem(ONE_SHARE);
        vm.prank(daoMS);
        yieldRepoV1.initialize(reserveBalance, conversionRate, V1_INITIAL_YIELD);

        _beatV1(uint256(V1_EPOCH) + 1);
    }

    function _beatV1(uint256 beats_) internal {
        for (uint256 i = 0; i < beats_; ++i) {
            vm.prank(address(heart));
            yieldRepoV1.endEpoch();
        }
    }

    // ========== ACTIVATOR ========== //

    function _deployment()
        internal
        view
        returns (IYieldRepurchaseFacilityV2Activator.Deployment memory deployment)
    {
        deployment.kernel = address(kernel);
        deployment.backingOracle = address(backingOracle);
        deployment.backingOracleConfigTimelock = address(backingOracleConfigTimelock);
        deployment.config = address(config);
        deployment.configTimelock = address(configTimelock);
        deployment.facility = address(facility);
        deployment.yieldRepoV1 = address(yieldRepoV1);
        deployment.heart = address(heart);
        deployment.priceConfig = address(priceConfig);
        deployment.bondAuctioneer = address(bondAuctioneer);
        deployment.usdeUsdPriceFeed = address(usdeUsdFeed);
        deployment.ohm = address(ohm);
        deployment.usds = address(usds);
        deployment.sUsds = address(sUsds);
        deployment.usde = address(usde);
        deployment.sUsde = address(sUsde);
    }

    /// @notice The launch values: the first two Clearinghouses included, the second one with
    ///         an offset, the third one neither included nor offset.
    function _launchParameters()
        internal
        view
        returns (IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters)
    {
        parameters.backing = BACKING;
        parameters.initialDiscount = INITIAL_DISCOUNT;
        parameters.maxPricePremium = MAX_PRICE_PREMIUM;
        parameters.sUsds = IYieldRepurchaseFacilityV2Activator.AssetParameters({
            yieldBuybackShare: SUSDS_YIELD_BUYBACK_SHARE,
            sellShares: false
        });
        parameters.sUsde = IYieldRepurchaseFacilityV2Activator.AssetParameters({
            yieldBuybackShare: SUSDE_YIELD_BUYBACK_SHARE,
            sellShares: true
        });
        parameters
            .clearinghouses = new IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters[](3);
        parameters.clearinghouses[0] = IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters({
            clearinghouse: address(clearinghouseOne),
            included: true,
            offset: 0
        });
        parameters.clearinghouses[1] = IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters({
            clearinghouse: address(clearinghouseTwo),
            included: true,
            offset: CLEARINGHOUSE_TWO_OFFSET
        });
        parameters.clearinghouses[2] = IYieldRepurchaseFacilityV2Activator.ClearinghouseParameters({
            clearinghouse: address(clearinghouseThree),
            included: false,
            offset: 0
        });
    }

    /// @notice Returns the bound policy at `index_` of the eight whose Kernel the activator
    ///         compares, and the name of the binding.
    function _kernelBound(
        uint256 index_
    ) internal view returns (address policy, string memory binding) {
        if (index_ == 0) return (address(backingOracle), "BackingOracle kernel");
        if (index_ == 1)
            return (address(backingOracleConfigTimelock), "BackingOracleConfigTimelock kernel");
        if (index_ == 2) return (address(config), "YieldRepurchaseFacilityV2Config kernel");
        if (index_ == 3)
            return (address(configTimelock), "YieldRepurchaseFacilityV2ConfigTimelock kernel");
        if (index_ == 4) return (address(facility), "YieldRepurchaseFacilityV2 kernel");
        if (index_ == 5) return (address(yieldRepoV1), "YieldRepurchaseFacility v1.2 kernel");
        if (index_ == 6) return (address(heart), "Heart kernel");
        return (address(priceConfig), "PriceConfig kernel");
    }

    function _deployActivator(
        IYieldRepurchaseFacilityV2Activator.Deployment memory deployment_,
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters_
    ) internal returns (YieldRepurchaseFacilityV2Activator deployed) {
        deployed = new YieldRepurchaseFacilityV2Activator(ocgTimelock, deployment_, parameters_);
        vm.label(address(deployed), "YieldRepurchaseFacilityV2Activator");
    }

    /// @notice Replaces the activator of the rig with one deployed with other launch values,
    ///         and moves the two roles of the launch to it.
    function _replaceActivator(
        IYieldRepurchaseFacilityV2Activator.LaunchParameters memory parameters_
    ) internal {
        rolesAdmin.revokeRole(ADMIN_ROLE, address(activator));
        rolesAdmin.revokeRole(LOOP_DADDY_ROLE, address(activator));
        activator = _deployActivator(_deployment(), parameters_);
        rolesAdmin.grantRole(ADMIN_ROLE, address(activator));
        rolesAdmin.grantRole(LOOP_DADDY_ROLE, address(activator));
    }

    function _activate(uint256 sUsdeNextYield_) internal {
        YieldRepurchaseFacilityV2Activator target = activator;
        vm.prank(ocgTimelock);
        target.activate(sUsdeNextYield_);
    }

    // ========== STATE HELPERS ========== //

    /// @notice Registers USDe in the PRICE module the way the launch does, from the test
    ///         contract as a holder of `admin`.
    function _registerUsde() internal {
        // The USDe feed answers 0.9995 USD, inside the tolerance around 1 USD
        _registerAsset(address(usde), usdeUsdFeed, 1e18, false);
    }

    function _setFeed(MockPriceFeed feed_, int256 answer_, uint256 updatedAt_) internal {
        feed_.setLatestAnswer(answer_);
        feed_.setTimestamp(updatedAt_);
    }

    /// @notice Asserts that nothing of the launch has happened.
    function _assertNotLaunched() internal view {
        assertFalse(activator.isActivated(), "the activator should not be activated");
        assertFalse(backingOracle.isEnabled(), "the oracle should be disabled");
        assertFalse(
            backingOracleConfigTimelock.isEnabled(),
            "the oracle timelock should be disabled"
        );
        assertFalse(config.isEnabled(), "the configuration policy should be disabled");
        assertFalse(configTimelock.isEnabled(), "the config timelock should be disabled");
        assertFalse(facility.isEnabled(), "the facility should be disabled");
        assertEq(config.facility(), address(0), "the configuration policy should be unbound");
        assertEq(facility.configurator(), address(0), "the facility should have no configurator");
        assertEq(facility.getVaults().length, 0, "the facility should have no vault");
        assertFalse(yieldRepoV1.isShutdown(), "v1.2 should not be shut down");
        assertEq(
            IPeriodicTaskManager(address(heart)).getPeriodicTaskIndex(address(yieldRepoV1)),
            V1_TASK_INDEX,
            "v1.2 should keep its periodic task slot"
        );
        assertFalse(price.isAssetApproved(address(usde)), "USDe should not be registered");
    }

    // ========== REVERT HELPERS ========== //

    function _expectRevertBindingMismatch(
        string memory binding_,
        address actual_,
        address expected_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_BindingMismatch
                    .selector,
                binding_,
                actual_,
                expected_
            )
        );
    }

    function _expectRevertPolicyNotActive(address policy_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_PolicyNotActive
                    .selector,
                policy_
            )
        );
    }

    function _expectRevertPolicyNotEnabled(address policy_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_PolicyNotEnabled
                    .selector,
                policy_
            )
        );
    }

    function _expectRevertPolicyAlreadyEnabled(address policy_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_PolicyAlreadyEnabled
                    .selector,
                policy_
            )
        );
    }

    function _expectRevertAlreadyBound(string memory binding_, address value_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_AlreadyBound
                    .selector,
                binding_,
                value_
            )
        );
    }

    function _expectRevertReserveNotPriceable(address reserve_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2Activator
                    .YieldRepurchaseFacilityV2Activator_ReserveNotPriceable
                    .selector,
                reserve_
            )
        );
    }

    // ========== STATE MODIFIERS ========== //

    modifier givenUsdeRegistered() {
        _registerUsde();
        _;
    }
}
