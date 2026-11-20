// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";
import {MockPriceCacherTaskCache} from "./MockPriceCacherTaskCache.sol";

contract PriceCacherTaskSelfExecuteTaskTest is PriceCacherTaskTest {
    // Scenarios: PCACHER-SELF-EXECUTE-A01.
    function test_whenCallerIsNotSelf_selfExecuteTaskReverts(address caller_) public {
        vm.assume(caller_ != address(cacher));
        _expectConfigRejected(
            caller_,
            abi.encodeCall(cacher.selfExecuteTask, ()),
            abi.encodeWithSelector(IPriceCacherTask.PriceCacherTask_OnlySelf.selector)
        );
    }

    // Scenarios: PCACHER-SELF-EXECUTE-A01.
    function test_whenCallerBoundarySeedsUsed_reverts() public {
        test_whenCallerIsNotSelf_selfExecuteTaskReverts(address(0));
        test_whenCallerIsNotSelf_selfExecuteTaskReverts(admin);
        test_whenCallerIsNotSelf_selfExecuteTaskReverts(heart);
    }

    // Scenarios: PCACHER-SELF-EXECUTE-D01.
    function test_givenCacheInactive_whenCalled_thenDependencyErrorBeforeStatusRead(
        bool enabled_
    ) public {
        _setCacheState(priceCache, true, enabled_);
        _setCacheMembership(false);
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(priceCache)
            )
        );
        vm.prank(address(cacher));
        cacher.selfExecuteTask();
        assertEq(priceCache.callCount(), 0, "inactive cache rejects work before the status read");
    }

    // Scenarios: PCACHER-SELF-EXECUTE-D02.
    function test_givenCachePaused_whenCalled_thenDependencyError() public {
        priceCache.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(priceCache)
            )
        );
        vm.prank(address(cacher));
        cacher.selfExecuteTask();
        assertEq(priceCache.callCount(), 0, "paused cache rejects work");
    }

    // Scenarios: PCACHER-SELF-EXECUTE-N01, PCACHER-SELF-EXECUTE-P01.
    function test_whenCollectionVaries_thenExactAttempts(uint8 count_) public {
        _seedPairs(bound(count_, 0, 32));
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        vm.prank(address(cacher));
        cacher.selfExecuteTask();
        _assertAttempts(priceCache, pairs);
    }

    // Scenarios: PCACHER-SELF-EXECUTE-N01, PCACHER-SELF-EXECUTE-P01.
    function test_whenEmptyCollection_thenNoAttempts() public {
        test_whenCollectionVaries_thenExactAttempts(0);
    }

    // Scenarios: PCACHER-SELF-EXECUTE-N01, PCACHER-SELF-EXECUTE-P01.
    function test_whenSinglePair_thenOneAttempt() public {
        test_whenCollectionVaries_thenExactAttempts(1);
    }

    // Scenarios: PCACHER-SELF-EXECUTE-N01, PCACHER-SELF-EXECUTE-P01.
    function test_whenLargerCollection_thenEveryPairAttempted() public {
        test_whenCollectionVaries_thenExactAttempts(32);
    }

    // Scenarios: PCACHER-SELF-EXECUTE-T01.
    function test_givenStatusGetterReverts_whenCalled_reverts() public {
        priceCache.setRevertEnabledQuery(true);
        _expectConfigRejected(
            address(cacher),
            abi.encodeCall(cacher.selfExecuteTask, ()),
            abi.encodeWithSelector(
                MockPriceCacherTaskCache.PairReverted.selector,
                address(0),
                address(0)
            )
        );
    }

    // Scenarios: PCACHER-SELF-EXECUTE-T02.
    function test_givenFirstPairFails_whenCalled_thenSecondPairSucceeds() public {
        priceCache.setRevertingPair(ohm, usds);
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.PairCacheFailed(
            address(priceCache),
            ohm,
            usds,
            MockPriceCacherTaskCache.PairReverted.selector
        );
        vm.prank(address(cacher));
        cacher.selfExecuteTask();
        assertEq(priceCache.callCount(), 1, "one independent success");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 0, "first pair did not update");
        assertEq(
            priceCache.pairCallCount(_pairKey(ohm, usde)),
            1,
            "second pair updated exactly once"
        );
    }
}
