// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockPriceCacherCache} from "./MockPriceCacherCache.sol";
import {PriceCacherTest} from "./PriceCacherTest.sol";

contract PriceCacherExecuteTest is PriceCacherTest {
    // when the caller does not have the HEART role
    //  then the call reverts
    function test_whenCallerDoesNotHaveHeartRole_reverts(address caller_) public {
        vm.assume(caller_ != heart);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        cacher.execute();
    }

    // given PriceCacher is disabled
    //  when the periodic task executes
    //   then the call is a no-op
    function test_givenDisabled_isNoOp() public {
        vm.prank(emergency);
        cacher.disable("");

        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given PriceCache is inactive
    //  when the periodic task executes
    //   then the call is a no-op
    function test_givenPriceCacheIsInactive_isNoOp() public {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(priceCache));

        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given PriceCache is disabled
    //  when the periodic task executes
    //   then the call is a no-op
    function test_givenPriceCacheIsDisabled_isNoOp() public {
        priceCache.disable("");

        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given PriceCache enabled query reverts
    //  when the periodic task executes
    //   then it emits the failure and returns
    function test_givenPriceCacheEnabledQueryReverts_emitsFailureAndReturns() public {
        priceCache.setRevertEnabledQuery(true);

        vm.expectEmit(false, false, false, true, address(cacher));
        emit IPriceCacher.ExecutionFailed(MockPriceCacherCache.PairReverted.selector);
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 0, "cache calls");
    }

    // given an operational PriceCache
    //  when the periodic task executes
    //   then it attempts configured pairs in order
    function test_givenOperationalPriceCache_attemptsConfiguredPairsInOrder() public {
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 2, "cache calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 1, "OHM/USDS calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "OHM/USDe calls");
        assertEq(priceCache.lastAsset(), ohm, "last asset");
        assertEq(priceCache.lastQuote(), usde, "last quote");
        assertEq(priceCache.lastMaxAge(), 0, "maximum age");
    }

    // given first pair reverts
    //  when the periodic task executes
    //   then it attempts the second pair
    function test_givenFirstPairReverts_attemptsSecondPair() public {
        priceCache.setRevertingPair(ohm, usds);

        vm.expectEmit(true, true, true, true, address(cacher));
        emit IPriceCacher.PairCacheFailed(
            address(priceCache),
            ohm,
            usds,
            MockPriceCacherCache.PairReverted.selector
        );
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 1, "successful calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "second pair calls");
    }

    // given configured pair becomes unsupported
    //  when the periodic task executes
    //   then it attempts the next pair without reverting
    function test_givenConfiguredPairBecomesUnsupported_attemptsNextPairWithoutReverting() public {
        priceCache.setUnsupportedPair(ohm, usds);

        vm.expectEmit(true, true, true, true, address(cacher));
        emit IPriceCacher.PairCacheFailed(
            address(priceCache),
            ohm,
            usds,
            MockPriceCacherCache.PairUnsupported.selector
        );
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 1, "successful calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usde)), 1, "second pair calls");
    }

    // given second pair reverts
    //  when the periodic task executes
    //   then it preserves the first successful pair
    function test_givenSecondPairReverts_preservesFirstPair() public {
        priceCache.setRevertingPair(ohm, usde);

        vm.expectEmit(true, true, true, true, address(cacher));
        emit IPriceCacher.PairCacheFailed(
            address(priceCache),
            ohm,
            usde,
            MockPriceCacherCache.PairReverted.selector
        );
        vm.prank(heart);
        cacher.execute();

        assertEq(priceCache.callCount(), 1, "successful calls");
        assertEq(priceCache.pairCallCount(_pairKey(ohm, usds)), 1, "first pair calls");
    }

    // when caller is not self
    //  then the self-execution call reverts
    function test_whenCallerIsNotSelf_selfExecuteTaskReverts(address caller_) public {
        vm.assume(caller_ != address(cacher));
        vm.expectRevert(IPriceCacher.PriceCacher_OnlySelf.selector);
        vm.prank(caller_);
        cacher.selfExecuteTask();
    }
}
