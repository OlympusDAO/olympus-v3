// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Contracts
import {BurnerLoansForkTest} from "./fixtures/BurnerLoansForkTest.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusHeart as Heart} from "src/policies/Heart.sol";
import {PriceCacherTask} from "src/policies/PriceCacherTask.sol";

contract BurnerLoansPriceCacherForkTest is BurnerLoansForkTest {
    // Scenarios: BLPF-P09.
    function test_givenLaunchedMarkets_whenPriceCacherRunsInHeart_thenRefreshesBothPairs() public {
        Heart heart = Heart(_graph.heart);
        _schedulePriceCacher(2_500_000, 1_200_000);
        _assertBothCacheRounds(0);
        uint48 lastBeat = heart.lastBeat();

        vm.startSnapshotGas("BurnerLoans.heart.withPriceCacher");
        heart.beat();
        uint256 beatGas = vm.stopSnapshotGas();
        emit log_named_uint("Heart beat gas with PriceCacherTask", beatGas);

        assertGt(heart.lastBeat(), lastBeat, "Heart completes its full beat");
        _assertBothCacheRounds(1);
    }

    // Scenarios: BLPF-T02.
    function test_whenPairGasIsTooLow_thenHeartCompletesWithoutRefreshing() public {
        Heart heart = Heart(_graph.heart);
        PriceCacherTask cacher = _schedulePriceCacher(1_000_000, 400_000);
        _assertBothCacheRounds(0);
        uint48 lastBeat = heart.lastBeat();

        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.PairCacheFailed(
            _graph.priceCache,
            _graph.ohm,
            _graph.usds,
            bytes4(0)
        );
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.PairCacheFailed(
            _graph.priceCache,
            _graph.ohm,
            _graph.usde,
            bytes4(0)
        );
        heart.beat();

        assertGt(heart.lastBeat(), lastBeat, "Heart completes despite both failed refreshes");
        _assertBothCacheRounds(0);
    }

    function _schedulePriceCacher(
        uint32 executionGas_,
        uint32 pairGas_
    ) private returns (PriceCacherTask cacher) {
        cacher = new PriceCacherTask(
            _kernel,
            IPriceCache(_graph.priceCache),
            executionGas_,
            pairGas_
        );
        vm.prank(_kernel.executor());
        _kernel.executeAction(Actions.ActivatePolicy, address(cacher));

        vm.startPrank(_timelock);
        cacher.addAssetPair(_graph.ohm, _graph.usds);
        cacher.addAssetPair(_graph.ohm, _graph.usde);
        cacher.enable("");
        Heart(_graph.heart).addPeriodicTaskAtIndex(address(cacher), bytes4(0), 0);
        vm.stopPrank();
    }

    function _assertBothCacheRounds(uint80 expectedRound_) private view {
        IPriceCache cache = IPriceCache(_graph.priceCache);
        assertEq(
            cache.getCachedPrice(_graph.ohm, _graph.usds).roundId,
            expectedRound_,
            "OHM/USDS cache round"
        );
        assertEq(
            cache.getCachedPrice(_graph.ohm, _graph.usde).roundId,
            expectedRound_,
            "OHM/USDe cache round"
        );
    }
}
