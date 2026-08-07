// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {YieldRepurchaseFacilityV2ForkTestBase} from "./YieldRepurchaseFacilityV2ForkTestBase.sol";

import {FullMath} from "src/libraries/FullMath.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

/// @title YieldRepurchaseFacilityV2ForkTests_V1Parity
/// @notice Mainnet-fork parity test between the deployed YRF v1.2 and the YRF v2: the same
///         weekly cycle is executed twice from a shared state snapshot at a v1 week
///         boundary - once by the live v1.2 and once by the freshly installed v2 - under
///         identical external conditions (the same beat schedule, the same oracle price
///         path, and the same OHM purchase amounts), and the branches are compared
///         day-by-day against a journal kept in Solidity memory (memory survives the
///         state snapshot revert; contract storage does not).
/// @dev    Divergence sources are pinned:
///         - Both versions size the daily bid from their actual holdings, and both
///           pools start the week at the same value (the seed is the exact v1 day-1
///           total), but the branches split that value differently between raw USDS
///           (non-earning) and sUSDS shares (earning): v1 enters the week holding its
///           unsold residual as raw USDS (its last pre-boundary market redeemed the
///           whole pool), while v2 withdraws the entire seed as shares and redeems only
///           each day's bid. The pool divergence therefore accrues day by day as the
///           appreciation of the share-holdings gap, dampened by the payout feedback
///           (the slightly larger v2 market prices the replayed chunks slightly lower,
///           paying out slightly more); it is asserted daily as an exact accrual law
///           (within a derived 3-wei floor bound) plus a derived envelope. The v1 bid
///           is additionally reconstructed in the v2 branch from the journal (the
///           previews are evaluated at the same timestamps) and asserted exactly, which
///           proves that no unexplained divergence exists in the v1 branch.
///         - The projections differ only by the clearinghouse interest rounding shape:
///           v1 divides the receivables sum once, v2 floors the interest per
///           clearinghouse. Both are asserted exactly.
///         - The treasury share delta between the branches is a constant after the first
///           reset and is asserted daily.
contract YieldRepurchaseFacilityV2ForkTests_V1Parity is YieldRepurchaseFacilityV2ForkTestBase {
    using FullMath for uint256;

    // ============ SCENARIO TABLES ============ //

    /// @notice Daily oracle price moves (signed bps), applied identically in both
    ///         branches: entries 0-6 at the daily beats, entry 7 at the second weekly
    ///         reset beat.
    int256[8] internal PARITY_PRICE_DELTA_BPS = [int256(150), -220, 80, -130, 190, -90, 60, -180];

    /// @notice The payout fraction of the v1 market capacity targeted each day (bps).
    ///         Day 1 is a full buyout (the markets are identical); day 3 has no
    ///         participation (the price floor demonstration); day 5 is a near-full "top
    ///         up" buyout executed with fixed quote chunks in both branches.
    uint256[7] internal BUY_FRACTION_BPS = [uint256(10_000), 6000, 0, 3000, 9000, 4500, 7000];

    // ============ JOURNAL (MEMORY-ONLY) ============ //

    /// @notice One day of the v1 branch. `vm.revertToState` rolls back contract storage,
    ///         so the journal lives in memory for the whole test function.
    struct DayRecord {
        uint256 marketId;
        uint256 capacity;
        uint256 initialPrice;
        uint256 minPrice;
        uint256 scale;
        uint256 chunkCount;
        uint256[8] ohmChunks;
        uint256 payoutTotal;
        uint256 rawAfter;
        uint256 sharesAfter;
        uint256 trsryShares;
        uint256 priceMid1;
        uint256 priceMid2;
    }

    /// @notice The full v1-branch journal for the compared week.
    struct WeekJournal {
        uint256 resetTs;
        uint256 nyBefore;
        uint256 seedTotal;
        uint256 projection1;
        uint256 lcr1;
        uint256 lrb1;
        uint256 projection2;
        uint256 lrb2;
        uint256 trsryAfterReset2;
        DayRecord[7] day;
    }

    // ============ V2-BRANCH STATE (WRITTEN AFTER THE REVERT ONLY) ============ //

    /// @notice The v1 snapshots carried into `addAsset` (recorded for the projection
    ///         asserts).
    uint256 internal paritySeedLrb;
    uint256 internal paritySeedLcr;

    /// @notice The v1 residual swept to the treasury by the shutdown.
    uint256 internal sweptRaw;
    uint256 internal sweptShares;

    /// @notice The v2 `lastReserveBalance` after the first weekly reset.
    uint256 internal v2Lrb1;

    /// @notice The constant treasury share delta between the branches, fixed at the
    ///         first reset.
    int256 internal trsryDeltaK;

    /// @notice The divergence-law state carried between the v2 days (see
    ///         `_assertDivergenceLaw`): the pre-beat pool divergence, the post-purchase
    ///         share gap with its value at the store timestamp, and the payout
    ///         difference of the replayed day.
    int256 internal prevPoolDelta;
    uint256 internal prevGapShares;
    uint256 internal prevGapValue;
    int256 internal prevPayoutDiff;

    /// @notice The v2 pool value and the sUSDS rate at the first reset, anchoring the
    ///         divergence envelope.
    uint256 internal seedPoolValue;
    uint256 internal seedDayRate;

    // ============ SETUP ============ //

    /// @dev The v2 stack is deployed, activated, authorized, and enabled before the
    ///      state snapshot, so both branches share an identical pre-boundary history;
    ///      until it is registered in the Heart pipeline and seeded with an asset it is
    ///      inert. The asset registration and the pipeline swap happen after the revert,
    ///      in the v2 branch only. Both DAI clearinghouses are included without offsets:
    ///      v1 counts the receivables of the whole registry, so the projection parity
    ///      requires v2 to count the same set.
    function setUp() public override {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        _setupActors();
        _loadMainnetContracts();
        _deployV2Stack();
        _installV2Stack();
        _initializeOracleState();

        vm.startPrank(TIMELOCK);
        yieldRepo.includeClearinghouse(CLEARINGHOUSE_DAI_V1);
        yieldRepo.includeClearinghouse(CLEARINGHOUSE_DAI_V1_1);
        vm.stopPrank();
    }

    // ============ TEST ============ //

    // test cases
    // [X] phase A: beats to the v1 week boundary (no purchases, no OHM held by v1)
    // [X] v1 branch: the boundary reset, 7 days with full/partial/zero buyouts, reset 2
    // [X] v2 branch (same snapshot): shutdown v1, swap the Heart slot, seed v2 with the
    //     exact v1 day-1 total, replay the week with the same OHM amounts
    // [X] day 1: the v1 capacity equals the seed total over 7 exactly, the v2 pool is
    //     the seed round trip (bounded to 1 wei), and the payouts match
    // [X] days 2..7: the v1 bid is reconstructed exactly from the journal; the v2 bid
    //     follows the balance-based pool exactly; the pool divergence follows the
    //     derived accrual law (share-gap appreciation minus the payout feedback) and
    //     stays within the derived envelope
    // [X] the treasury share delta between the branches is constant after the reset
    // [X] day 3 (no buys): v1 decays below the v2 floor, v2 rests exactly on the floor
    // [X] both weekly projections match their formulas exactly; the difference is the
    //     clearinghouse rounding shape

    function test_v1ParityWeek() public {
        WeekJournal memory journal;

        _runPhaseA();

        uint256 snapshotId = vm.snapshotState();

        _runV1Week(journal);

        assertTrue(vm.revertToState(snapshotId), "snapshot revert failed");
        _updateOracles();

        _installV2Branch(journal);
        _runV2Week(journal);
    }

    // ============ PHASE A ============ //

    /// @notice Beats from the pinned block (v1 epoch 9) to the week boundary (epoch 20)
    ///         without purchases: v1 holds no OHM at the boundary and its unsold
    ///         inventory is the organic residual that enters the day-1 total.
    function _runPhaseA() internal {
        assertEq(yieldRepoV1.epoch(), 9, "phase A: pinned epoch");
        while (yieldRepoV1.epoch() != 20) {
            _beatIntraDay();
        }
        assertEq(ohm.balanceOf(YIELD_REPO_V1), 0, "phase A: no OHM at the boundary");
    }

    // ============ V1 BRANCH ============ //

    function _runV1Week(WeekJournal memory journal_) internal {
        for (uint256 day = 0; day < 7; ++day) {
            _warpToNextBeat();
            _applyPriceDeltaBps(PARITY_PRICE_DELTA_BPS[day]);
            _updateOracles();

            if (day == 0) _recordBoundary(journal_);

            vm.prank(keeper);
            heart.beat();

            if (day == 0) {
                journal_.projection1 = yieldRepoV1.nextYield();
                journal_.lcr1 = yieldRepoV1.lastConversionRate();
                journal_.lrb1 = yieldRepoV1.lastReserveBalance();
            }

            _recordDayAndBuyV1(journal_.day[day], day);
        }

        // The second weekly reset
        _warpToNextBeat();
        _applyPriceDeltaBps(PARITY_PRICE_DELTA_BPS[7]);
        _updateOracles();
        vm.prank(keeper);
        heart.beat();

        journal_.projection2 = yieldRepoV1.nextYield();
        journal_.lrb2 = yieldRepoV1.lastReserveBalance();
        journal_.trsryAfterReset2 = susds.balanceOf(address(treasury));
    }

    /// @notice Records the boundary state right before the reset beat. The seed is the
    ///         exact v1 day-1 total: the residual holdings plus the round-tripped value
    ///         of the `nextYield` withdrawal, all previewed at the reset timestamp, so
    ///         that the v2 branch produces an identical day-1 bid.
    function _recordBoundary(WeekJournal memory journal_) internal view {
        journal_.resetTs = vm.getBlockTimestamp();
        journal_.nyBefore = yieldRepoV1.nextYield();
        journal_.seedTotal =
            usds.balanceOf(YIELD_REPO_V1) +
            susds.previewRedeem(
                susds.balanceOf(YIELD_REPO_V1) + susds.previewWithdraw(journal_.nyBefore)
            );
    }

    function _recordDayAndBuyV1(DayRecord memory rec_, uint256 day_) internal {
        rec_.marketId = aggregator.marketCounter() - 1;
        (rec_.capacity, rec_.minPrice, rec_.scale) = _marketSummary(rec_.marketId);
        rec_.initialPrice = auctioneer.marketPrice(rec_.marketId);
        rec_.trsryShares = susds.balanceOf(address(treasury));
        assertEq(rec_.minPrice, 0, "v1 market: floorless");
        assertEq(ohm.balanceOf(YIELD_REPO_V1), 0, "v1: prior OHM burned");

        _buyChunks(rec_, rec_.marketId, BUY_FRACTION_BPS[day_], true);

        // Guard against a vacuous pass: the scheduled purchases must have executed, and
        // the full-buyout day must have drained (almost) the whole capacity.
        if (BUY_FRACTION_BPS[day_] != 0) {
            assertGt(rec_.chunkCount, 0, "v1 purchase: no chunks");
            // payoutTotal >= capacity * fraction * 97% (the chunk loop may stop a hair
            // short of the target because of the payout floor rounding).
            assertGe(
                rec_.payoutTotal,
                (((rec_.capacity * BUY_FRACTION_BPS[day_]) / 10_000) * 97) / 100,
                "v1 purchase: target fraction not reached"
            );
        }

        rec_.rawAfter = usds.balanceOf(YIELD_REPO_V1);
        rec_.sharesAfter = susds.balanceOf(YIELD_REPO_V1);

        _beatIntraDay();
        if (day_ == 2) rec_.priceMid1 = auctioneer.marketPrice(rec_.marketId);
        _beatIntraDay();
        if (day_ == 2) rec_.priceMid2 = auctioneer.marketPrice(rec_.marketId);
    }

    // ============ V2 BRANCH ============ //

    /// @notice Shuts the v1.2 down (sweeping its residual to the treasury), swaps the
    ///         Heart slot, and registers sUSDS on the v2 with the carried-over v1
    ///         snapshots and the exact day-1 total as the next-yield seed.
    function _installV2Branch(WeekJournal memory journal_) internal {
        sweptRaw = usds.balanceOf(YIELD_REPO_V1);
        sweptShares = susds.balanceOf(YIELD_REPO_V1);
        paritySeedLrb = yieldRepoV1.lastReserveBalance();
        paritySeedLcr = yieldRepoV1.lastConversionRate();

        address[] memory tokensToTransfer = new address[](2);
        tokensToTransfer[0] = USDS;
        tokensToTransfer[1] = SUSDS;
        vm.prank(DAO_MS);
        yieldRepoV1.shutdown(tokensToTransfer);

        vm.startPrank(TIMELOCK);
        heart.removePeriodicTaskAtIndex(4);
        heart.addPeriodicTaskAtIndex(address(yieldRepo), bytes4(0), 4);
        yieldRepo.addAsset(
            SUSDS,
            1e18, // yieldBuybackShare: 100%, matching v1
            paritySeedLrb,
            paritySeedLcr,
            journal_.seedTotal,
            false, // sellShares
            true // setAsBackingVault
        );
        vm.stopPrank();
    }

    function _runV2Week(WeekJournal memory journal_) internal {
        for (uint256 day = 0; day < 7; ++day) {
            _warpToNextBeat();
            _applyPriceDeltaBps(PARITY_PRICE_DELTA_BPS[day]);
            _updateOracles();

            // The bid inputs of both branches, fixed before the beat: the expected pool
            // values at the beat timestamp, after the pending withdrawals of the beat
            // itself.
            uint256 expectedPool;
            uint256 v1Pool;
            if (day == 0) {
                // The first reset withdraws the seed into an empty pool; the funded
                // value is the round trip of the seed through the share withdrawal. The
                // v1 pool at the same timestamp is the seed total by construction.
                expectedPool = susds.previewRedeem(susds.previewWithdraw(journal_.seedTotal));
                v1Pool = journal_.seedTotal;
                seedPoolValue = expectedPool;
                seedDayRate = susds.previewRedeem(1e18);
                _assertResetOneInputs(journal_);
            } else {
                // The pending beat first adds the backing shares withdrawn for the OHM
                // bought the day before, so they are valued together with the held
                // shares (a single floor).
                expectedPool =
                    usds.balanceOf(address(yieldRepo)) +
                    susds.previewRedeem(
                        susds.balanceOf(address(yieldRepo)) +
                            _expectedBackingShares(journal_.day[day - 1])
                    );
                v1Pool = _assertV1BidReconstruction(journal_, day);
                _assertDivergenceLaw(expectedPool, v1Pool, day);
            }

            vm.prank(keeper);
            heart.beat();

            _assertV2Day(journal_, day, expectedPool, v1Pool);
        }

        // The second weekly reset
        _warpToNextBeat();
        _applyPriceDeltaBps(PARITY_PRICE_DELTA_BPS[7]);
        _updateOracles();
        vm.prank(keeper);
        heart.beat();

        _assertResetTwo(journal_);
    }

    /// @notice Day 1 pre-beat: pins the treasury delta formula inputs. The expected
    ///         constant share delta between the branches is: the swept shares, plus the
    ///         wrap of the swept raw USDS, minus the prefund excess over the v1
    ///         withdrawal (the seed contains the residual, so v2 withdraws more).
    function _assertResetOneInputs(WeekJournal memory journal_) internal {
        assertEq(vm.getBlockTimestamp(), journal_.resetTs, "reset 1: timestamp");

        // expectedK = sweptShares + previewDeposit(sweptRaw)
        //           - (previewWithdraw(seedTotal) - previewWithdraw(nyBefore)).
        // The wrap composition with the same-beat deposit-facility sweep can shift the
        // wrapped shares by a wei, so the delta is pinned within 2 wei here and asserted
        // strictly constant afterwards.
        int256 expectedK = int256(sweptShares + susds.previewDeposit(sweptRaw)) -
            int256(
                susds.previewWithdraw(journal_.seedTotal) - susds.previewWithdraw(journal_.nyBefore)
            );
        trsryDeltaK = expectedK;
    }

    /// @notice Days 2..7 pre-beat: reconstructs the v1 daily bid exactly from the journal
    ///         and the previews of the current (identical) timestamp: the day-(d-1)
    ///         post-purchase holdings, plus the backing withdrawn for the OHM bought the
    ///         day before, re-marked at the current conversion rate. The journal capacity
    ///         must match it to the wei, proving that no unexplained divergence exists in
    ///         the v1 branch.
    /// @return v1Pool The reconstructed v1 pool value at the current beat timestamp.
    function _assertV1BidReconstruction(
        WeekJournal memory journal_,
        uint256 day_
    ) internal view returns (uint256 v1Pool) {
        DayRecord memory prev = journal_.day[day_ - 1];

        // backingShares = previewWithdraw(burned (9 dec) * 11.33e18 / 1e9)
        uint256 backingShares = susds.previewWithdraw(_chunkSum(prev).mulDiv(BACKING, 1e9));
        v1Pool = prev.rawAfter + susds.previewRedeem(prev.sharesAfter + backingShares);

        assertEq(journal_.day[day_].capacity, v1Pool / (7 - day_), "reconstruction: v1 daily bid");
    }

    /// @notice Days 2..7 pre-beat: asserts that the pool divergence between the branches
    ///         follows its derived accrual law and stays within the derived envelope.
    ///         Both pools start the week at the same value (the seed is the exact v1
    ///         day-1 total), but the branches split it differently between raw USDS
    ///         (non-earning) and sUSDS shares (earning): v1 entered the week holding its
    ///         unsold residual as raw USDS (its last pre-boundary market redeemed the
    ///         whole pool), while v2 withdrew the entire seed as shares and redeems only
    ///         each day's bid, so v2 keeps more of the pool earning.
    /// @dev    The accrual law (all values in USDS wei; PR_t(x) = previewRedeem of x
    ///         shares at the beat timestamp t): pool_i = raw_i + PR_t(S_i + sb), where
    ///         the backing shares sb and the replayed OHM chunks are identical between
    ///         the branches. Between the beats each branch redeems u_i shares for
    ///         exactly PR_t(u_i) raw (value-neutral up to one floor wei) and pays out
    ///         p_i raw to the purchases, so with G = S2 - S1 (the post-purchase share
    ///         gap) the sb terms cancel and
    ///           delta(t+1) = delta(t) + [PR_{t+1}(G) - PR_t(G)] - (p2 - p1) + e,
    ///         where e collects one floor split from each branch's redeem, one from
    ///         valuing the gap as a single quantity per timestamp, and one from the sb
    ///         re-split: |e| <= 3.
    function _assertDivergenceLaw(uint256 poolV2_, uint256 poolV1_, uint256 day_) internal view {
        string memory label = string.concat("day ", vm.toString(day_ + 1));
        int256 poolDelta = int256(poolV2_) - int256(poolV1_);

        int256 gapAccrual = int256(susds.previewRedeem(prevGapShares)) - int256(prevGapValue);
        assertApproxEqAbs(
            poolDelta,
            prevPoolDelta + gapAccrual - prevPayoutDiff,
            3,
            string.concat(label, ": pool divergence accrual law")
        );

        // The divergence starts at the seed round trip (at most 1 wei), every accrual
        // is non-negative (the sUSDS rate is non-decreasing and the share gap sign is
        // asserted at every store), and the payout feedback only dampens (its sign is
        // asserted at every store), so the divergence never drops below zero.
        assertGe(poolDelta, 0, string.concat(label, ": v2 pool not below v1"));

        // The pool only shrinks through the compared week (the replayed payouts exceed
        // the appreciation), which bounds the share gap by the seed pool value below.
        assertLe(poolV2_, seedPoolValue, string.concat(label, ": pool within the seed value"));

        // The envelope: the accrual per transition is at most the whole pool value
        // times the relative rate increment (gapValue <= poolV2 <= seedPool, asserted
        // above), and the rate increments telescope, so
        //   delta(d) <= seedPool * (rate_d - rate_1) / rate_1 + slack,
        // slack = 1 wei of the seed round trip + 3 floor wei per transition * 6 = 19,
        // rounded to 20. On the pinned fork the weekly rate growth is ~0.06%, so the
        // envelope stays below 9e18 while the observed divergence peaks below 2e18.
        uint256 rateNow = susds.previewRedeem(1e18);
        assertLe(
            uint256(poolDelta),
            seedPoolValue.mulDiv(rateNow - seedDayRate, seedDayRate) + 20,
            string.concat(label, ": pool divergence envelope")
        );
    }

    /// @notice The backing vault shares the purchased-OHM processing withdraws at the
    ///         pending beat for the OHM bought the day before (same formula, same
    ///         timestamp).
    function _expectedBackingShares(DayRecord memory prev_) internal view returns (uint256) {
        uint256 burned = _chunkSum(prev_);
        if (burned == 0) return 0;
        return susds.previewWithdraw(burned.mulDiv(BACKING, 1e9));
    }

    function _assertV2Day(
        WeekJournal memory journal_,
        uint256 day_,
        uint256 expectedPool_,
        uint256 v1Pool_
    ) internal {
        DayRecord memory rec = journal_.day[day_];
        string memory label = string.concat("day ", vm.toString(day_ + 1));

        assertEq(yieldRepo.epoch(), uint48(day_ * 3), string.concat(label, ": epoch"));
        assertEq(yieldRepo.ohmPurchased(), 0, string.concat(label, ": OHM burned"));

        uint256 marketId = aggregator.marketCounter() - 1;
        (uint256 capacity, uint256 minPrice, uint256 scale) = _marketSummary(marketId);

        // The v2 bid follows the balance-based pool exactly. The v1 capacity is
        // reconstructed exactly as well (day 1 from the seed below, days 2..7 in
        // _assertV1BidReconstruction), so the cross-branch capacity delta is exactly
        // the floor difference of the two pools; the pool divergence itself is pinned
        // by the accrual law and the envelope asserted in _assertDivergenceLaw.
        assertEq(capacity, expectedPool_ / (7 - day_), string.concat(label, ": v2 capacity"));
        assertEq(scale, rec.scale, string.concat(label, ": scale"));
        assertGt(minPrice, 0, string.concat(label, ": v2 floor"));

        if (day_ == 0) {
            // The v1 day-1 capacity is the seed total over 7: the seed was recorded as
            // the exact v1 pool at the reset timestamp (the raw residual plus the
            // previewRedeem of the held and to-be-withdrawn shares), so the journaled
            // capacity must reproduce it to the wei.
            assertEq(rec.capacity, journal_.seedTotal / 7, "day 1: v1 capacity from the seed");
            // The v2 day-1 pool is the seed round trip through the treasury
            // withdrawal: shares = previewWithdraw(seed) rounds up and
            // previewRedeem(shares) floors, so the pool is in [seed, seed + 1] wei
            // while one sUSDS share is worth less than 2 USDS (the rate is ~1.103e18).
            // The two capacity floors above therefore differ by at most 1 wei.
            assertGe(expectedPool_, journal_.seedTotal, "day 1: round trip lower bound");
            assertLe(expectedPool_ - journal_.seedTotal, 1, "day 1: round trip upper bound");
            assertEq(auctioneer.marketPrice(marketId), rec.initialPrice, "day 1: initial price");
            _assertResetOneOutputs(journal_);
        } else {
            // The initial price depends only on the (identical) oracle price; the
            // capacity-dependent control variable rounding can move it by a wei.
            assertApproxEqAbs(
                auctioneer.marketPrice(marketId),
                rec.initialPrice,
                1,
                string.concat(label, ": initial price")
            );
        }

        // The treasury share delta against the v1 branch is constant after the reset
        int256 actualDelta = int256(susds.balanceOf(address(treasury))) - int256(rec.trsryShares);
        if (day_ == 0) {
            assertApproxEqAbs(
                uint256(actualDelta),
                uint256(trsryDeltaK),
                2,
                "day 1: treasury delta formula"
            );
            trsryDeltaK = actualDelta;
        } else {
            assertEq(actualDelta, trsryDeltaK, string.concat(label, ": treasury delta"));
        }

        // Replay the same OHM amounts
        uint256 payoutV2 = _replayChunks(rec, marketId);
        if (day_ == 0) {
            // With equal capacities the two day-1 markets are bit-identical (the equal
            // capacity, initial price, scale, and schedule fix the whole SDA state), so
            // the replayed chunks return exactly equal payouts. A 1-wei pool excess
            // (see the round trip bound above) can shift the capacity floor by one wei,
            // which moves the formatted price by at most one unit and each floored
            // chunk payout by at most one wei (the formatted price exceeds the payout
            // in magnitude).
            assertApproxEqAbs(
                payoutV2,
                rec.payoutTotal,
                capacity == rec.capacity ? 0 : rec.chunkCount,
                "day 1: payout parity"
            );
        }
        assertEq(
            yieldRepo.ohmPurchased(),
            _chunkSum(rec),
            string.concat(label, ": purchased OHM accounted")
        );
        _assertV2Holdings(label);

        // Store the divergence-law inputs for the next day's pre-beat assert: the
        // pre-beat pool divergence of this day, the post-purchase share gap with its
        // value at this beat, and the payout difference of the replayed chunks.
        uint256 v2Shares = susds.balanceOf(address(yieldRepo));
        // v2 keeps the divergence excess on the earning (share) side: both branches'
        // raw inventories track the same daily bid, so the v1 share holdings never
        // exceed the v2 holdings.
        assertGe(v2Shares, rec.sharesAfter, string.concat(label, ": share gap sign"));
        // The payout feedback is non-negative: the v2 market capacity is never below
        // the v1 capacity (the pool divergence is non-negative), and the larger market
        // prices the same replayed quote chunks at or below the v1 price, so the v2
        // payout is at or above the v1 payout.
        assertGe(payoutV2, rec.payoutTotal, string.concat(label, ": payout feedback sign"));
        prevPoolDelta = int256(expectedPool_) - int256(v1Pool_);
        prevGapShares = v2Shares - rec.sharesAfter;
        prevGapValue = susds.previewRedeem(prevGapShares);
        prevPayoutDiff = int256(payoutV2) - int256(rec.payoutTotal);

        _beatIntraDay();
        if (day_ == 2) _assertPriceFloorParity(rec, marketId, rec.priceMid1);
        _beatIntraDay();
        if (day_ == 2) _assertPriceFloorParity(rec, marketId, rec.priceMid2);
    }

    /// @notice Day 1 post-beat: the reset outputs. The conversion-rate snapshot is
    ///         identical; the balance snapshot and the projection relate to the v1 values
    ///         by exact formulas.
    function _assertResetOneOutputs(WeekJournal memory journal_) internal {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(SUSDS);

        // The conversion-rate snapshots are taken at the same timestamp
        assertEq(config.lastConversionRate, journal_.lcr1, "reset 1: conversion rate");

        // Both balance snapshots equal the post-beat treasury balance previews (no OHM
        // was processed at this reset, so nothing was withdrawn after the snapshots).
        assertEq(
            config.lastReserveBalance,
            susds.previewRedeem(susds.balanceOf(address(treasury))),
            "reset 1: v2 balance snapshot"
        );
        assertEq(
            journal_.lrb1,
            susds.previewRedeem(journal_.day[0].trsryShares),
            "reset 1: v1 balance snapshot"
        );
        v2Lrb1 = config.lastReserveBalance;

        // The projections share the vault term (identical snapshots; the v1 formula
        // (lrb * rate) / lastRate - lrb equals the v2 mulDiv form exactly) and differ
        // only in the clearinghouse rounding shape: v1 divides the receivables sum once,
        // v2 floors the interest per clearinghouse.
        uint256 vaultYield = paritySeedLrb.mulDiv(journal_.lcr1 - paritySeedLcr, paritySeedLcr);
        uint256 chSumInterest = _sumThenDivideInterest();
        uint256 chPerHouseInterest = _perHouseInterest();
        assertEq(journal_.projection1, vaultYield + chSumInterest, "reset 1: v1 projection");
        assertEq(config.nextYield, vaultYield + chPerHouseInterest, "reset 1: v2 projection");
        assertEq(
            journal_.projection1 - config.nextYield,
            chSumInterest - chPerHouseInterest,
            "reset 1: projection delta is the rounding shape"
        );
    }

    /// @notice Day 3 intra-day: the v2 market rests exactly on its floor while the
    ///         journaled v1 price has decayed below that floor - the v1.2 defect the
    ///         floor fixes, demonstrated on the fork.
    function _assertPriceFloorParity(
        DayRecord memory rec_,
        uint256 marketIdV2_,
        uint256 v1Price_
    ) internal view {
        (, uint256 minPriceV2, uint256 scaleV2) = _marketSummary(marketIdV2_);
        assertEq(scaleV2, rec_.scale, "floor: same scale");
        assertEq(auctioneer.marketPrice(marketIdV2_), minPriceV2, "floor: v2 at floor");
        assertLt(v1Price_, minPriceV2, "floor: v1 decayed below the v2 floor");
    }

    function _assertResetTwo(WeekJournal memory journal_) internal view {
        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(SUSDS);

        // Both balance snapshots were taken before the same-beat backing withdrawal for
        // the OHM bought on day 7, so the withdrawn shares are added back.
        uint256 backingShares = susds.previewWithdraw(
            _chunkSum(journal_.day[6]).mulDiv(BACKING, 1e9)
        );
        assertEq(
            journal_.lrb2,
            susds.previewRedeem(journal_.trsryAfterReset2 + backingShares),
            "reset 2: v1 balance snapshot"
        );
        assertEq(
            config.lastReserveBalance,
            susds.previewRedeem(susds.balanceOf(address(treasury)) + backingShares),
            "reset 2: v2 balance snapshot"
        );

        // The projections: the vault terms differ only through the balance snapshots
        // (the v2 snapshot includes the treasury share delta), the clearinghouse terms
        // only through the rounding shape.
        uint256 rate = susds.previewRedeem(1e18);
        assertEq(
            journal_.projection2,
            journal_.lrb1.mulDiv(rate - journal_.lcr1, journal_.lcr1) + _sumThenDivideInterest(),
            "reset 2: v1 projection"
        );
        assertEq(
            config.nextYield,
            v2Lrb1.mulDiv(rate - journal_.lcr1, journal_.lcr1) + _perHouseInterest(),
            "reset 2: v2 projection"
        );
    }

    function _assertV2Holdings(string memory label_) internal view {
        // The burn invariant: the OHM balance always covers the purchased accumulator
        // (nothing is donated in this test, so the balances are equal).
        assertEq(
            ohm.balanceOf(address(yieldRepo)),
            yieldRepo.ohmPurchased(),
            string.concat(label_, ": facility OHM")
        );
        // No unfunded carry accrues: the treasury covers every weekly withdrawal.
        assertEq(
            yieldRepo.getAssetConfig(SUSDS).unfundedYield,
            0,
            string.concat(label_, ": unfunded carry")
        );
    }

    // ============ PURCHASES ============ //

    /// @notice Buys the target payout fraction in fixed quote chunks. In the recording
    ///         mode the chunk amounts are derived from the live market and journaled; in
    ///         the replay mode they are executed verbatim.
    function _buyChunks(
        DayRecord memory rec_,
        uint256 marketId_,
        uint256 fractionBps_,
        bool record_
    ) internal returns (uint256 totalPayout) {
        if (record_) {
            if (fractionBps_ == 0) return 0;
            uint256 targetPayout = (rec_.capacity * fractionBps_) / 10_000;
            for (uint256 i = 0; i < 8 && totalPayout < targetPayout; ++i) {
                uint256 quote = _chunkQuote(marketId_, targetPayout - totalPayout);
                if (quote == 0) break;
                rec_.ohmChunks[i] = quote;
                rec_.chunkCount = i + 1;
                totalPayout += _purchase(marketId_, quote);
            }
            rec_.payoutTotal = totalPayout;
        } else {
            for (uint256 i = 0; i < rec_.chunkCount; ++i) {
                totalPayout += _purchase(marketId_, rec_.ohmChunks[i]);
            }
        }
    }

    function _replayChunks(
        DayRecord memory rec_,
        uint256 marketId_
    ) internal returns (uint256 totalPayout) {
        return _buyChunks(rec_, marketId_, 0, false);
    }

    /// @notice The quote amount for the next chunk: enough for the remaining payout at
    ///         the current price, capped at 90% of `maxAmountAccepted` so that the same
    ///         amounts stay executable in the v2 branch, whose market capacity differs
    ///         slightly from day 2 on.
    function _chunkQuote(
        uint256 marketId_,
        uint256 remainingPayout_
    ) internal view returns (uint256) {
        uint256 quote = remainingPayout_.mulDivUp(
            auctioneer.marketPrice(marketId_),
            auctioneer.marketScale(marketId_)
        );
        uint256 cap = (auctioneer.maxAmountAccepted(marketId_, address(0)) * 9) / 10;
        return quote > cap ? cap : quote;
    }

    function _purchase(uint256 marketId_, uint256 quoteAmount_) internal returns (uint256 payout) {
        vm.prank(MINTR_MODULE);
        ohm.mint(buyer, quoteAmount_);

        uint256 minAmountOut = auctioneer.payoutFor(quoteAmount_, marketId_, address(0));
        vm.startPrank(buyer);
        ohm.approve(BOND_TELLER, quoteAmount_);
        (payout, ) = teller.purchase(buyer, address(0), marketId_, quoteAmount_, minAmountOut);
        vm.stopPrank();
    }

    // ============ HELPERS ============ //

    function _warpToNextBeat() internal {
        vm.warp(heart.lastBeat() + heart.frequency());
    }

    function _beatIntraDay() internal {
        _warpToNextBeat();
        _updateOracles();
        vm.prank(keeper);
        heart.beat();
    }

    /// @notice Reads the market fields used by the comparisons without spilling the full
    ///         12-slot tuple into the caller's stack.
    function _marketSummary(
        uint256 marketId_
    ) internal view returns (uint256 capacity, uint256 minPrice, uint256 scale) {
        (, , , , , capacity, , minPrice, , , , scale) = auctioneer.markets(marketId_);
    }

    function _chunkSum(DayRecord memory rec_) internal pure returns (uint256 sum) {
        for (uint256 i = 0; i < rec_.chunkCount; ++i) {
            sum += rec_.ohmChunks[i];
        }
    }

    /// @notice The v1 clearinghouse interest shape: the registry receivables are summed
    ///         first and the rate is applied once.
    function _sumThenDivideInterest() internal view returns (uint256) {
        uint256 receivables;
        uint256 len = chreg.registryCount();
        for (uint256 i = 0; i < len; ++i) {
            receivables += _readPrincipalReceivables(chreg.registry(i));
        }
        return (receivables * 5) / 1000 / 52;
    }

    /// @notice The v2 clearinghouse interest shape: the interest is floored per
    ///         clearinghouse (no offsets are set in this test).
    function _perHouseInterest() internal view returns (uint256 interest) {
        uint256 len = chreg.registryCount();
        for (uint256 i = 0; i < len; ++i) {
            interest += (_readPrincipalReceivables(chreg.registry(i)) * 5) / 1000 / 52;
        }
    }
}
