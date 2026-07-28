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
///         markets), simulated sUSDe rewards, treasury in/outflows, and a mid-week
///         clearinghouse offset increase. Every beat is asserted exactly against the
///         mirror model of the base contract.
contract YieldRepurchaseFacilityV2ForkTests_E2E is YieldRepurchaseFacilityV2ForkTestBase {
    using FullMath for uint256;

    // ============ PINNED-BLOCK ANCHORS ============ //

    // The following literals pin the seed derivation to the fork block, guarding the
    // runtime computation in the setup against silent regressions.

    /// @notice YRF v1.2 `nextYield` at the fork block.
    uint256 internal constant ANCHOR_V1_NEXT_YIELD = 5_982_089_731_452_058_944_082;
    /// @notice YRF v1.2 `lastReserveBalance` at the fork block.
    uint256 internal constant ANCHOR_V1_LAST_RESERVE_BALANCE = 7_806_531_153_059_147_483_913_598;
    /// @notice YRF v1.2 `lastConversionRate` at the fork block.
    uint256 internal constant ANCHOR_V1_LAST_CONVERSION_RATE = 1_102_142_411_298_698_298;

    // susdsSeedYield = v1.nextYield + v1 USDS balance + previewRedeem(v1 sUSDS balance)
    //                = 5982089731452058944082 + 1966844232402929448780
    //                  + 7079416863813230974217
    //                = 15028350827668219367079 (18 decimals, ~15028 USDS).
    uint256 internal constant ANCHOR_SUSDS_SEED_YIELD = 15_028_350_827_668_219_367_079;

    // susdeSeedBalance = susde.previewRedeem(susde.balanceOf(TRSRY))
    //                  = previewRedeem(24787014187233048960130950)
    //                  = 30701086260475240266353512 (~30.7M USDe).
    uint256 internal constant ANCHOR_SUSDE_SEED_BALANCE = 30_701_086_260_475_240_266_353_512;

    // susdeSeedYield = susdeSeedBalance * 400 / 10000 / 52 * 5e17 / 1e18
    //                = 30701086260475240266353512 * 400 / 10000 / 52 / 2
    //                = 11808110100182784717828 (~11808 USDe, floor at each step).
    uint256 internal constant ANCHOR_SUSDE_SEED_YIELD = 11_808_110_100_182_784_717_828;

    // The oracle price stored by the PRICE module at the fork block:
    // ohmEth (9.884202867418591e15) * 1e18 / daiEth (5.69962526353400e14)
    // = 17341846894141216413 (~$17.34 per OHM, 18 decimals).
    uint256 internal constant ANCHOR_INITIAL_PRICE = 17_341_846_894_141_216_413;

    // ============ SCENARIO TABLES (ONE ENTRY PER DAY) ============ //

    /// @notice Daily oracle price moves in signed basis points, applied to the OHM/ETH
    ///         feed before the daily beat. Mixed directions, bounded by ~2.2% per day, so
    ///         the price stays well above the backing for the whole test.
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
    ///         YRF timelock on day 5 and executed on day 6, one timelock delay later.
    uint256 internal constant DAI_V1_1_OFFSET_INCREASE = 2_000_000e18;

    /// @notice The queued offset increase, pending between day 5 and day 6.
    uint64 internal offsetActionId;

    // ============ SETUP VALIDATION ============ //

    function test_setup() public view {
        // The v1.2 state feeding the migration matches the pinned block.
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

        // The computed seeds match the anchors.
        assertEq(susdsSeedYield, ANCHOR_SUSDS_SEED_YIELD, "sUSDS seed yield");
        assertEq(susdsSeedBalance, ANCHOR_V1_LAST_RESERVE_BALANCE, "sUSDS seed balance");
        assertEq(susdsSeedRate, ANCHOR_V1_LAST_CONVERSION_RATE, "sUSDS seed rate");
        assertEq(susdeSeedBalance, ANCHOR_SUSDE_SEED_BALANCE, "sUSDe seed balance");
        assertEq(susdeSeedYield, ANCHOR_SUSDE_SEED_YIELD, "sUSDe seed yield");

        // The facility configuration.
        assertTrue(yieldRepo.isEnabled(), "facility enabled");
        assertEq(yieldRepo.epoch(), 20, "initial epoch");
        assertEq(yieldRepo.backingVault(), SUSDS, "backing vault");
        assertEq(yieldRepo.backingOracle(), address(backingOracle), "backing oracle");
        assertEq(yieldRepo.teller(), BOND_TELLER, "teller");
        assertEq(yieldRepo.bondAuctioneer(), BOND_AUCTIONEER, "auctioneer");
        assertEq(yieldRepo.timelock(), address(yrfTimelock), "timelock");
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

        // The market authorization and the oracle price.
        assertTrue(auctioneer.callbackAuthorized(address(yieldRepo)), "callback authorized");
        assertEq(price.getLastPrice(), ANCHOR_INITIAL_PRICE, "initial oracle price");

        // The clearinghouse configuration: both DAI clearinghouses are included, the
        // v1.1 inclusion carries the initial phantom-receivables offset.
        assertTrue(yieldRepo.isClearinghouseIncluded(CLEARINGHOUSE_DAI_V1), "DAI v1 included");
        assertTrue(yieldRepo.isClearinghouseIncluded(CLEARINGHOUSE_DAI_V1_1), "DAI v1.1 included");
        assertEq(
            yieldRepo.clearinghouseOffset(CLEARINGHOUSE_DAI_V1_1),
            DAI_V1_1_INITIAL_OFFSET,
            "DAI v1.1 offset"
        );
        assertEq(chreg.registryCount(), 3, "registry count");

        // The roles.
        assertTrue(roles.hasRole(yrfAdmin, "yrf_admin"), "yrf_admin role");
        assertTrue(roles.hasRole(backingAdmin, "backing_admin"), "backing_admin role");
    }

    // ============ TWO-WEEK END-TO-END ============ //

    function test_e2e_twoWeeks() public {
        for (uint256 day = 0; day < 14; ++day) {
            // The daily reward stream and the daily price move land before the daily beat.
            _accrueSusdeRewards();
            _applyPriceDeltaBps(PRICE_DELTA_BPS[day]);

            // The daily beat: on day 0 and day 7 it also performs the weekly reset.
            bool isResetDay = day % 7 == 0;
            if (isResetDay) vm.recordLogs();
            _beat();
            if (isResetDay) _assertNoMismatchEvents();

            if (day == 0) _assertWeekOneStart();
            if (day == 7) _assertWeekTwoStart();

            // Bond purchases at the freshly created markets.
            _buyBonds(SUSDS, BUY_SUSDS_BPS[day]);
            _buyBonds(SUSDE, BUY_SUSDE_BPS[day]);

            // Scenario events.
            if (day == 2) _trsryUsdsInflow(TRSRY_INFLOW_USDS);
            if (day == 4) _queueOffsetIncrease();
            if (day == 5) _executeOffsetIncreaseAndAssert();
            if (day == 9) _trsrySusdsOutflow(TRSRY_OUTFLOW_SUSDS_SHARES);

            // The two intra-day beats: the facility only advances its epoch.
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

    /// @notice Day 0: the first weekly reset funds both weekly budgets with the seeded
    ///         next yields, and the day-1 markets are sized to 1/7 of the budgets.
    function _assertWeekOneStart() internal view {
        // The pool value was zero before the first reset, so the budget equals the seed.
        assertEq(
            yieldRepo.getAssetConfig(SUSDS).weeklyBudgetRemaining,
            // The purchased-OHM processing has not run yet: nothing was purchased.
            ANCHOR_SUSDS_SEED_YIELD,
            "week 1: sUSDS budget"
        );
        assertEq(
            yieldRepo.getAssetConfig(SUSDE).weeklyBudgetRemaining,
            ANCHOR_SUSDE_SEED_YIELD,
            "week 1: sUSDe budget"
        );

        // Day 1 markets: capacity = budget / 7 (floor). The sUSDS market pays the raw
        // reserve; the sUSDe market pays vault shares priced at the share conversion rate.
        assertEq(
            market[SUSDS].capacity,
            ANCHOR_SUSDS_SEED_YIELD / 7,
            "week 1: sUSDS day-1 capacity"
        );
        assertEq(
            market[SUSDE].capacity,
            IERC4626(SUSDE).previewWithdraw(ANCHOR_SUSDE_SEED_YIELD / 7),
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

        // Week 2 has a live budget on both assets.
        assertGt(yieldRepo.getAssetConfig(SUSDS).weeklyBudgetRemaining, 0, "week 2: sUSDS budget");
        assertGt(yieldRepo.getAssetConfig(SUSDE).weeklyBudgetRemaining, 0, "week 2: sUSDe budget");
    }

    /// @notice Day 5: the yrf_admin queues the DAI v1.1 offset increase through the
    ///         YRF timelock; the direct facility path is closed for the yrf_admin.
    function _queueOffsetIncrease() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(yrfAdmin);
        yieldRepo.increaseClearinghouseOffset(CLEARINGHOUSE_DAI_V1_1, DAI_V1_1_OFFSET_INCREASE);

        vm.prank(yrfAdmin);
        offsetActionId = yrfTimelock.queueIncreaseClearinghouseOffset(
            CLEARINGHOUSE_DAI_V1_1,
            DAI_V1_1_OFFSET_INCREASE
        );
    }

    /// @notice Day 6: the queued offset increase executes (the day-5 queueing is exactly
    ///         one timelock delay in the past) and is applied to the projection
    ///         immediately, and therefore to the next weekly reset, reducing it by the
    ///         interest on the offset delta.
    function _executeOffsetIncreaseAndAssert() internal {
        uint256 projectionBefore = yieldRepo.getNextYield(SUSDS);

        yrfTimelock.executeQueuedAction(offsetActionId);

        assertEq(
            yieldRepo.clearinghouseOffset(CLEARINGHOUSE_DAI_V1_1),
            DAI_V1_1_INITIAL_OFFSET + DAI_V1_1_OFFSET_INCREASE,
            "offset: cumulative value"
        );

        // The projection drops by the difference of the floored per-clearinghouse
        // interest values, not by the floored interest on the offset delta itself.
        // receivables = 4694589579921195513858306 (live at the pinned block).
        // before: ((receivables - 2_000_000e18) * 5) / 1000 / 52 = 259095151915499568640.
        // after:  ((receivables - 4_000_000e18) * 5) / 1000 / 52 = 66787459607807260947.
        // delta = 192307692307692307693, one wei above (2_000_000e18 * 5) / 1000 / 52
        // due to the sequential floor divisions.
        uint256 receivables = _readPrincipalReceivables(CLEARINGHOUSE_DAI_V1_1);
        uint256 interestBefore = ((receivables - DAI_V1_1_INITIAL_OFFSET) * 5) / 1000 / 52;
        uint256 interestAfter = ((receivables -
            DAI_V1_1_INITIAL_OFFSET -
            DAI_V1_1_OFFSET_INCREASE) * 5) /
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
