// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// forge-lint: disable-start(calls-loop,reentrancy-no-eth)

import {YieldRepurchaseFacilityV2ForkTestBase} from "./YieldRepurchaseFacilityV2ForkTestBase.sol";

import {Vm} from "@forge-std-1.16.2/Vm.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2MathLib} from "src/policies/YieldRepurchaseFacility/libraries/internal/YieldRepurchaseFacilityV2MathLib.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @title YieldRepurchaseFacilityV2ForkTests_E2E
/// @notice End-to-end mainnet-fork test of the YRF v2: migrates from the deployed
///         YRF v1.2 and drives the facility through two full weekly cycles with real
///         heart beats, daily oracle price moves in both directions, full and partial
///         bond market buyouts on both assets (sUSDS reserve markets and sUSDe share
///         markets), simulated sUSDe rewards, treasury in/outflows, a mid-week
///         clearinghouse offset increase, and a one-day stale USDe feed that skips only
///         the sUSDe daily cycle. Every beat is asserted exactly against the mirror
///         model of the base contract.
contract YieldRepurchaseFacilityV2ForkTests_E2E is YieldRepurchaseFacilityV2ForkTestBase {
    using FullMath for uint256;

    // ============ PINNED-BLOCK ANCHORS ============ //

    // The following literals pin the seed derivation to the fork block, guarding the
    // runtime computation in the setup against silent regressions.

    /// @notice YRF v1.2 `nextYield` at the fork block.
    uint256 internal constant ANCHOR_V1_NEXT_YIELD = 4_928_271_123_449_554_446_677;
    /// @notice YRF v1.2 `lastReserveBalance` at the fork block.
    uint256 internal constant ANCHOR_V1_LAST_RESERVE_BALANCE = 6_233_970_843_384_700_549_263_322;
    /// @notice YRF v1.2 `lastConversionRate` at the fork block.
    uint256 internal constant ANCHOR_V1_LAST_CONVERSION_RATE = 1_105_110_460_979_110_481;

    // susdsSeedYield = v1.nextYield + v1 USDS balance + previewRedeem(v1 sUSDS balance)
    //                = 4928271123449554446677 + 581035073856701697328
    //                  + 6962457638133393135336
    //                = 12471763835439649279341 (18 decimals, ~12472 USDS).
    uint256 internal constant ANCHOR_SUSDS_SEED_YIELD = 12_471_763_835_439_649_279_341;

    // susdeSeedBalance = susde.previewRedeem(susde.balanceOf(TRSRY))
    //                  = previewRedeem(24659208386952951521922260)
    //                  = 30625819877463308069230224 (~30.6M USDe).
    uint256 internal constant ANCHOR_SUSDE_SEED_BALANCE = 30_625_819_877_463_308_069_230_224;

    // susdeSeedYield = susdeSeedBalance * 400 / 10000 / 52 * 5e17 / 1e18
    //                = 30625819877463308069230224 * 400 / 10000 / 52 / 2
    //                = 11779161491332041565088 (~11779 USDe, floor at each step).
    uint256 internal constant ANCHOR_SUSDE_SEED_YIELD = 11_779_161_491_332_041_565_088;

    // The live CURRENT OHM price resolved by the PRICE module at the fork block
    // (~$18.66 per OHM, 18 decimals), captured as the base of the steered price path.
    uint256 internal constant ANCHOR_INITIAL_PRICE = 18_658_476_018_160_737_830;

    // ============ SCENARIO TABLES (ONE ENTRY PER DAY) ============ //

    /// @notice Daily oracle price moves in signed basis points, applied to the steered
    ///         OHM/USD price before the daily beat. Mixed directions, bounded by ~2.2%
    ///         per day, so the price stays well above the backing for the whole test.
    int256[14] internal PRICE_DELTA_BPS = [
        int256(150),
        -220,
        80,
        -130,
        190,
        -90,
        60,
        -180,
        140,
        -70,
        210,
        -160,
        90,
        -110
    ];

    /// @notice The fraction of the daily sUSDS market capacity bought each day (bps).
    ///         10000 = a full buyout, 0 = no participation.
    uint256[14] internal BUY_SUSDS_BPS = [
        uint256(10_000),
        6000,
        0,
        3000,
        10_000,
        4500,
        2500,
        5000,
        10_000,
        0,
        7000,
        3500,
        10_000,
        6000
    ];

    /// @notice The fraction of the daily sUSDe share market capacity bought each day (bps).
    uint256[14] internal BUY_SUSDE_BPS = [
        uint256(4000),
        10_000,
        0,
        0,
        6500,
        10_000,
        3000,
        8000,
        0,
        10_000,
        2000,
        5500,
        7500,
        10_000
    ];

    // ============ SCENARIO EVENT PARAMETERS ============ //

    /// @notice The treasury revenue inflow simulated on day 3 (raw USDS, wrapped into
    ///         sUSDS by the ReserveWrapper at the following beat).
    uint256 internal constant TRSRY_INFLOW_USDS = 2_000_000e18;

    /// @notice The treasury outflow (a Cooler V2 borrow) simulated on day 10, in sUSDS
    ///         shares.
    uint256 internal constant TRSRY_OUTFLOW_SUSDS_SHARES = 1_400_000e18;

    /// @notice The additional receivables offset queued on day 4 through the config timelock
    ///         and executed on day 5.
    uint256 internal constant CLEARINGHOUSE_V1_1_OFFSET_INCREASE = 2_000_000e18;

    // ============ SCENARIO DAYS ============ //

    /// @notice The day of the treasury revenue inflow, landed after the daily beat.
    uint256 internal constant TRSRY_INFLOW_DAY = 2;

    /// @notice The day without purchases, on which the SDA decay of both markets is observed
    ///         at the intra-day beats.
    uint256 internal constant PRICE_DECAY_DAY = 2;

    /// @notice The day the Clearinghouse v1.1 offset increase is queued through the config
    ///         timelock, after the direct facility path is shown closed to the yrf_admin.
    uint256 internal constant OFFSET_QUEUE_DAY = 4;

    /// @notice The day the queued offset increase is executed, one timelock delay later.
    uint256 internal constant OFFSET_INCREASE_DAY = 5;

    /// @notice The day whose daily beat runs on a stale USDe feed.
    uint256 internal constant STALE_USDE_FEED_DAY = 8;

    /// @notice The day of the treasury outflow (a Cooler V2 borrow), after the daily beat.
    uint256 internal constant TRSRY_OUTFLOW_DAY = 9;

    // ============ SCENARIO STATE ============ //

    /// @notice The ID of the offset increase queued on the config timelock.
    uint64 internal offsetActionId;

    // ============ SETUP VALIDATION ============ //

    function test_setup() public view {
        // The v1.2 state feeding the migration matches the pinned block
        assertEq(yieldRepoV1.nextYield(), ANCHOR_V1_NEXT_YIELD, "v1 nextYield");
        assertEq(
            yieldRepoV1.lastReserveBalance(),
            ANCHOR_V1_LAST_RESERVE_BALANCE,
            "v1 lastReserveBalance"
        );
        assertEq(
            yieldRepoV1.lastConversionRate(),
            ANCHOR_V1_LAST_CONVERSION_RATE,
            "v1 lastConversionRate"
        );
        assertTrue(yieldRepoV1.isShutdown(), "v1 isShutdown");

        // The computed seeds match the anchors
        assertEq(susdsSeedYield, ANCHOR_SUSDS_SEED_YIELD, "sUSDS seed yield");
        assertEq(susdsSeedBalance, ANCHOR_V1_LAST_RESERVE_BALANCE, "sUSDS seed balance");
        assertEq(susdsSeedRate, ANCHOR_V1_LAST_CONVERSION_RATE, "sUSDS seed rate");
        assertEq(susdeSeedBalance, ANCHOR_SUSDE_SEED_BALANCE, "sUSDe seed balance");
        assertEq(susdeSeedYield, ANCHOR_SUSDE_SEED_YIELD, "sUSDe seed yield");

        // The facility configuration
        assertTrue(yieldRepo.isEnabled(), "facility enabled");
        assertEq(yieldRepo.epoch(), RESTART_EPOCH, "initial epoch");
        assertEq(yieldRepo.backingVault(), SUSDS, "backing vault");
        assertEq(yieldRepo.backingOracle(), address(backingOracle), "backing oracle");
        assertEq(yieldRepo.bondTeller(), BOND_TELLER, "bondTeller");
        assertEq(yieldRepo.bondAuctioneer(), BOND_AUCTIONEER, "auctioneer");
        assertEq(yieldRepo.configurator(), address(yieldRepoConfig), "configurator");
        assertEq(yieldRepoLens.facility(), address(yieldRepo), "lens facility");
        assertEq(yieldRepoConfig.facility(), address(yieldRepo), "config facility");
        assertEq(
            yieldRepoConfig.configOperator(),
            address(yieldRepoConfigTimelock),
            "config operator"
        );
        assertTrue(yieldRepoConfig.isEnabled(), "config enabled");
        assertTrue(yieldRepoConfigTimelock.isEnabled(), "config timelock enabled");
        assertEq(yieldRepo.initialDiscount(), INITIAL_DISCOUNT, "initial discount");
        assertEq(yieldRepo.maxPricePremium(), MAX_PRICE_PREMIUM, "max price premium");
        assertEq(backingOracle.backing(), BACKING, "backing value");

        address[] memory vaults = yieldRepo.getVaults();
        assertEq(vaults.length, 2, "vault count");
        assertEq(vaults[0], SUSDS, "vault 0");
        assertEq(vaults[1], SUSDE, "vault 1");

        IYieldRepurchaseFacilityV2.ReserveAsset memory susdsConfig = yieldRepo.getAssetConfig(
            SUSDS
        );
        assertEq(susdsConfig.shareToken, SUSDS, "sUSDS share token");
        assertEq(susdsConfig.reserve, USDS, "sUSDS reserve");
        assertEq(susdsConfig.reserveDecimals, RESERVE_DECIMALS, "sUSDS reserve decimals");
        assertEq(susdsConfig.sellShares, false, "sUSDS sellShares");
        assertEq(susdsConfig.asyncRedeem, false, "sUSDS asyncRedeem");
        assertEq(susdsConfig.yieldBuybackShare, SUSDS_BUYBACK_SHARE, "sUSDS share");
        assertEq(susdsConfig.nextYield, susdsSeedYield, "sUSDS nextYield");

        IYieldRepurchaseFacilityV2.ReserveAsset memory susdeConfig = yieldRepo.getAssetConfig(
            SUSDE
        );
        assertEq(susdeConfig.shareToken, SUSDE, "sUSDe share token");
        assertEq(susdeConfig.reserve, USDE, "sUSDe reserve");
        assertEq(susdeConfig.sellShares, true, "sUSDe sellShares");
        assertEq(susdeConfig.asyncRedeem, false, "sUSDe asyncRedeem");
        assertEq(susdeConfig.yieldBuybackShare, SUSDE_BUYBACK_SHARE, "sUSDe share");
        assertEq(susdeConfig.nextYield, susdeSeedYield, "sUSDe nextYield");

        // The yield recipient surface: the interfaces a sender checks, the route of each
        // vault, and the vault lookup by the underlying asset
        assertTrue(
            yieldRepo.supportsInterface(type(IYieldRepurchaseRecipient).interfaceId),
            "recipient interface"
        );
        assertTrue(yieldRepo.supportsInterface(type(IEnabler).interfaceId), "enabler interface");

        IYieldRepurchaseRecipient.VaultConfig memory susdsRoute = yieldRepo.getVaultConfig(SUSDS);
        assertEq(susdsRoute.vault, SUSDS, "sUSDS route vault");
        assertEq(susdsRoute.shareToken, SUSDS, "sUSDS route share token");
        assertEq(susdsRoute.asset, USDS, "sUSDS route asset");
        assertTrue(susdsRoute.enabled, "sUSDS route enabled");

        IYieldRepurchaseRecipient.VaultConfig memory susdeRoute = yieldRepo.getVaultConfig(SUSDE);
        assertEq(susdeRoute.vault, SUSDE, "sUSDe route vault");
        assertEq(susdeRoute.shareToken, SUSDE, "sUSDe route share token");
        assertEq(susdeRoute.asset, USDE, "sUSDe route asset");
        assertTrue(susdeRoute.enabled, "sUSDe route enabled");

        assertEq(yieldRepo.getAssetVault(USDS), SUSDS, "USDS vault");
        assertEq(yieldRepo.getAssetVault(USDE), SUSDE, "USDe vault");
        assertEq(yieldRepo.getAssetVault(SUSDS), address(0), "no vault for a share token");
        assertEq(yieldRepo.getAssetVault(OHM), address(0), "no vault for an unknown token");

        // The market authorization and the oracle price
        assertTrue(auctioneer.callbackAuthorized(address(yieldRepo)), "callback authorized");
        // The steered price path starts at the live CURRENT resolution of the fork block
        assertEq(ohmPriceUsd, ANCHOR_INITIAL_PRICE, "initial oracle price");
        assertEq(_expectedOraclePrice(), ANCHOR_INITIAL_PRICE, "initial gate price");

        // The clearinghouse configuration: both DAI-denominated clearinghouses (v1 and
        // v1.1) are included, the v1.1 inclusion carries the initial phantom-receivables
        // offset.
        assertTrue(
            yieldRepo.isClearinghouseIncluded(CLEARINGHOUSE_V1),
            "clearinghouse v1 included"
        );
        assertTrue(
            yieldRepo.isClearinghouseIncluded(CLEARINGHOUSE_V1_1),
            "clearinghouse v1.1 included"
        );
        assertEq(
            yieldRepo.clearinghouseOffset(CLEARINGHOUSE_V1_1),
            CLEARINGHOUSE_V1_1_INITIAL_OFFSET,
            "clearinghouse v1.1 offset"
        );
        assertEq(chreg.registryCount(), 3, "registry count");

        // The roles.
        assertTrue(roles.hasRole(yrfAdmin, "yrf_admin"), "yrf_admin role");
        assertTrue(roles.hasRole(backingAdmin, "backing_admin"), "backing_admin role");
    }

    // ============ TWO-WEEK END-TO-END ============ //

    // forge-lint: disable-next-item(cyclomatic-complexity)
    function test_e2e_twoWeeks() public {
        for (uint256 day; day < 14; ++day) {
            // The daily reward stream and the daily price move land before the daily beat
            _accrueSusdeRewards();
            _applyPriceDeltaBps(PRICE_DELTA_BPS[day]);

            // Day 8: the USDe feed goes stale for the daily beat. The PRICE module
            // rejects the stale USDe price, the facility skips the sUSDe daily cycle
            // through its self-call isolation, and the beat and the sUSDS market
            // proceed.
            if (day == STALE_USDE_FEED_DAY) {
                susdeReserveFeedStale = true;
                vm.recordLogs();
            }

            // The daily beat: on day 0 and day 7 it also performs the weekly reset
            bool isResetDay = day % YieldRepurchaseFacilityV2Constants.DAYS_PER_WEEK == 0;
            if (isResetDay) vm.recordLogs();
            _beat();
            if (isResetDay) _assertNoMismatchEvents();
            if (day == STALE_USDE_FEED_DAY) _assertSusdeCycleSkipped();

            if (day == 0) _assertWeekOneStart();
            if (day == YieldRepurchaseFacilityV2Constants.DAYS_PER_WEEK) _assertWeekTwoStart();

            // Bond purchases at the freshly created markets
            _buyBonds(SUSDS, BUY_SUSDS_BPS[day]);
            _buyBonds(SUSDE, BUY_SUSDE_BPS[day]);

            // Scenario events
            if (day == TRSRY_INFLOW_DAY) _trsryUsdsInflow(TRSRY_INFLOW_USDS);
            if (day == OFFSET_QUEUE_DAY) _queueOffsetIncrease();
            if (day == OFFSET_INCREASE_DAY) _executeOffsetIncreaseAndAssert();
            if (day == TRSRY_OUTFLOW_DAY) _trsrySusdsOutflow(TRSRY_OUTFLOW_SUSDS_SHARES);

            // The two intra-day beats: the facility only advances its epoch
            _beat();
            if (day == PRICE_DECAY_DAY) _assertMarketsInsidePriceBand();
            _beat();
            if (day == PRICE_DECAY_DAY) _assertMarketsAtPriceFloor();
        }

        // 42 beats total: the epoch counter sits at 20, one beat away from the third
        // weekly reset.
        assertEq(yieldRepo.epoch(), RESTART_EPOCH, "final epoch");
    }

    // ============ OHM PRICE OF THE BEAT ============ //

    /// @notice The parameters of a created market that the oracle price and the bid determine.
    struct MarketParameters {
        uint256 capacity;
        uint256 minPrice;
        uint256 maxPayout;
        uint256 scale;
        uint256 initialPrice;
    }

    /// @notice Reads the parameters of the live market the facility tracks for the vault.
    // Only the fields the oracle price and the bid determine are compared
    // forge-lint: disable-next-item(unused-return)
    function _trackedMarket(
        address vault_
    ) internal view returns (MarketParameters memory parameters) {
        (bool tracked, uint256 marketId, bool live) = yieldRepoLens.getVaultMarket(vault_);
        assertTrue(tracked, "market tracked");
        assertTrue(live, "market live");
        (
            ,
            ,
            ,
            ,
            ,
            parameters.capacity,
            ,
            parameters.minPrice,
            parameters.maxPayout,
            ,
            ,
            parameters.scale
        ) = auctioneer.markets(marketId);
        parameters.initialPrice = auctioneer.marketPrice(marketId);
    }

    function _assertSameMarket(
        MarketParameters memory actual_,
        MarketParameters memory expected_,
        string memory label_
    ) internal pure {
        assertEq(actual_.capacity, expected_.capacity, string.concat(label_, ": capacity"));
        assertEq(actual_.minPrice, expected_.minPrice, string.concat(label_, ": minPrice"));
        assertEq(actual_.maxPayout, expected_.maxPayout, string.concat(label_, ": maxPayout"));
        assertEq(actual_.scale, expected_.scale, string.concat(label_, ": scale"));
        assertEq(
            actual_.initialPrice,
            expected_.initialPrice,
            string.concat(label_, ": initial price")
        );
    }

    function test_execute_ohmObservationOfTheBlock_pricesTheMarketsAsTheCurrentPrice() public {
        // The first daily beat runs three times from the same state, as a direct `execute`
        // call in the fork block, where the feed mocks of the setup are fresh
        uint256 snapshotId = vm.snapshotState();

        // Without an OHM observation of the block the facility reads the current OHM price
        (uint256 observation, uint48 observedAt) = priceV2.getPrice(OHM, IPRICEv2.Variant.LAST);
        assertLt(observedAt, vm.getBlockTimestamp(), "current price: no observation of the block");
        uint256 susdsOraclePrice = priceV2.getPriceIn(OHM, USDS);
        uint256 susdeOraclePrice = priceV2.getPriceIn(OHM, USDE);
        uint256 susdeConversionRate = susde.previewRedeem(ONE_SHARE);
        vm.prank(HEART);
        yieldRepo.execute();
        MarketParameters memory susdsMarket = _trackedMarket(SUSDS);
        MarketParameters memory susdeMarket = _trackedMarket(SUSDE);

        // The markets are priced by the values `getPriceIn` reports in the block.
        // sUSDS pays out USDS: the oracle price is OHM in USDS (18 decimals).
        (uint256 initialPrice, uint256 minPrice, ) = _mirrorMarketPricing(susdsOraclePrice);
        assertEq(susdsMarket.initialPrice, initialPrice, "current price: sUSDS initial price");
        assertEq(susdsMarket.minPrice, minPrice, "current price: sUSDS minPrice");
        // sUSDe pays out shares: oraclePrice (18 decimals, USDe per OHM) * 1e18
        // / conversionRate (18 decimals, USDe per share) -> 18 decimals, shares per OHM (floor).
        (initialPrice, minPrice, ) = _mirrorMarketPricing(
            susdeOraclePrice.mulDiv(ONE_SHARE, susdeConversionRate)
        );
        assertEq(susdeMarket.initialPrice, initialPrice, "current price: sUSDe initial price");
        assertEq(susdeMarket.minPrice, minPrice, "current price: sUSDe minPrice");

        // With the OHM observation of the block, stored as the Heart stores it before its
        // tasks, the facility prices with the observation. It equals the current OHM price of
        // the block, so the markets are the same.
        assertTrue(vm.revertToState(snapshotId), "snapshot revert failed");
        vm.prank(HEART);
        price.updateMovingAverage();
        (observation, observedAt) = priceV2.getPrice(OHM, IPRICEv2.Variant.LAST);
        assertEq(observedAt, vm.getBlockTimestamp(), "observation: of the block");
        assertEq(observation, priceV2.getPrice(OHM), "observation: equals the current price");
        vm.prank(HEART);
        yieldRepo.execute();
        _assertSameMarket(_trackedMarket(SUSDS), susdsMarket, "observation: sUSDS");
        _assertSameMarket(_trackedMarket(SUSDE), susdeMarket, "observation: sUSDe");

        // The current OHM price moves after the observation of the block is stored: the
        // markets stay priced by the observation.
        // movedPrice = ohmPriceUsd * (10000 - 300) / 10000 (18 decimals, floor).
        assertTrue(vm.revertToState(snapshotId), "snapshot revert failed");
        vm.prank(HEART);
        price.updateMovingAverage();
        _applyPriceDeltaBps(-300);
        _updateOracles();
        assertEq(priceV2.getPrice(OHM), ohmPriceUsd, "moved price: current price");
        assertLt(ohmPriceUsd, observation, "moved price: below the observation");
        vm.prank(HEART);
        yieldRepo.execute();
        _assertSameMarket(_trackedMarket(SUSDS), susdsMarket, "moved price: sUSDS");
        _assertSameMarket(_trackedMarket(SUSDE), susdeMarket, "moved price: sUSDe");
        // The lens gate is evaluated at the current price.
        // gatePrice = ohmPriceUsd (18 decimals) * 1e18 / USDS price (1e18) = ohmPriceUsd.
        (bool gateOpen, uint256 gatePrice, uint256 gateBacking) = yieldRepoLens.priceGate();
        assertTrue(gateOpen, "moved price: lens gate open");
        assertEq(gatePrice, ohmPriceUsd, "moved price: lens gate price");
        assertEq(gateBacking, BACKING, "moved price: lens gate backing");
    }

    // ============ DAY-SPECIFIC ASSERTIONS ============ //

    /// @notice Day 0: the first weekly reset withdraws the seeded next yields into the
    ///         buyback pools, and the day-1 markets are sized to 1/7 of the funded pools.
    function _assertWeekOneStart() internal view {
        // The pools were empty before the first reset, so the funded value is the round
        // trip of the seed through the treasury withdrawal:
        // shares = previewWithdraw(seed) (round up), funded = previewRedeem(shares)
        // (round down), so funded >= seed within the share rounding.
        uint256 susdsFunded = IERC4626(SUSDS).previewRedeem(
            IERC4626(SUSDS).previewWithdraw(ANCHOR_SUSDS_SEED_YIELD)
        );
        uint256 susdeFundedShares = IERC4626(SUSDE).previewWithdraw(ANCHOR_SUSDE_SEED_YIELD);

        // The whole seed was funded: no unfunded carry on either vault
        assertEq(yieldRepo.getAssetConfig(SUSDS).unfundedYield, 0, "week 1: sUSDS carry");
        assertEq(yieldRepo.getAssetConfig(SUSDE).unfundedYield, 0, "week 1: sUSDe carry");

        // Day 1 markets: capacity = pool value / 7 (floor). The sUSDS market pays the raw
        // reserve; the sUSDe market pays vault shares priced at the share conversion rate.
        assertEq(
            market[SUSDS].capacity,
            susdsFunded / YieldRepurchaseFacilityV2Constants.DAYS_PER_WEEK,
            "week 1: sUSDS day-1 capacity"
        );
        assertEq(
            market[SUSDE].capacity,
            IERC4626(SUSDE).previewWithdraw(
                IERC4626(SUSDE).previewRedeem(susdeFundedShares) /
                    YieldRepurchaseFacilityV2Constants.DAYS_PER_WEEK
            ),
            "week 1: sUSDe day-1 capacity"
        );

        // The projection for week 2 was refreshed from the carried-over v1 snapshots and
        // the clearinghouse yield; both must be non-zero on the pinned block.
        assertGt(yieldRepo.getAssetConfig(SUSDS).nextYield, 0, "week 1: sUSDS projection");
        assertGt(yieldRepo.getAssetConfig(SUSDE).nextYield, 0, "week 1: sUSDe projection");
    }

    /// @notice Day 7: the second weekly reset. The stored next yields projected at the
    ///         first reset are withdrawn into the buyback pools exactly once, and the
    ///         fresh projections match the view mirror.
    function _assertWeekTwoStart() internal view {
        // The mirror model asserted the exact pool transition inside _beat; here the
        // view projection is cross-checked against the live formula mirror.
        assertEq(
            yieldRepoLens.getNextYield(SUSDS),
            _expectedProjectionView(SUSDS),
            "week 2: sUSDS projection view"
        );
        assertEq(
            yieldRepoLens.getNextYield(SUSDE),
            _expectedProjectionView(SUSDE),
            "week 2: sUSDe projection view"
        );

        // Week 2 has a funded buyback pool on both assets.
        assertGt(
            usds.balanceOf(address(yieldRepo)) +
                IERC4626(SUSDS).previewRedeem(susds.balanceOf(address(yieldRepo))),
            0,
            "week 2: sUSDS pool"
        );
        assertGt(
            usde.balanceOf(address(yieldRepo)) +
                IERC4626(SUSDE).previewRedeem(susde.balanceOf(address(yieldRepo))),
            0,
            "week 2: sUSDe pool"
        );
    }

    /// @notice Day 4: the direct facility path of the offset increase is closed for the
    ///         yrf_admin, which holds no configuration authority over the facility; the
    ///         yrf_admin queues the Clearinghouse v1.1 offset increase through the config
    ///         timelock instead, where it waits for the timelock delay.
    function _queueOffsetIncrease() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_OnlyConfigurator.selector,
                yrfAdmin
            )
        );
        vm.prank(yrfAdmin);
        yieldRepo.increaseClearinghouseOffset(
            CLEARINGHOUSE_V1_1,
            CLEARINGHOUSE_V1_1_OFFSET_INCREASE
        );

        vm.prank(yrfAdmin);
        offsetActionId = yieldRepoConfigTimelock.queueIncreaseClearinghouseOffset(
            CLEARINGHOUSE_V1_1,
            CLEARINGHOUSE_V1_1_OFFSET_INCREASE
        );

        // The queued increase is not applied until the action is executed
        assertEq(
            yieldRepo.clearinghouseOffset(CLEARINGHOUSE_V1_1),
            CLEARINGHOUSE_V1_1_INITIAL_OFFSET,
            "offset: unchanged while queued"
        );
    }

    /// @notice Day 5: the queued offset increase is executed (permissionlessly, by the
    ///         keeper) once the timelock delay has elapsed. The timelock dispatches it to
    ///         the config policy, the facility's configurator, and the increase lands in the
    ///         projection immediately, and therefore in the next weekly reset, reducing it
    ///         by the interest on the offset delta.
    function _executeOffsetIncreaseAndAssert() internal {
        uint256 projectionBefore = yieldRepoLens.getNextYield(SUSDS);

        vm.prank(keeper);
        yieldRepoConfigTimelock.executeQueuedAction(offsetActionId);

        assertEq(
            yieldRepo.clearinghouseOffset(CLEARINGHOUSE_V1_1),
            CLEARINGHOUSE_V1_1_INITIAL_OFFSET + CLEARINGHOUSE_V1_1_OFFSET_INCREASE,
            "offset: cumulative value"
        );

        // The projection drops by the difference of the floored per-clearinghouse
        // interest values, not by the floored interest on the offset delta itself (the
        // sequential floor divisions can shift the difference by a wei).
        // receivables = 4616766973610647568650468 (live at the pinned block).
        // before: ((receivables - 2_000_000e18) * 5) / 1000 / 52 = 251612209001023804677.
        // after:  ((receivables - 4_000_000e18) * 5) / 1000 / 52 = 59304516693331496985.
        // delta = 192307692307692307692, equal to (2_000_000e18 * 5) / 1000 / 52 at
        // these values.
        uint256 receivables = _readPrincipalReceivables(CLEARINGHOUSE_V1_1);
        uint256 interestBefore = ((receivables - CLEARINGHOUSE_V1_1_INITIAL_OFFSET) *
            YieldRepurchaseFacilityV2MathLib.CH_RATE_NUMERATOR) /
            YieldRepurchaseFacilityV2MathLib.CH_RATE_DENOMINATOR /
            YieldRepurchaseFacilityV2MathLib.WEEKS_PER_YEAR;
        uint256 interestAfter = ((receivables -
            CLEARINGHOUSE_V1_1_INITIAL_OFFSET -
            CLEARINGHOUSE_V1_1_OFFSET_INCREASE) *
            YieldRepurchaseFacilityV2MathLib.CH_RATE_NUMERATOR) /
            YieldRepurchaseFacilityV2MathLib.CH_RATE_DENOMINATOR /
            YieldRepurchaseFacilityV2MathLib.WEEKS_PER_YEAR;

        uint256 projectionAfter = yieldRepoLens.getNextYield(SUSDS);
        assertEq(projectionAfter, _expectedProjectionView(SUSDS), "offset: projection view");
        assertEq(
            projectionBefore - projectionAfter,
            interestBefore - interestAfter,
            "offset: projection delta"
        );
    }

    /// @notice Day 3, second intra-day beat (16 hours of decay, no purchases): the SDA
    ///         decay has driven both market prices down until they rest exactly on the
    ///         floor placed at `oraclePrice * (1 + MAX_PRICE_PREMIUM)`, the headline v2
    ///         fix over the floorless v1 markets.
    /// @dev    The SDA decays the debt linearly over a 72-hour interval, so an unclamped
    ///         price is `initialPrice * (1 - elapsed / 72 hours)`: 8/9 of the opening
    ///         price at the first intra-day beat and 7/9 at the second. The floor sits at
    ///         `1 / band` of the opening price, where the band is
    ///         `(1 + MAX_PRICE_PREMIUM) / (1 - INITIAL_DISCOUNT)` = 1.134, so the floor is
    ///         0.8818 of the opening price. Only the second beat clears it.
    function _assertMarketsAtPriceFloor() internal view {
        assertTrue(auctioneer.isLive(market[SUSDS].id), "floor: sUSDS market live");
        assertTrue(auctioneer.isLive(market[SUSDE].id), "floor: sUSDe market live");
        assertEq(
            auctioneer.marketPrice(market[SUSDS].id),
            market[SUSDS].minPrice,
            "floor: sUSDS price at floor"
        );
        assertEq(
            auctioneer.marketPrice(market[SUSDE].id),
            market[SUSDE].minPrice,
            "floor: sUSDe price at floor"
        );
    }

    /// @notice Day 3, first intra-day beat (8 hours of decay, no purchases): both market
    ///         prices have left the opening price but have not yet met the floor. The
    ///         premium is measured from the oracle price and does not compound with the
    ///         discount, so the decay band is
    ///         `(1 + MAX_PRICE_PREMIUM) / (1 - INITIAL_DISCOUNT)` wide and one beat of
    ///         decay does not cross it.
    function _assertMarketsInsidePriceBand() internal view {
        assertTrue(auctioneer.isLive(market[SUSDS].id), "band: sUSDS market live");
        assertTrue(auctioneer.isLive(market[SUSDE].id), "band: sUSDe market live");

        // 8/9 of the opening price against a floor at 0.8818 of it.
        assertGt(
            auctioneer.marketPrice(market[SUSDS].id),
            market[SUSDS].minPrice,
            "band: sUSDS price above floor"
        );
        assertLt(
            auctioneer.marketPrice(market[SUSDS].id),
            market[SUSDS].initialPrice,
            "band: sUSDS price below opening"
        );
        assertGt(
            auctioneer.marketPrice(market[SUSDE].id),
            market[SUSDE].minPrice,
            "band: sUSDe price above floor"
        );
        assertLt(
            auctioneer.marketPrice(market[SUSDE].id),
            market[SUSDE].initialPrice,
            "band: sUSDe price below opening"
        );
    }

    /// @notice Day 8 (stale USDe feed): the beat survived (asserted by the mirror model
    ///         inside `_beat`), the sUSDS market was created, the sUSDe daily cycle was
    ///         skipped with `DailyCycleSkipped`, and no sUSDe market exists. The feed
    ///         recovers for the following beats.
    function _assertSusdeCycleSkipped() internal {
        bytes32 skippedTopic = keccak256("DailyCycleSkipped(address,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(yieldRepo) &&
                logs[i].topics[0] == skippedTopic &&
                address(uint160(uint256(logs[i].topics[1]))) == SUSDE
            ) {
                found = true;
            }
        }
        assertTrue(found, "stale feed: sUSDe cycle skipped event");
        assertTrue(market[SUSDS].live, "stale feed: sUSDS market created");
        assertFalse(market[SUSDE].live, "stale feed: no sUSDe market");

        susdeReserveFeedStale = false;
    }

    /// @notice Asserts that the weekly reset emitted no ClearinghouseDebtTokenMismatch:
    ///         every registered clearinghouse is either included or matches the backing
    ///         reserve.
    function _assertNoMismatchEvents() internal {
        bytes32 mismatchTopic = keccak256("ClearinghouseDebtTokenMismatch(address)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != mismatchTopic, "unexpected mismatch event");
        }
    }

    // ============ VIEW MIRRORS ============ //

    /// @notice Mirrors `getNextYield` (the live projection view): the snapshot-based vault
    ///         yield plus the clearinghouse yield for the backing vault, scaled by the
    ///         buyback share.
    function _expectedProjectionView(address vault_) internal view returns (uint256) {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(vault_);

        uint256 currentRate = IERC4626(vault_).previewRedeem(ONE_SHARE);
        uint256 vaultYield;
        if (config.lastConversionRate != 0 && currentRate > config.lastConversionRate) {
            vaultYield = config.lastReserveBalance.mulDiv(
                currentRate - config.lastConversionRate,
                config.lastConversionRate
            );
        }

        uint256 clearinghouseYield = vault_ == SUSDS ? _modelClearinghouseYield() : 0;
        return
            (vaultYield + clearinghouseYield).mulDiv(
                config.yieldBuybackShare,
                YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT
            );
    }
}
// forge-lint: disable-end(calls-loop,reentrancy-no-eth)
