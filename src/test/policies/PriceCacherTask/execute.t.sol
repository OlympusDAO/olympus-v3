// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockPriceCacherTaskCache} from "./MockPriceCacherTaskCache.sol";
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract PriceCacherTaskExecuteTest is PriceCacherTaskTest {
    // when the caller does not have the HEART role
    //  then the call reverts
    // Scenarios: PCACHER-EXECUTE-A01.
    function test_whenCallerDoesNotHaveHeartRole_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, HEART_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        cacher.execute();
    }

    // given PriceCacherTask is disabled
    //  when the periodic task executes
    //   then the call is a no-op
    // Scenarios: PCACHER-EXECUTE-L01.
    function test_givenDisabled_isNoOp() public {
        vm.prank(emergency);
        cacher.disable("");

        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given PriceCache is inactive
    //  when the periodic task executes
    //   then the task reports failure without reverting Heart
    // Scenarios: PCACHER-EXECUTE-D01.
    function test_givenPriceCacheIsInactive_reportsFailure() public {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(priceCache));

        vm.expectEmit(false, false, false, true, address(cacher));
        emit IPriceCacherTask.ExecutionFailed(PolicyDependency.PolicyDependency_NotActive.selector);
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given PriceCache is disabled
    //  when the periodic task executes
    //   then the task reports failure without reverting Heart
    // Scenarios: PCACHER-EXECUTE-D02.
    function test_givenPriceCacheIsDisabled_reportsFailure() public {
        priceCache.disable("");

        vm.expectEmit(false, false, false, true, address(cacher));
        emit IPriceCacherTask.ExecutionFailed(PolicyDependency.PolicyDependency_NotActive.selector);
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given PriceCache enabled query reverts
    //  when the periodic task executes
    //   then it emits the failure and returns
    // Scenarios: PCACHER-EXECUTE-T01.
    function test_givenPriceCacheEnabledQueryReverts_emitsFailureAndReturns() public {
        priceCache.setRevertEnabledQuery(true);

        vm.expectEmit(false, false, false, true, address(cacher));
        emit IPriceCacherTask.ExecutionFailed(MockPriceCacherTaskCache.PairReverted.selector);
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given an operational PriceCache
    //  when the periodic task executes
    //   then it attempts configured pairs in order
    // Scenarios: PCACHER-EXECUTE-P01.
    function test_givenOperationalPriceCache_attemptsConfiguredPairsInOrder() public {
        vm.expectCall(address(cacher), 0, 1_000_000, abi.encodeCall(cacher.selfExecuteTask, ()), 1);
        vm.expectCall(
            address(priceCache),
            0,
            400_000,
            abi.encodeCall(priceCache.cachePriceIfNecessary, (ohm, usds, uint48(0))),
            1
        );
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 2, "cache calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 1, "OHM/USDS calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "OHM/USDe calls");
        assertEq(priceCache.lastAsset(), ohm, "last asset");
        assertEq(priceCache.lastQuote(), usde, "last quote");
        assertEq(priceCache.lastMaxAge(), 0, "maximum age");
        _assertAttempts(priceCache, cacher.getAssetPairs());
    }

    // given first pair reverts
    //  when the periodic task executes
    //   then it attempts the second pair
    // Scenarios: PCACHER-EXECUTE-T02.
    function test_givenFirstPairReverts_attemptsSecondPair() public {
        priceCache.setRevertingPair(ohm, usds);

        vm.expectEmit(true, true, true, true, address(cacher));
        emit IPriceCacherTask.PairCacheFailed(
            address(priceCache),
            ohm,
            usds,
            MockPriceCacherTaskCache.PairReverted.selector
        );
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 1, "successful calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "second pair calls");
    }

    // given configured pair becomes unsupported
    //  when the periodic task executes
    //   then it attempts the next pair without reverting
    // Scenarios: PCACHER-EXECUTE-T03.
    function test_givenConfiguredPairBecomesUnsupported_attemptsNextPairWithoutReverting() public {
        priceCache.setUnsupportedPair(ohm, usds);

        vm.expectEmit(true, true, true, true, address(cacher));
        emit IPriceCacherTask.PairCacheFailed(
            address(priceCache),
            ohm,
            usds,
            MockPriceCacherTaskCache.PairUnsupported.selector
        );
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 1, "successful calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "second pair calls");
    }

    // given second pair reverts
    //  when the periodic task executes
    //   then it preserves the first successful pair
    // Scenarios: PCACHER-EXECUTE-T04.
    function test_givenSecondPairReverts_preservesFirstPair() public {
        priceCache.setRevertingPair(ohm, usde);

        vm.expectEmit(true, true, true, true, address(cacher));
        emit IPriceCacherTask.PairCacheFailed(
            address(priceCache),
            ohm,
            usde,
            MockPriceCacherTaskCache.PairReverted.selector
        );
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 1, "successful calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 1, "first pair calls");
    }

    // Scenarios: PCACHER-EXECUTE-A02, PCACHER-EXECUTE-N01.
    function test_whenHeartAndCollectionVary_thenExactAttempts(
        address caller_,
        uint8 count_
    ) public {
        _grantTestRole(HEART_ROLE, caller_);
        _seedPairs(bound(count_, 0, 4));
        _executeSucceeds(caller_);
    }

    // Scenarios: PCACHER-EXECUTE-N01.
    function test_whenEmptyPairSet_thenNoCacheCalls() public {
        test_whenHeartAndCollectionVary_thenExactAttempts(heart, 0);
    }

    // Scenarios: PCACHER-EXECUTE-N01.
    function test_whenSinglePair_thenOneCacheCall() public {
        test_whenHeartAndCollectionVary_thenExactAttempts(heart, 1);
    }

    // Scenarios: PCACHER-EXECUTE-N02.
    function test_givenLargePairSet_whenExecuted_thenReportsDeferredWork() public {
        _seedPairs(32);
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();

        vm.recordLogs();
        vm.prank(heart);
        cacher.execute();

        uint256 refreshed = priceCache.callCount();
        assertGt(refreshed, 0, "refreshes some pairs within the task cap");
        assertLt(refreshed, pairs.length, "defers the remaining pairs");
        for (uint256 i; i < refreshed; ++i) {
            (address asset, address quote, ) = priceCache.recordedCalls(i);
            assertEq(asset, pairs[i].asset, "refreshes prefix assets in stored order");
            assertEq(quote, pairs[i].quote, "refreshes prefix quotes in stored order");
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "emits one deferral event");
        assertEq(logs[0].emitter, address(cacher), "task emits the deferral");
        assertEq(logs[0].topics[0], IPriceCacherTask.ExecutionDeferred.selector, "deferral event");
        assertEq(abi.decode(logs[0].data, (uint256)), refreshed, "index of first skipped pair");
    }

    // Scenarios: PCACHER-EXECUTE-N03.
    function test_whenGasAllowsOnePair_thenEachExecutionStartsAtFirstPair() public {
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.ExecutionDeferred(1);
        vm.prank(heart);
        cacher.execute{gas: 550_000}();

        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 1, "first pair refreshed");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 0, "second pair deferred");

        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.ExecutionDeferred(1);
        vm.prank(heart);
        cacher.execute{gas: 550_000}();

        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 2, "refreshes first pair again");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 0, "second pair still skipped");
    }

    // Scenarios: PCACHER-EXECUTE-N04.
    function test_whenGasCannotFundAPair_thenReportsDeferral() public {
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.ExecutionDeferred(0);
        vm.prank(heart);
        cacher.execute{gas: 250_000}();

        assertEq(priceCache.callCount(), 0, "no pair attempted below the gas threshold");
    }

    // Scenarios: PCACHER-EXECUTE-N06.
    function test_whenGasCannotFundSelfCall_thenReportsDeferralWithoutCalling() public {
        vm.expectCall(address(cacher), abi.encodeCall(cacher.selfExecuteTask, ()), uint64(0));
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.ExecutionDeferred(0);
        vm.prank(heart);
        cacher.execute{gas: 35_000}();
    }

    // Scenarios: PCACHER-EXECUTE-N05.
    function test_givenPairRemovedAfterDeferral_whenExecuted_thenStartsAtRemainingPair() public {
        vm.prank(heart);
        cacher.execute{gas: 550_000}();
        assertEq(priceCache.callCount(), 1, "first run deferred the second pair");
        vm.prank(admin);
        cacher.removeAssetPair(ohm, usds);

        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "refreshes the remaining pair");
    }

    // Scenarios: PCACHER-EXECUTE-N07.
    function test_givenThreePairs_whenExecutionLimitIsRaised_thenAllPairsRefresh() public {
        address quote = makeAddr("third quote");
        vm.startPrank(admin);
        cacher.addAssetPair(ohm, quote);
        // This budget covers two mock refreshes before reaching the pair limit plus reserve.
        cacher.setGasLimits(660_000, 400_000);
        vm.stopPrank();

        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.ExecutionDeferred(2);
        vm.prank(heart);
        cacher.execute();
        assertEq(priceCache.callCount(), 2, "refreshes two pairs at the lower cap");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, quote)), 0, "third pair skipped");

        vm.prank(admin);
        cacher.setGasLimits(1_000_000, 400_000);
        vm.prank(heart);
        cacher.execute();
        assertEq(priceCache.callCount(), 5, "refreshes all three from the start");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, quote)), 1, "reaches third pair");
    }

    // Scenarios: PCACHER-EXECUTE-N08.
    function test_whenPairGasLimitIsExhausted_thenReportsEachFailure() public {
        vm.prank(admin);
        cacher.setGasLimits(1_000_000, 1);

        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.PairCacheFailed(address(priceCache), ohm, usds, bytes4(0));
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.PairCacheFailed(address(priceCache), ohm, usde, bytes4(0));
        vm.prank(heart);
        cacher.execute();
        assertEq(priceCache.callCount(), 0, "neither gas-limited cache write succeeds");

        vm.prank(admin);
        cacher.setGasLimits(1_000_000, 400_000);
        vm.prank(heart);
        cacher.execute();
        assertEq(priceCache.callCount(), 2, "higher pair limit allows both cache writes");
    }

    // Scenarios: PCACHER-EXECUTE-L02, PCACHER-EXECUTE-L03.
    function test_givenInactive_whenExecuted_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setTaskMembership(false);
        _expectConfigRejected(
            heart,
            abi.encodeCall(cacher.execute, ()),
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
    }

    // Scenarios: PCACHER-EXECUTE-D03.
    function test_givenCacheInactiveDisabled_whenExecuted_thenFailureAndNoCalls() public {
        priceCache.disable("");
        _setCacheMembership(false);
        vm.expectEmit(false, false, false, true, address(cacher));
        emit IPriceCacherTask.ExecutionFailed(PolicyDependency.PolicyDependency_NotActive.selector);
        vm.prank(heart);
        cacher.execute();
        assertEq(priceCache.callCount(), 0, "no work for inactive paused cache");
    }

    // Scenarios: PCACHER-EXECUTE-P02.
    function test_givenReEnabled_whenExecuted_thenNormalWork() public {
        vm.startPrank(admin);
        cacher.disable("");
        cacher.reEnable();
        vm.stopPrank();
        _executeSucceeds(heart);
    }

    // Scenarios: PCACHER-EXECUTE-P02.
    function test_givenReactivated_whenExecuted_thenNormalWork() public {
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(cacher));
        kernel.executeAction(Actions.ActivatePolicy, address(cacher));
        vm.stopPrank();
        _executeSucceeds(heart);
    }

    // Scenarios: PCACHER-EXECUTE-A03.
    function test_givenDisabled_whenUnauthorizedCallerExecutes_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, HEART_ROLE));
        vm.prank(admin);
        cacher.disable("");
        _expectConfigRejected(
            caller_,
            abi.encodeCall(cacher.execute, ()),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE)
        );
    }

    // Scenarios: PCACHER-EXECUTE-T05.
    function test_givenEmptyStatusError_whenExecuted_thenZeroSelector() public {
        _statusFailure("", bytes4(0));
    }

    // Scenarios: PCACHER-EXECUTE-T06.
    function test_givenShortStatusErrors_whenExecuted_thenPaddedSelectors() public {
        _statusFailure(hex"aa", 0xaa000000);
        _statusFailure(hex"aabb", 0xaabb0000);
        _statusFailure(hex"aabbcc", 0xaabbcc00);
    }

    // Scenarios: PCACHER-EXECUTE-T07.
    function test_givenLargeStatusError_whenExecuted_thenPrefixOnly() public {
        _statusFailure(_largeError(), 0xdeadbeef);
    }

    // Scenarios: PCACHER-EXECUTE-T08.
    function test_givenEmptyPairError_whenExecuted_thenNextPairSucceeds() public {
        _pairFailure("", bytes4(0));
    }

    // Scenarios: PCACHER-EXECUTE-T09.
    function test_givenShortPairError_whenExecuted_thenNextPairSucceeds() public {
        _pairFailure(hex"aa", 0xaa000000);
    }

    // Scenarios: PCACHER-EXECUTE-T10.
    function test_givenLargePairError_whenExecuted_thenNextPairSucceeds() public {
        _pairFailure(_largeError(), 0xdeadbeef);
    }

    function _executeSucceeds(address caller_) internal {
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        vm.expectCall(address(cacher), abi.encodeCall(cacher.selfExecuteTask, ()), uint64(1));
        vm.prank(caller_);
        cacher.execute();
        _assertAttempts(priceCache, pairs);
    }

    function _statusFailure(bytes memory data_, bytes4 selector_) internal {
        vm.mockCallRevert(address(priceCache), abi.encodeWithSignature("isEnabled()"), data_);
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.ExecutionFailed(selector_);
        vm.prank(heart);
        cacher.execute();
        assertEq(priceCache.callCount(), 0, "status failure makes no cache calls");
    }

    function _pairFailure(bytes memory data_, bytes4 selector_) internal {
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeCall(priceCache.cachePriceIfNecessary, (ohm, usds, uint48(0))),
            data_
        );
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.PairCacheFailed(address(priceCache), ohm, usds, selector_);
        vm.prank(heart);
        cacher.execute();
        assertEq(priceCache.callCount(), 1, "only independent second pair succeeds");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 0, "failed first pair rolled back");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "second pair attempted once");
    }

    function _largeError() internal pure returns (bytes memory data) {
        data = new bytes(4096);
        data[0] = 0xde;
        data[1] = 0xad;
        data[2] = 0xbe;
        data[3] = 0xef;
    }

    // Scenarios: PCACHER-EXECUTE-L04.
    function test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst(
        address caller_
    ) public {
        _setTaskEnabled(false);
        _setTaskMembership(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
        vm.prank(caller_);
        cacher.execute();
    }
}
