// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {FullMath} from "src/libraries/FullMath.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";

import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {PRICEv1} from "src/modules/PRICE/PRICE.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ERC20 as SolmateERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

import {OlympusHeart} from "src/policies/Heart.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {YRFTimelock} from "src/policies/YieldRepurchaseFacility/YRFTimelock.sol";

// ============ MINIMAL MAINNET INTERFACES ============ //

/// @notice The YRF v1.2 surface used by the migration to v2.
interface IYieldRepoV1 {
    function epoch() external view returns (uint48);

    function isShutdown() external view returns (bool);

    function nextYield() external view returns (uint256);

    function lastReserveBalance() external view returns (uint256);

    function lastConversionRate() external view returns (uint256);

    function getReserveBalance() external view returns (uint256);

    function getNextYield() external view returns (uint256);

    function shutdown(address[] memory tokensToTransfer) external;
}

/// @notice The Bond Protocol SDA auctioneer surface used by the test.
interface IBondAuctioneerLike {
    function setCallbackAuthStatus(address creator_, bool status_) external;

    function callbackAuthorized(address creator_) external view returns (bool);

    function marketPrice(uint256 id_) external view returns (uint256);

    function marketScale(uint256 id_) external view returns (uint256);

    function maxAmountAccepted(uint256 id_, address referrer_) external view returns (uint256);

    function payoutFor(
        uint256 amount_,
        uint256 id_,
        address referrer_
    ) external view returns (uint256);

    function isLive(uint256 id_) external view returns (bool);

    function currentCapacity(uint256 id_) external view returns (uint256);

    function markets(
        uint256 id_
    )
        external
        view
        returns (
            address owner,
            address payoutToken,
            address quoteToken,
            address callbackAddr,
            bool capacityInQuote,
            uint256 capacity,
            uint256 totalDebt,
            uint256 minPrice,
            uint256 maxPayout,
            uint256 sold,
            uint256 purchased,
            uint256 scale
        );
}

/// @notice The Bond Protocol teller surface used by the test.
interface IBondTellerLike {
    function purchase(
        address recipient_,
        address referrer_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_
    ) external returns (uint256 payout, uint48 expiry);
}

/// @notice The Bond Protocol aggregator surface used by the test.
interface IBondAggregatorLike {
    function marketCounter() external view returns (uint256);
}

/// @notice The OHM token surface used by the test (mint is gated to the MINTR module).
interface IOhmLike is IERC20 {
    function mint(address to_, uint256 amount_) external;
}

/// @title YieldRepurchaseFacilityV2ForkTestBase
/// @notice Mainnet-fork base for the YRF v2 end-to-end tests: installs the v2 stack into the
///         live Kernel (DAO MS for kernel actions, the OCG timelock for role-gated
///         configuration), migrates the state of the deployed YRF v1.2 into the v2 seeds,
///         swaps the Heart periodic task, and maintains an exact mirror model of the
///         expected facility state that is asserted after every heart beat.
/// @dev The mirror model replicates the arithmetic of `YieldRepurchaseFacilityV2` (same
///      formulas, same rounding, same ordering) using ERC4626 previews evaluated at the
///      beat timestamp, so all assertions are exact (`assertEq`).
// solhint-disable max-states-count
abstract contract YieldRepurchaseFacilityV2ForkTestBase is Test {
    using FullMath for uint256;

    // ============ FORK CONFIGURATION ============ //

    /// @notice Pinned mainnet block (2026-07-10 00:44:23 UTC). YRF v1.2 is mid-week at
    ///         epoch 9 with a projected `nextYield` and an unspent weekly budget, which the
    ///         setup migrates into the v2 seeds.
    uint256 internal constant FORK_BLOCK = 25_498_685;

    // These addresses are hard-coded, as the values in env.json can change while this test
    // operates on a pinned block.
    address internal constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address internal constant ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
    address internal constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address internal constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;
    address internal constant EMERGENCY_MS = 0xa8A6ff2606b24F61AFA986381D8991DFcCCd2D55;
    address internal constant MINTR_MODULE = 0xa90bFe53217da78D900749eb6Ef513ee5b6a491e;

    address internal constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    address internal constant BOND_AUCTIONEER = 0x007F7A1cb838A872515c8ebd16bE4b14Ef43a222;
    address internal constant BOND_TELLER = 0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6;
    address internal constant BOND_AGGREGATOR = 0x007A66A2a13415DB3613C1a4dd1C942A285902d1;
    /// @notice The owner of the Bond Protocol auctioneer, which grants the callback
    ///         authorization required by the v2 markets.
    address internal constant BOND_OWNER = 0x007BD11FCa0dAaeaDD455b51826F9a015f2f0969;

    address internal constant HEART = 0x5824850D8A6E46a473445a5AF214C7EbD46c5ECB;
    address internal constant YIELD_REPO_V1 = 0x271e35a8555a62F6bA76508E85dfD76D580B0692;
    /// @notice A live policy with TRSRY withdraw permissions, impersonated to simulate a
    ///         treasury outflow (a Cooler V2 borrow).
    address internal constant COOLER_BORROWER = 0xD58d7406E9CE34c90cf849Fc3eed3764EB3779B0;

    /// @notice The registered clearinghouses on the pinned block (all deactivated).
    address internal constant CLEARINGHOUSE_DAI_V1 = 0xD6A6E8d9e82534bD65821142fcCd91ec9cF31880;
    address internal constant CLEARINGHOUSE_DAI_V1_1 = 0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c;
    address internal constant CLEARINGHOUSE_USDS_V1_2 = 0x1e094fE00E13Fd06D64EeA4FB3cD912893606fE0;

    /// @notice The Chainlink feeds read by the PRICE module.
    address internal constant CHAINLINK_OHM_ETH = 0x9a72298ae3886221820B1c878d12D872087D3a23;
    address internal constant CHAINLINK_DAI_ETH = 0x773616E4d11A78F511299002da57A0a94577F1f4;

    // ============ DEPLOYMENT PARAMETERS ============ //

    /// @notice The initial backing value (18 decimals): the value hardcoded in the
    ///         deployed YRF v1.2 ($11.33 per OHM), fixed for the whole test.
    uint256 internal constant BACKING = 11.33e18;
    /// @notice The initial bond market discount (3%, 18 decimals), matching YRF v1.2.
    uint256 internal constant INITIAL_DISCOUNT = 3e16;
    uint32 internal constant GRACE_PERIOD = 5 days;
    uint48 internal constant YRF_TIMELOCK_DELAY = 1 days;

    /// @notice The sUSDS yield buyback share (100%, matching the v1.2 behaviour).
    uint256 internal constant SUSDS_BUYBACK_SHARE = 1e18;
    /// @notice The sUSDe yield buyback share (50%): half of the sUSDe yield is left in the
    ///         treasury, exercising the yield split of v2.
    uint256 internal constant SUSDE_BUYBACK_SHARE = 5e17;
    /// @notice The annualized rate (in basis points) used both for the sUSDe next-yield
    ///         seed estimate and for the simulated Ethena reward stream.
    uint256 internal constant SUSDE_APR_BPS = 400;

    /// @notice The receivables offset applied to the DAI v1.1 Clearinghouse when it is
    ///         included into the backing yield (the governance estimate of its phantom
    ///         receivables at inclusion time).
    uint256 internal constant DAI_V1_1_INITIAL_OFFSET = 2_000_000e18;

    uint256 internal constant ONE_HUNDRED_PERCENT = 1e18;
    uint48 internal constant EPOCH_LENGTH = 21;
    uint48 internal constant EPOCHS_PER_DAY = 3;
    uint256 internal constant DAYS_PER_WEEK = 7;

    // ============ MAINNET CONTRACTS ============ //

    Kernel internal kernel;
    ROLESv1 internal roles;
    RolesAdmin internal rolesAdmin;
    TRSRYv1 internal treasury;
    PRICEv1 internal price;
    CHREGv1 internal chreg;
    OlympusHeart internal heart;
    IYieldRepoV1 internal yieldRepoV1;

    IOhmLike internal ohm;
    IERC20 internal usds;
    IERC4626 internal susds;
    IERC20 internal usde;
    IERC4626 internal susde;

    IBondAuctioneerLike internal auctioneer;
    IBondTellerLike internal teller;
    IBondAggregatorLike internal aggregator;

    // ============ DEPLOYED V2 STACK ============ //

    BackingOracle internal backingOracle;
    YRFTimelock internal yrfTimelock;
    YieldRepurchaseFacilityV2 internal yieldRepo;

    // ============ TEST ACCOUNTS ============ //

    address internal keeper;
    address internal buyer;
    address internal yrfAdmin;
    address internal backingAdmin;
    address internal coolerRecipient;

    // ============ SEEDS (COMPUTED IN setUp) ============ //

    /// @notice The sUSDS next-yield seed: the v1.2 `nextYield` projected at its last weekly
    ///         reset plus the value of the unspent weekly budget swept back to the
    ///         treasury by the v1.2 shutdown.
    uint256 internal susdsSeedYield;
    /// @notice The sUSDS yield snapshots carried over from v1.2, so that the first v2
    ///         weekly reset captures the yield accrued since the last v1.2 reset.
    uint256 internal susdsSeedBalance;
    uint256 internal susdsSeedRate;

    /// @notice The sUSDe next-yield seed: one week of the estimated yield on the current
    ///         treasury holding, scaled by the buyback share.
    uint256 internal susdeSeedYield;
    uint256 internal susdeSeedBalance;
    uint256 internal susdeSeedRate;

    /// @notice The fixed daily reward stream simulated for the whole sUSDe vault.
    uint256 internal susdeDailyReward;

    // ============ ORACLE PRICE STATE ============ //

    int256 internal ohmEthAnswer;
    int256 internal daiEthAnswer;

    // ============ MIRROR MODEL ============ //

    /// @notice The expected per-vault state, mirroring `ReserveAsset` plus the expected
    ///         facility (buyback pool) and TRSRY balances of the vault.
    struct AssetModel {
        bool sellShares;
        uint256 yieldBuybackShare;
        uint256 nextYield;
        uint256 unfundedYield;
        uint256 heldShares;
        uint256 heldReserve;
        uint256 lastConversionRate;
        uint256 lastReserveBalance;
        uint256 trsryShares;
    }

    /// @notice The expected parameters of a bond market created at the last daily beat.
    struct MarketModel {
        bool live;
        uint256 id;
        address payoutToken;
        uint256 capacity;
        uint256 initialPrice;
        uint256 minPrice;
        uint256 scale;
        uint256 maxPayout;
    }

    mapping(address vault => AssetModel) internal model;
    mapping(address vault => MarketModel) internal market;
    uint48 internal modelEpoch;
    uint256 internal modelOhmPurchased;
    /// @notice The number of markets the mirror model expects the pending beat to create.
    uint256 internal modelPendingMarkets;
    /// @notice The raw USDS balance the treasury is expected to hold after a beat (the
    ///         ReserveWrapper normally wraps everything, so this is usually zero).
    uint256 internal modelTrsryRawUsds;

    // ============ SETUP ============ //

    function setUp() public virtual {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        _setupActors();
        _loadMainnetContracts();
        _deployV2Stack();
        _installV2Stack();
        _computeSeeds();
        _shutdownV1();
        _registerAssets();
        _configureClearinghouses();
        _swapHeartTask();
        _initializeOracleState();
        _initializeModel();
    }

    function _setupActors() internal {
        keeper = makeAddr("keeper");
        buyer = makeAddr("buyer");
        yrfAdmin = makeAddr("yrfAdmin");
        backingAdmin = makeAddr("backingAdmin");
        coolerRecipient = makeAddr("coolerRecipient");
    }

    function _loadMainnetContracts() internal {
        kernel = Kernel(KERNEL);
        roles = ROLESv1(address(kernel.getModuleForKeycode(toKeycode("ROLES"))));
        treasury = TRSRYv1(address(kernel.getModuleForKeycode(toKeycode("TRSRY"))));
        price = PRICEv1(address(kernel.getModuleForKeycode(toKeycode("PRICE"))));
        chreg = CHREGv1(address(kernel.getModuleForKeycode(toKeycode("CHREG"))));
        rolesAdmin = RolesAdmin(ROLES_ADMIN);
        heart = OlympusHeart(HEART);
        yieldRepoV1 = IYieldRepoV1(YIELD_REPO_V1);

        ohm = IOhmLike(OHM);
        usds = IERC20(USDS);
        susds = IERC4626(SUSDS);
        usde = IERC20(USDE);
        susde = IERC4626(SUSDE);

        auctioneer = IBondAuctioneerLike(BOND_AUCTIONEER);
        teller = IBondTellerLike(BOND_TELLER);
        aggregator = IBondAggregatorLike(BOND_AGGREGATOR);

        vm.label(KERNEL, "Kernel");
        vm.label(address(roles), "ROLES");
        vm.label(address(treasury), "TRSRY");
        vm.label(address(price), "PRICE");
        vm.label(address(chreg), "CHREG");
        vm.label(ROLES_ADMIN, "RolesAdmin");
        vm.label(TIMELOCK, "Timelock");
        vm.label(DAO_MS, "DaoMS");
        vm.label(EMERGENCY_MS, "EmergencyMS");
        vm.label(MINTR_MODULE, "MINTR");
        vm.label(HEART, "Heart");
        vm.label(YIELD_REPO_V1, "YieldRepoV1");
        vm.label(COOLER_BORROWER, "CoolerBorrower");
        vm.label(OHM, "OHM");
        vm.label(USDS, "USDS");
        vm.label(SUSDS, "sUSDS");
        vm.label(USDE, "USDe");
        vm.label(SUSDE, "sUSDe");
        vm.label(BOND_AUCTIONEER, "BondAuctioneer");
        vm.label(BOND_TELLER, "BondTeller");
        vm.label(BOND_AGGREGATOR, "BondAggregator");
        vm.label(BOND_OWNER, "BondOwner");
        vm.label(CLEARINGHOUSE_DAI_V1, "ClearinghouseDaiV1");
        vm.label(CLEARINGHOUSE_DAI_V1_1, "ClearinghouseDaiV1_1");
        vm.label(CLEARINGHOUSE_USDS_V1_2, "ClearinghouseUsdsV1_2");
        vm.label(CHAINLINK_OHM_ETH, "ChainlinkOhmEth");
        vm.label(CHAINLINK_DAI_ETH, "ChainlinkDaiEth");

        // The reserve-balance model relies on the fact that no clearinghouse is active on
        // the pinned block (the v2 backing balance then equals the TRSRY share balance).
        assertEq(chreg.activeCount(), 0, "setup: active clearinghouses");
    }

    function _deployV2Stack() internal {
        backingOracle = new BackingOracle(kernel);
        vm.label(address(backingOracle), "BackingOracle");

        // The facility pins the YRF timelock as an immutable address, so the timelock is
        // deployed first and wired to the facility afterwards.
        yrfTimelock = new YRFTimelock(kernel, YRF_TIMELOCK_DELAY, GRACE_PERIOD);
        vm.label(address(yrfTimelock), "YRFTimelock");

        yieldRepo = new YieldRepurchaseFacilityV2(
            kernel,
            OHM,
            address(backingOracle),
            BOND_AUCTIONEER,
            BOND_TELLER,
            address(yrfTimelock),
            GRACE_PERIOD
        );
        vm.label(address(yieldRepo), "YieldRepoV2");
    }

    function _installV2Stack() internal {
        // Kernel actions are performed by the kernel executor (the DAO MS)
        vm.startPrank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(backingOracle));
        kernel.executeAction(Actions.ActivatePolicy, address(yrfTimelock));
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRepo));
        vm.stopPrank();

        // Roles are granted by the RolesAdmin admin (the OCG timelock). The admin,
        // emergency, and heart roles already exist on the live actors.
        vm.startPrank(TIMELOCK);
        rolesAdmin.grantRole("yrf_admin", yrfAdmin);
        rolesAdmin.grantRole("backing_admin", backingAdmin);
        vm.stopPrank();

        // The v2 markets use the facility as their callback, which requires the market
        // owner to be authorized on the auctioneer by the Bond Protocol owner.
        vm.prank(BOND_OWNER);
        auctioneer.setCallbackAuthStatus(address(yieldRepo), true);

        // Wire and enable the YRF timelock, enable the backing oracle (before the
        // facility, so that the price gate never sees a zero backing), and enable the
        // facility itself. `enable` is called before the assets are registered, so that
        // its cycle reset does not overwrite the migration seeds below.
        vm.startPrank(TIMELOCK);
        yrfTimelock.setFacility(address(yieldRepo));
        yrfTimelock.enable("");
        backingOracle.enable(abi.encode(BACKING));
        yieldRepo.enable(
            abi.encode(INITIAL_DISCOUNT, new IYieldRepurchaseFacilityV2.NextYieldSeed[](0))
        );
        vm.stopPrank();
    }

    function _computeSeeds() internal {
        // sUSDS: continue the v1.2 accounting.
        // - The next-yield seed is the yield already earmarked by v1.2: its projected
        //   `nextYield` plus the value of the unspent weekly budget still held by v1.2
        //   (swept back to the treasury by the shutdown below).
        // - The snapshots are carried over verbatim, so that the first v2 weekly reset
        //   projects the yield accrued since the last v1.2 weekly reset.
        uint256 v1Residual = usds.balanceOf(YIELD_REPO_V1) +
            susds.previewRedeem(susds.balanceOf(YIELD_REPO_V1));
        susdsSeedYield = yieldRepoV1.nextYield() + v1Residual;
        susdsSeedBalance = yieldRepoV1.lastReserveBalance();
        susdsSeedRate = yieldRepoV1.lastConversionRate();

        // sUSDe: no v1 history. The snapshots start at the live values and the next-yield
        // seed is the governance estimate of one week of yield on the current treasury
        // holding, scaled by the buyback share:
        // seed = value * SUSDE_APR_BPS / 10000 / 52 * share / 1e18 (floor at each step).
        susdeSeedBalance = susde.previewRedeem(susde.balanceOf(address(treasury)));
        susdeSeedRate = susde.previewRedeem(1e18);
        susdeSeedYield = ((susdeSeedBalance * SUSDE_APR_BPS) / 10_000 / 52).mulDiv(
            SUSDE_BUYBACK_SHARE,
            ONE_HUNDRED_PERCENT
        );

        // The simulated Ethena reward stream: SUSDE_APR_BPS on the whole vault, fixed at
        // the setup-time total assets.
        susdeDailyReward = (susde.totalAssets() * SUSDE_APR_BPS) / 10_000 / 365;
    }

    function _shutdownV1() internal {
        // The v1.2 shutdown burns its OHM balance and sweeps the listed tokens to the
        // treasury; it is executed by the DAO MS (a loop_daddy holder).
        address[] memory tokensToTransfer = new address[](2);
        tokensToTransfer[0] = USDS;
        tokensToTransfer[1] = SUSDS;
        vm.prank(DAO_MS);
        yieldRepoV1.shutdown(tokensToTransfer);

        assertTrue(yieldRepoV1.isShutdown(), "setup: v1 shutdown");
        assertEq(usds.balanceOf(YIELD_REPO_V1), 0, "setup: v1 USDS swept");
        assertEq(susds.balanceOf(YIELD_REPO_V1), 0, "setup: v1 sUSDS swept");
        assertEq(ohm.balanceOf(YIELD_REPO_V1), 0, "setup: v1 OHM burned");
    }

    function _registerAssets() internal {
        vm.startPrank(TIMELOCK);
        yieldRepo.addAsset(
            SUSDS,
            SUSDS_BUYBACK_SHARE,
            susdsSeedBalance,
            susdsSeedRate,
            susdsSeedYield,
            false, // sellShares
            true // setAsBackingVault
        );
        yieldRepo.addAsset(
            SUSDE,
            SUSDE_BUYBACK_SHARE,
            susdeSeedBalance,
            susdeSeedRate,
            susdeSeedYield,
            true, // sellShares: sUSDe redeem reverts while the cooldown is active
            false
        );
        vm.stopPrank();
    }

    function _configureClearinghouses() internal {
        // The DAI clearinghouses accrue to the backing reserve through the 1:1 DAI->USDS
        // migration, so they are included explicitly; the v1.1 inclusion is accompanied by
        // an offset for its phantom receivables.
        vm.startPrank(TIMELOCK);
        yieldRepo.includeClearinghouse(CLEARINGHOUSE_DAI_V1);
        yieldRepo.includeClearinghouse(CLEARINGHOUSE_DAI_V1_1);
        yieldRepo.setClearinghouseOffset(CLEARINGHOUSE_DAI_V1_1, DAI_V1_1_INITIAL_OFFSET);
        vm.stopPrank();
    }

    function _swapHeartTask() internal {
        // YRF v1.2 occupies slot 4 of the Heart pipeline with a custom endEpoch selector;
        // v2 implements IPeriodicTask, so it is registered with the default selector.
        (address[] memory tasksBefore, ) = heart.getPeriodicTasks();
        assertEq(tasksBefore[4], YIELD_REPO_V1, "setup: v1 heart slot");

        vm.startPrank(TIMELOCK);
        heart.removePeriodicTaskAtIndex(4);
        heart.addPeriodicTaskAtIndex(address(yieldRepo), bytes4(0), 4);
        vm.stopPrank();

        (address[] memory tasksAfter, ) = heart.getPeriodicTasks();
        assertEq(tasksAfter[4], address(yieldRepo), "setup: v2 heart slot");
        assertEq(tasksAfter.length, tasksBefore.length, "setup: task count");
    }

    function _initializeOracleState() internal {
        // Start the simulated price path from the live feed answers at the pinned block
        (, ohmEthAnswer, , , ) = AggregatorV3Interface(CHAINLINK_OHM_ETH).latestRoundData();
        (, daiEthAnswer, , , ) = AggregatorV3Interface(CHAINLINK_DAI_ETH).latestRoundData();
    }

    function _initializeModel() internal {
        model[SUSDS] = AssetModel({
            sellShares: false,
            yieldBuybackShare: SUSDS_BUYBACK_SHARE,
            nextYield: susdsSeedYield,
            unfundedYield: 0,
            heldShares: 0,
            heldReserve: 0,
            lastConversionRate: susdsSeedRate,
            lastReserveBalance: susdsSeedBalance,
            trsryShares: susds.balanceOf(address(treasury))
        });
        model[SUSDE] = AssetModel({
            sellShares: true,
            yieldBuybackShare: SUSDE_BUYBACK_SHARE,
            nextYield: susdeSeedYield,
            unfundedYield: 0,
            heldShares: 0,
            heldReserve: 0,
            lastConversionRate: susdeSeedRate,
            lastReserveBalance: susdeSeedBalance,
            trsryShares: susde.balanceOf(address(treasury))
        });
        modelEpoch = 20;
        modelOhmPurchased = 0;
    }

    // ============ BEAT DRIVER ============ //

    /// @notice Advances to the next heart beat slot, refreshes the Chainlink mocks,
    ///         applies the expected state transition to the mirror model, executes the
    ///         beat, and asserts the resulting on-chain state against the model.
    function _beat() internal {
        vm.warp(heart.lastBeat() + heart.frequency());
        _updateOracles();
        _measureExternalPipelineEffects();

        uint256 marketCountBefore = aggregator.marketCounter();
        _applyModelBeat(marketCountBefore);

        vm.prank(keeper);
        heart.beat();

        _assertBeat(marketCountBefore);
    }

    /// @notice Measures the exact treasury effects of the non-facility pipeline tasks for
    ///         the pending beat: executes the beat with the facility disabled on a state
    ///         snapshot, records the treasury deltas, and reverts. The other tasks do not
    ///         read the facility state, so the measured deltas match the real beat that
    ///         follows. This captures the ReserveWrapper wrap of the raw USDS balance and
    ///         the sUSDS interest swept to the treasury by the deposit facility task.
    function _measureExternalPipelineEffects() internal {
        uint256 susdsBefore = susds.balanceOf(address(treasury));
        uint256 susdeBefore = susde.balanceOf(address(treasury));

        uint256 snapshotId = vm.snapshotState();

        vm.prank(TIMELOCK);
        yieldRepo.disable("");
        vm.prank(keeper);
        heart.beat();

        uint256 externalSusds = susds.balanceOf(address(treasury)) - susdsBefore;
        uint256 externalSusde = susde.balanceOf(address(treasury)) - susdeBefore;
        uint256 externalRawUsds = usds.balanceOf(address(treasury));

        assertTrue(vm.revertToState(snapshotId), "snapshot revert failed");
        // Cheatcode mocks are not part of the state snapshot; refresh them regardless.
        _updateOracles();

        model[SUSDS].trsryShares += externalSusds;
        model[SUSDE].trsryShares += externalSusde;
        modelTrsryRawUsds = externalRawUsds;
    }

    /// @notice Re-mocks both Chainlink feeds with the current simulated answers and a
    ///         fresh timestamp. Required before every beat: `PRICE.updateMovingAverage`
    ///         and the EmissionManager task read the live feeds and revert on staleness.
    function _updateOracles() internal {
        vm.mockCall(
            CHAINLINK_OHM_ETH,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(
                uint80(block.number),
                ohmEthAnswer,
                block.timestamp,
                block.timestamp,
                uint80(block.number)
            )
        );
        vm.mockCall(
            CHAINLINK_DAI_ETH,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(
                uint80(block.number),
                daiEthAnswer,
                block.timestamp,
                block.timestamp,
                uint80(block.number)
            )
        );
    }

    /// @notice Applies a relative change (in signed basis points) to the OHM/ETH answer,
    ///         moving the OHM price for the subsequent beats.
    function _applyPriceDeltaBps(int256 deltaBps_) internal {
        ohmEthAnswer = (ohmEthAnswer * (10_000 + deltaBps_)) / 10_000;
    }

    /// @notice The oracle price the PRICE module stores at the pending beat:
    ///         ohmEth (18 dec) * 1e18 / daiEth (18 dec) -> 18 decimals (floor).
    function _expectedOraclePrice() internal view returns (uint256) {
        return uint256(ohmEthAnswer).mulDiv(1e18, uint256(daiEthAnswer));
    }

    // ============ MIRROR MODEL: BEAT TRANSITION ============ //

    /// @notice Mirrors one `execute()` call of the facility, using previews evaluated at
    ///         the already-warped beat timestamp. The treasury effects of the tasks that
    ///         run before the facility in the same beat have already been applied to the
    ///         model by `_measureExternalPipelineEffects`.
    function _applyModelBeat(uint256 marketCountBefore_) internal {
        modelPendingMarkets = 0;
        market[SUSDS].live = false;
        market[SUSDE].live = false;

        modelEpoch += 1;
        if (modelEpoch % EPOCHS_PER_DAY != 0) return;

        if (modelEpoch == EPOCH_LENGTH) {
            modelEpoch = 0;
            _modelWeeklyReset();
        }

        _modelProcessOhmPurchases();

        uint256 oraclePrice = _expectedOraclePrice();
        if (oraclePrice < BACKING) return;

        uint256 daysRemaining = DAYS_PER_WEEK - uint256(modelEpoch / EPOCHS_PER_DAY);
        _modelDailyCycle(SUSDS, daysRemaining, oraclePrice, marketCountBefore_);
        _modelDailyCycle(SUSDE, daysRemaining, oraclePrice, marketCountBefore_);
    }

    function _modelWeeklyReset() internal {
        uint256 clearinghouseYield = _modelClearinghouseYield();
        _modelWeeklyResetVault(SUSDS, clearinghouseYield);
        _modelWeeklyResetVault(SUSDE, 0);
    }

    function _modelWeeklyResetVault(address vault_, uint256 clearinghouseYield_) internal {
        AssetModel storage m = model[vault_];
        IERC4626 vault = IERC4626(vault_);

        // The sanctioned funding target: the stored projection plus the carried
        // shortfall. It does not depend on the facility's balances.
        uint256 fundingTarget = m.nextYield + m.unfundedYield;

        // Projection for the next week: snapshot-based vault yield plus the clearinghouse
        // yield (backing vault only), scaled by the buyback share.
        uint256 currentRate = vault.previewRedeem(1e18);
        uint256 vaultYield = 0;
        if (m.lastConversionRate != 0 && currentRate > m.lastConversionRate) {
            vaultYield = m.lastReserveBalance.mulDiv(
                currentRate - m.lastConversionRate,
                m.lastConversionRate
            );
        }
        m.nextYield = (vaultYield + clearinghouseYield_).mulDiv(
            m.yieldBuybackShare,
            ONE_HUNDRED_PERCENT
        );

        m.lastConversionRate = currentRate;

        // Funding withdrawal: shares worth the target, capped at the treasury balance;
        // the uncovered remainder is carried.
        uint256 funded = 0;
        if (fundingTarget != 0) {
            uint256 shares = vault.previewWithdraw(fundingTarget);
            if (shares > m.trsryShares) shares = m.trsryShares;
            if (shares != 0) {
                funded = vault.previewRedeem(shares);
                m.heldShares += shares;
                m.trsryShares -= shares;
            }
        }
        m.unfundedYield = Math.saturatingSub(fundingTarget, funded);

        // The balance snapshot is taken after the funding withdrawal. No clearinghouse
        // is active on the pinned block, so the protocol balance is the TRSRY share
        // balance.
        m.lastReserveBalance = vault.previewRedeem(m.trsryShares);
    }

    /// @notice Mirrors `_clearinghouseYield`: iterates the CHREG registry and counts the
    ///         clearinghouses whose reserve matches USDS or that are explicitly included,
    ///         applying the receivables offsets.
    function _modelClearinghouseYield() internal view returns (uint256 yield) {
        uint256 len = chreg.registryCount();
        for (uint256 i = 0; i < len; ++i) {
            address ch = chreg.registry(i);
            bool counted = yieldRepo.isClearinghouseIncluded(ch) || _readReserve(ch) == USDS;
            if (!counted) continue;

            uint256 receivables = _readPrincipalReceivables(ch);
            uint256 effective = Math.saturatingSub(receivables, yieldRepo.clearinghouseOffset(ch));
            yield += (effective * 5) / 1000 / 52;
        }
    }

    function _modelProcessOhmPurchases() internal {
        if (modelOhmPurchased == 0) return;

        AssetModel storage m = model[SUSDS];

        // backingAmount = purchased (9 dec) * BACKING (18 dec) / 1e9 -> 18 decimals
        uint256 backingAmount = modelOhmPurchased.mulDiv(BACKING, 1e9);
        if (backingAmount == 0) return;

        uint256 shares = susds.previewWithdraw(backingAmount);
        if (shares > m.trsryShares) shares = m.trsryShares;
        if (shares == 0) return;

        uint256 funded = susds.previewRedeem(shares);
        uint256 ohmToBurn = funded >= backingAmount
            ? modelOhmPurchased
            : modelOhmPurchased.mulDiv(funded, backingAmount);
        if (ohmToBurn == 0) return;

        // The withdrawn shares join the backing vault's buyback pool as shares
        modelOhmPurchased -= ohmToBurn;
        m.trsryShares -= shares;
        m.heldShares += shares;
    }

    function _modelDailyCycle(
        address vault_,
        uint256 daysRemaining_,
        uint256 oraclePrice_,
        uint256 marketCountBefore_
    ) internal {
        AssetModel storage m = model[vault_];
        IERC4626 vault = IERC4626(vault_);
        uint256 marketOraclePrice = oraclePrice_;
        address payoutToken;
        uint256 capacity;

        if (m.sellShares) {
            // The idle reserve is wrapped into vault shares before the sizing
            if (m.heldReserve != 0) {
                m.heldShares += vault.previewDeposit(m.heldReserve);
                m.heldReserve = 0;
            }

            uint256 bidAmount = vault.previewRedeem(m.heldShares) / daysRemaining_;
            if (bidAmount == 0) return;

            uint256 capacityShares = Math.min(vault.previewWithdraw(bidAmount), m.heldShares);
            if (capacityShares == 0) return;

            uint256 conversionRate = vault.previewRedeem(1e18);
            if (conversionRate == 0) return;

            // The oracle price is quoted per reserve token; a share is worth
            // `conversionRate` reserve tokens, so the per-share price scales up.
            marketOraclePrice = oraclePrice_.mulDiv(1e18, conversionRate);
            payoutToken = vault_;
            capacity = capacityShares;
        } else {
            uint256 currentReserve = m.heldReserve;
            uint256 bidAmount = (currentReserve + vault.previewRedeem(m.heldShares)) /
                daysRemaining_;
            if (bidAmount == 0) return;

            if (currentReserve < bidAmount) {
                uint256 deficit = bidAmount - currentReserve;
                uint256 sharesNeeded = vault.previewWithdraw(deficit);
                uint256 sharesToRedeem = sharesNeeded > m.heldShares ? m.heldShares : sharesNeeded;
                uint256 redeemed = sharesToRedeem == 0 ? 0 : vault.previewRedeem(sharesToRedeem);

                m.heldShares -= sharesToRedeem;
                m.heldReserve += redeemed;

                if (redeemed < deficit) bidAmount = currentReserve + redeemed;
            }
            if (bidAmount == 0) return;

            payoutToken = USDS;
            capacity = bidAmount;
        }

        (uint256 initialPrice, uint256 minPrice, int8 scaleAdjustment) = _mirrorMarketPricing(
            marketOraclePrice
        );

        market[vault_] = MarketModel({
            live: true,
            id: marketCountBefore_ + modelPendingMarkets,
            payoutToken: payoutToken,
            capacity: capacity,
            initialPrice: initialPrice,
            minPrice: minPrice,
            scale: 10 ** uint8(36 + scaleAdjustment),
            // maxPayout = capacity * depositInterval / duration = capacity / 6 (floor)
            maxPayout: capacity / 6
        });
        modelPendingMarkets += 1;
    }

    /// @notice Mirrors the `YRFBondMarketLib` market pricing for 18-decimal payout tokens and the
    ///         18-decimal oracle.
    function _mirrorMarketPricing(
        uint256 oraclePrice_
    )
        internal
        pure
        returns (uint256 formattedInitialPrice, uint256 formattedMinimumPrice, int8 scaleAdjustment)
    {
        uint256 discountFactor = ONE_HUNDRED_PERCENT - INITIAL_DISCOUNT;
        uint256 effectivePrice = oraclePrice_.mulDiv(discountFactor, ONE_HUNDRED_PERCENT);
        uint256 oracleSquare = 1e36;

        uint256 initialPrice = oracleSquare / effectivePrice;
        uint256 minPrice = oracleSquare / oraclePrice_;

        int8 priceDecimals = _mirrorPriceDecimals(initialPrice);
        // scaleAdjustment = reserveDecimals - ohmDecimals + priceDecimals / 2
        scaleAdjustment = int8(18) - int8(9) + (priceDecimals / 2);

        uint256 oracleScale = 10 ** uint8(int8(18) - priceDecimals);
        uint256 bondScale = 10 ** uint8(36 + scaleAdjustment + int8(9) - int8(18) - priceDecimals);

        formattedInitialPrice = initialPrice.mulDiv(bondScale, oracleScale);
        formattedMinimumPrice = minPrice.mulDiv(bondScale, oracleScale);
    }

    function _mirrorPriceDecimals(uint256 price_) internal pure returns (int8) {
        int8 decimals;
        while (price_ >= 10) {
            price_ = price_ / 10;
            ++decimals;
        }
        return decimals - int8(18);
    }

    // ============ ASSERTIONS ============ //

    /// @notice Asserts the full facility state, the treasury balances, the oracle price,
    ///         and the parameters of any created markets against the mirror model.
    function _assertBeat(uint256 marketCountBefore_) internal view {
        assertEq(yieldRepo.epoch(), modelEpoch, "epoch");
        assertEq(price.getLastPrice(), _expectedOraclePrice(), "oracle price");
        assertEq(
            aggregator.marketCounter(),
            marketCountBefore_ + modelPendingMarkets,
            "created market count"
        );

        _assertAsset(SUSDS, "sUSDS");
        _assertAsset(SUSDE, "sUSDe");
        _assertHoldings();

        if (market[SUSDS].live) _assertMarket(SUSDS, "sUSDS");
        if (market[SUSDE].live) _assertMarket(SUSDE, "sUSDe");
    }

    function _assertAsset(address vault_, string memory label_) internal view {
        AssetModel storage m = model[vault_];
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(vault_);

        assertEq(config.nextYield, m.nextYield, string.concat(label_, ": nextYield"));
        assertEq(config.unfundedYield, m.unfundedYield, string.concat(label_, ": unfundedYield"));
        assertEq(
            config.lastConversionRate,
            m.lastConversionRate,
            string.concat(label_, ": lastConversionRate")
        );
        assertEq(
            config.lastReserveBalance,
            m.lastReserveBalance,
            string.concat(label_, ": lastReserveBalance")
        );
    }

    /// @notice Asserts that the token holdings of the facility (the buyback pools) and
    ///         the treasury match the mirror model exactly.
    function _assertHoldings() internal view {
        assertEq(
            susds.balanceOf(address(yieldRepo)),
            model[SUSDS].heldShares,
            "holdings: facility sUSDS"
        );
        assertEq(
            usds.balanceOf(address(yieldRepo)),
            model[SUSDS].heldReserve,
            "holdings: facility USDS"
        );
        assertEq(
            susde.balanceOf(address(yieldRepo)),
            model[SUSDE].heldShares,
            "holdings: facility sUSDe"
        );
        assertEq(
            usde.balanceOf(address(yieldRepo)),
            model[SUSDE].heldReserve,
            "holdings: facility USDe"
        );
        assertEq(ohm.balanceOf(address(yieldRepo)), modelOhmPurchased, "holdings: facility OHM");
        assertEq(yieldRepo.ohmPurchased(), modelOhmPurchased, "holdings: ohmPurchased");

        assertEq(
            susds.balanceOf(address(treasury)),
            model[SUSDS].trsryShares,
            "holdings: TRSRY sUSDS"
        );
        assertEq(
            susde.balanceOf(address(treasury)),
            model[SUSDE].trsryShares,
            "holdings: TRSRY sUSDe"
        );
        assertEq(usds.balanceOf(address(treasury)), modelTrsryRawUsds, "holdings: TRSRY raw USDS");
    }

    function _assertMarket(address vault_, string memory label_) internal view {
        MarketModel storage expected = market[vault_];
        (
            address owner,
            address payoutToken,
            address quoteToken,
            address callbackAddr,
            bool capacityInQuote,
            uint256 capacity,
            ,
            uint256 minPrice,
            uint256 maxPayout,
            ,
            ,
            uint256 scale
        ) = auctioneer.markets(expected.id);

        assertEq(owner, address(yieldRepo), string.concat(label_, " market: owner"));
        assertEq(payoutToken, expected.payoutToken, string.concat(label_, " market: payout"));
        assertEq(quoteToken, OHM, string.concat(label_, " market: quote"));
        assertEq(callbackAddr, address(yieldRepo), string.concat(label_, " market: callback"));
        assertEq(capacityInQuote, false, string.concat(label_, " market: capacityInQuote"));
        assertEq(capacity, expected.capacity, string.concat(label_, " market: capacity"));
        assertEq(minPrice, expected.minPrice, string.concat(label_, " market: minPrice"));
        assertEq(maxPayout, expected.maxPayout, string.concat(label_, " market: maxPayout"));
        assertEq(scale, expected.scale, string.concat(label_, " market: scale"));
        assertEq(
            auctioneer.marketPrice(expected.id),
            expected.initialPrice,
            string.concat(label_, " market: initial price")
        );
        assertEq(
            yieldRepo.marketReserves(expected.id),
            vault_ == SUSDS ? USDS : USDE,
            string.concat(label_, " market: marketReserves")
        );
    }

    // ============ BOND PURCHASES ============ //

    /// @notice Buys `fractionBps_` of the capacity of the market created for `vault_` at
    ///         the last daily beat, in chunks bounded by `maxAmountAccepted`, and applies
    ///         the expected callback accounting to the mirror model.
    function _buyBonds(address vault_, uint256 fractionBps_) internal {
        MarketModel storage mkt = market[vault_];
        if (!mkt.live || fractionBps_ == 0) return;

        AssetModel storage m = model[vault_];
        uint256 targetPayout = (mkt.capacity * fractionBps_) / 10_000;
        uint256 boughtPayout = 0;

        for (uint256 i = 0; i < 16 && boughtPayout < targetPayout; ++i) {
            uint256 amountIn = _purchaseAmountIn(mkt.id, targetPayout - boughtPayout);
            if (amountIn == 0) break;

            uint256 expectedPayout = auctioneer.payoutFor(amountIn, mkt.id, address(0));

            // Mint the quote OHM to the buyer: the MINTR module is the OHM vault
            vm.prank(MINTR_MODULE);
            ohm.mint(buyer, amountIn);

            vm.startPrank(buyer);
            ohm.approve(BOND_TELLER, amountIn);
            (uint256 payout, ) = teller.purchase(
                buyer,
                address(0),
                mkt.id,
                amountIn,
                expectedPayout
            );
            vm.stopPrank();

            // Mirror the callback accounting: the payout leaves the buyback pool
            modelOhmPurchased += amountIn;
            if (m.sellShares) {
                m.heldShares = Math.saturatingSub(m.heldShares, payout);
            } else {
                m.heldReserve = Math.saturatingSub(m.heldReserve, payout);
            }
            boughtPayout += payout;
        }

        assertGt(boughtPayout, 0, "purchase: nothing bought");
        _assertHoldings();
    }

    /// @notice Computes the quote amount for the next purchase chunk: enough for the
    ///         remaining payout target at the current market price, capped by
    ///         `maxAmountAccepted` (which respects both maxPayout and capacity).
    function _purchaseAmountIn(
        uint256 marketId_,
        uint256 remainingPayout_
    ) internal view returns (uint256) {
        uint256 currentPrice = auctioneer.marketPrice(marketId_);
        uint256 scale = auctioneer.marketScale(marketId_);
        // payout = amount * scale / price (floor), so amount = payout * price / scale,
        // rounded up to not undershoot the target.
        uint256 amountIn = remainingPayout_.mulDivUp(currentPrice, scale);
        uint256 maxAccepted = auctioneer.maxAmountAccepted(marketId_, address(0));
        return amountIn > maxAccepted ? maxAccepted : amountIn;
    }

    // ============ SCENARIO EVENTS ============ //

    /// @notice Simulates one day of Ethena rewards: increases the USDe balance of the
    ///         sUSDe vault, which raises `totalAssets` and the share conversion rate.
    function _accrueSusdeRewards() internal {
        deal(USDE, SUSDE, usde.balanceOf(SUSDE) + susdeDailyReward, true);
    }

    /// @notice Simulates a treasury revenue inflow: raw USDS lands on the TRSRY and is
    ///         wrapped into sUSDS by the ReserveWrapper at the next beat.
    function _trsryUsdsInflow(uint256 amount_) internal {
        deal(USDS, address(treasury), usds.balanceOf(address(treasury)) + amount_, true);
    }

    /// @notice Simulates a treasury outflow (a Cooler V2 borrow): the treasury borrower
    ///         policy withdraws sUSDS shares from the TRSRY.
    function _trsrySusdsOutflow(uint256 shares_) internal {
        vm.startPrank(COOLER_BORROWER);
        treasury.increaseWithdrawApproval(COOLER_BORROWER, SolmateERC20(SUSDS), shares_);
        treasury.withdrawReserves(coolerRecipient, SolmateERC20(SUSDS), shares_);
        vm.stopPrank();

        model[SUSDS].trsryShares -= shares_;
    }

    // ============ CLEARINGHOUSE HELPERS ============ //

    /// @notice Reads `reserve()` of a clearinghouse, tolerating a missing selector (the
    ///         DAI v1/v1.1 clearinghouses expose `dai()` instead).
    function _readReserve(address clearinghouse_) internal view returns (address) {
        (bool success, bytes memory data) = clearinghouse_.staticcall(
            abi.encodeWithSignature("reserve()")
        );
        if (!success || data.length < 32) return address(0);
        return abi.decode(data, (address));
    }

    function _readPrincipalReceivables(address clearinghouse_) internal view returns (uint256) {
        (bool success, bytes memory data) = clearinghouse_.staticcall(
            abi.encodeWithSignature("principalReceivables()")
        );
        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }
}
