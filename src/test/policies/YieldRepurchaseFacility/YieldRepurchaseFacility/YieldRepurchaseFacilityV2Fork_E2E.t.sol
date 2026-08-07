// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {YieldRepurchaseFacilityV2ForkTestBase} from "./YieldRepurchaseFacilityV2ForkTestBase.sol";

import {Vm} from "@forge-std-1.9.6/Vm.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

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

    /// @notice The additional receivables offset queued by the yrf_admin through the
    ///         config timelock on day 5 and executed on day 6, one timelock delay later.
    uint256 internal constant CLEARINGHOUSE_V1_1_OFFSET_INCREASE = 2_000_000e18;

    /// @notice The queued offset increase, pending between day 5 and day 6.
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
        assertEq(yieldRepo.epoch(), 20, "initial epoch");
        assertEq(yieldRepo.backingVault(), SUSDS, "backing vault");
        assertEq(yieldRepo.backingOracle(), address(backingOracle), "backing oracle");
        assertEq(yieldRepo.bondTeller(), BOND_TELLER, "bondTeller");
        assertEq(yieldRepo.bondAuctioneer(), BOND_AUCTIONEER, "auctioneer");
        assertEq(yieldRepo.timelock(), address(configTimelock), "timelock");
        assertEq(yieldRepo.initialDiscount(), INITIAL_DISCOUNT, "initial discount");
        assertEq(backingOracle.backing(), BACKING, "backing value");

        address[] memory vaults = yieldRepo.getVaults();
        assertEq(vaults.length, 2, "vault count");
        assertEq(vaults[0], SUSDS, "vault 0");
        assertEq(vaults[1], SUSDE, "vault 1");

        IYieldRepurchaseFacilityV2.ReserveAsset memory susdsConfig = yieldRepo.getAssetConfig(
            SUSDS
        );
        assertEq(susdsConfig.reserve, USDS, "sUSDS reserve");
        assertEq(susdsConfig.reserveDecimals, 18, "sUSDS reserve decimals");
        assertEq(susdsConfig.sellShares, false, "sUSDS sellShares");
        assertEq(susdsConfig.yieldBuybackShare, SUSDS_BUYBACK_SHARE, "sUSDS share");
        assertEq(susdsConfig.nextYield, susdsSeedYield, "sUSDS nextYield");

        IYieldRepurchaseFacilityV2.ReserveAsset memory susdeConfig = yieldRepo.getAssetConfig(
            SUSDE
        );
        assertEq(susdeConfig.reserve, USDE, "sUSDe reserve");
        assertEq(susdeConfig.sellShares, true, "sUSDe sellShares");
        assertEq(susdeConfig.yieldBuybackShare, SUSDE_BUYBACK_SHARE, "sUSDe share");
        assertEq(susdeConfig.nextYield, susdeSeedYield, "sUSDe nextYield");

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

    function test_e2e_twoWeeks() public {
        for (uint256 day = 0; day < 14; ++day) {
            // The daily reward stream and the daily price move land before the daily beat
            _accrueSusdeRewards();
            _applyPriceDeltaBps(PRICE_DELTA_BPS[day]);

            // Day 8: the USDe feed goes stale for the daily beat. The PRICE module
            // rejects the stale USDe price, the facility skips the sUSDe daily cycle
            // through its self-call isolation, and the beat and the sUSDS market
            // proceed.
            if (day == 8) {
                susdeReserveFeedStale = true;
                vm.recordLogs();
            }

            // The daily beat: on day 0 and day 7 it also performs the weekly reset
            bool isResetDay = day % 7 == 0;
            if (isResetDay) vm.recordLogs();
            _beat();
            if (isResetDay) _assertNoMismatchEvents();
            if (day == 8) _assertSusdeCycleSkipped();

            if (day == 0) _assertWeekOneStart();
            if (day == 7) _assertWeekTwoStart();

            // Bond purchases at the freshly created markets
            _buyBonds(SUSDS, BUY_SUSDS_BPS[day]);
            _buyBonds(SUSDE, BUY_SUSDE_BPS[day]);

            // Scenario events
            if (day == 2) _trsryUsdsInflow(TRSRY_INFLOW_USDS);
            if (day == 4) _queueOffsetIncrease();
            if (day == 5) _executeOffsetIncreaseAndAssert();
            if (day == 9) _trsrySusdsOutflow(TRSRY_OUTFLOW_SUSDS_SHARES);

            // The two intra-day beats: the facility only advances its epoch
            _beat();
            if (day == 2) _assertMarketsAtPriceFloor();
            _beat();
            if (day == 2) _assertMarketsAtPriceFloor();
        }

        // 42 beats total: the epoch counter sits at 20, one beat away from the third
        // weekly reset.
        assertEq(yieldRepo.epoch(), 20, "final epoch");
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
        assertEq(market[SUSDS].capacity, susdsFunded / 7, "week 1: sUSDS day-1 capacity");
        assertEq(
            market[SUSDE].capacity,
            IERC4626(SUSDE).previewWithdraw(IERC4626(SUSDE).previewRedeem(susdeFundedShares) / 7),
            "week 1: sUSDe day-1 capacity"
        );

        // The projection for week 2 was refreshed from the carried-over v1 snapshots and
        // the clearinghouse yield; both must be non-zero on the pinned block.
        assertGt(yieldRepo.getAssetConfig(SUSDS).nextYield, 0, "week 1: sUSDS projection");
        assertGt(yieldRepo.getAssetConfig(SUSDE).nextYield, 0, "week 1: sUSDe projection");
    }

    /// @notice Day 7: the second weekly reset. The stored next yields projected at the
    ///         first reset are injected into the week-2 budgets exactly once, and the
    ///         fresh projections match the view mirror.
    function _assertWeekTwoStart() internal view {
        // The mirror model asserted the exact budget transition inside _beat; here the
        // view projection is cross-checked against the live formula mirror.
        assertEq(
            yieldRepo.getNextYield(SUSDS),
            _expectedProjectionView(SUSDS),
            "week 2: sUSDS projection view"
        );
        assertEq(
            yieldRepo.getNextYield(SUSDE),
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

    /// @notice Day 5: the yrf_admin queues the Clearinghouse v1.1 offset increase through the
    ///         config timelock; the direct facility path is closed for the yrf_admin.
    function _queueOffsetIncrease() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(yrfAdmin);
        yieldRepo.increaseClearinghouseOffset(
            CLEARINGHOUSE_V1_1,
            CLEARINGHOUSE_V1_1_OFFSET_INCREASE
        );

        vm.prank(yrfAdmin);
        offsetActionId = configTimelock.queueIncreaseClearinghouseOffset(
            CLEARINGHOUSE_V1_1,
            CLEARINGHOUSE_V1_1_OFFSET_INCREASE
        );
    }

    /// @notice Day 6: the queued offset increase executes (the day-5 queueing is exactly
    ///         one timelock delay in the past) and is applied to the projection
    ///         immediately, and therefore to the next weekly reset, reducing it by the
    ///         interest on the offset delta.
    function _executeOffsetIncreaseAndAssert() internal {
        uint256 projectionBefore = yieldRepo.getNextYield(SUSDS);

        configTimelock.executeQueuedAction(offsetActionId);

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
        uint256 interestBefore = ((receivables - CLEARINGHOUSE_V1_1_INITIAL_OFFSET) * 5) /
            1000 /
            52;
        uint256 interestAfter = ((receivables -
            CLEARINGHOUSE_V1_1_INITIAL_OFFSET -
            CLEARINGHOUSE_V1_1_OFFSET_INCREASE) * 5) /
            1000 /
            52;

        uint256 projectionAfter = yieldRepo.getNextYield(SUSDS);
        assertEq(projectionAfter, _expectedProjectionView(SUSDS), "offset: projection view");
        assertEq(
            projectionBefore - projectionAfter,
            interestBefore - interestAfter,
            "offset: projection delta"
        );
    }

    /// @notice Day 3 (no purchases): with nobody buying, the SDA decay drives both market
    ///         prices down until they rest exactly on the undiscounted oracle floor, the
    ///         headline v2 fix over the floorless v1 markets.
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

    /// @notice Day 8 (stale USDe feed): the beat survived (asserted by the mirror model
    ///         inside `_beat`), the sUSDS market was created, the sUSDe daily cycle was
    ///         skipped with `DailyCycleSkipped`, and no sUSDe market exists. The feed
    ///         recovers for the following beats.
    function _assertSusdeCycleSkipped() internal {
        bytes32 skippedTopic = keccak256("DailyCycleSkipped(address,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
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
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != mismatchTopic, "unexpected mismatch event");
        }
    }

    // ============ VIEW MIRRORS ============ //

    /// @notice Mirrors `getNextYield` (the live projection view): the snapshot-based vault
    ///         yield plus the clearinghouse yield for the backing vault, scaled by the
    ///         buyback share.
    function _expectedProjectionView(address vault_) internal view returns (uint256) {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(vault_);

        uint256 currentRate = IERC4626(vault_).previewRedeem(1e18);
        uint256 vaultYield = 0;
        if (config.lastConversionRate != 0 && currentRate > config.lastConversionRate) {
            vaultYield = config.lastReserveBalance.mulDiv(
                currentRate - config.lastConversionRate,
                config.lastConversionRate
            );
        }

        uint256 clearinghouseYield = vault_ == SUSDS ? _modelClearinghouseYield() : 0;
        return (vaultYield + clearinghouseYield).mulDiv(config.yieldBuybackShare, 1e18);
    }
}
