// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockPriceCacherTaskCache} from "./MockPriceCacherTaskCache.sol";
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";

contract PriceCacherTaskAddAssetPairTest is PriceCacherTaskTest {
    uint256 internal constant _PAIR_COUNT_AFTER_MULTIPLE_ADDS = 4;

    // when caller has neither configuration role
    //  then the call reverts
    // Scenarios: PCACHER-ADD-PAIR-A01.
    function test_whenCallerIsNotAuthorized_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, PRICE_ADMIN_ROLE));

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        cacher.addAssetPair(alice, usds);
    }

    // Scenarios: PCACHER-ADD-PAIR-A03, PCACHER-ADD-PAIR-L04.
    function test_whenPriceAdminAddsPair(address caller_, bool enabled_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        _grantTestRole(PRICE_ADMIN_ROLE, caller_);
        _setTaskEnabled(enabled_);
        _addSucceeds(caller_, alice, usds);
    }

    // Scenarios: PCACHER-ADD-PAIR-A04.
    function test_whenBothRolesAddPair(address caller_) public {
        _grantTestRole(ADMIN_ROLE, caller_);
        _grantTestRole(PRICE_ADMIN_ROLE, caller_);
        _addSucceeds(caller_, alice, usds);
    }

    // Scenarios: PCACHER-ADD-PAIR-L05.
    function test_givenInactive_whenPriceAdminAddsPair_reverts(bool enabled_) public {
        address caller = makeAddr("priceAdmin");
        _grantTestRole(PRICE_ADMIN_ROLE, caller);
        _setTaskEnabled(enabled_);
        _setTaskMembership(false);
        _expectConfigRejected(
            caller,
            abi.encodeCall(cacher.addAssetPair, (alice, usds)),
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
    }

    // when asset is zero
    //  then the call reverts
    // Scenarios: PCACHER-ADD-PAIR-I01.
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.addAssetPair(address(0), usds);
    }

    // when quote is zero
    //  then the call reverts
    // Scenarios: PCACHER-ADD-PAIR-I02.
    function test_whenQuoteIsZero_reverts() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.addAssetPair(ohm, address(0));
    }

    // when asset equals quote
    //  then the call reverts
    // Scenarios: PCACHER-ADD-PAIR-I03.
    function test_whenAssetEqualsQuote_reverts() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.addAssetPair(ohm, ohm);
    }

    // given the pair exists
    //  when the asset pair is added
    //   then the call reverts
    // Scenarios: PCACHER-ADD-PAIR-I04.
    function test_givenPairExists_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_AssetPairAlreadyAdded.selector,
                ohm,
                usds
            )
        );
        vm.prank(admin);
        cacher.addAssetPair(ohm, usds);
    }

    // given the pair exists in reverse order
    //  when the asset pair is added
    //   then the call reverts
    // Scenarios: PCACHER-ADD-PAIR-I05.
    function test_givenPairExistsInReverseOrder_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_AssetPairAlreadyAdded.selector,
                usds,
                ohm
            )
        );
        vm.prank(admin);
        cacher.addAssetPair(usds, ohm);
    }

    // when pair is not supported by PriceCache
    //  then the call reverts
    // Scenarios: PCACHER-ADD-PAIR-D01.
    function test_whenPairIsNotSupportedByPriceCache_reverts() public {
        priceCache.setUnsupportedPair(alice, usds);

        vm.expectRevert(
            abi.encodeWithSelector(MockPriceCacherTaskCache.PairUnsupported.selector, alice, usds)
        );
        vm.prank(admin);
        cacher.addAssetPair(alice, usds);
    }

    // given PriceCacherTask is enabled
    //  when admin adds multiple pairs
    //   then the requested pair is stored
    // Scenarios: PCACHER-ADD-PAIR-P01.
    function test_givenEnabled_whenAdminAddsMultiplePairs() public {
        address secondAsset = makeAddr("secondAsset");

        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacherTask.AssetPairAdded(alice, usds);
        vm.prank(admin);
        cacher.addAssetPair(alice, usds);
        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacherTask.AssetPairAdded(secondAsset, usde);
        vm.prank(admin);
        cacher.addAssetPair(secondAsset, usde);

        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        assertEq(pairs.length, _PAIR_COUNT_AFTER_MULTIPLE_ADDS, "pair count");
        assertEq(pairs[0].asset, ohm, "first asset");
        assertEq(pairs[0].quote, usds, "first quote");
        assertEq(pairs[1].asset, ohm, "second asset");
        assertEq(pairs[1].quote, usde, "second quote");
        assertEq(pairs[2].asset, alice, "added asset");
        assertEq(pairs[2].quote, usds, "added quote");
        assertEq(pairs[3].asset, secondAsset, "second added asset");
        assertEq(pairs[3].quote, usde, "second added quote");
    }

    // given PriceCacherTask is disabled
    //  when admin adds pair
    //   then the requested pair is stored
    // Scenarios: PCACHER-ADD-PAIR-L01.
    function test_givenDisabled_whenAdminAddsPair() public {
        vm.prank(emergency);
        cacher.disable("");

        _addSucceeds(admin, alice, usds);
        assertFalse(cacher.isEnabled(), "cacher should remain disabled");
    }

    // given PriceCacherTask is re-enabled
    //  when admin adds pair
    //   then the requested pair is stored
    // Scenarios: PCACHER-ADD-PAIR-L02.
    function test_givenReEnabled_whenAdminAddsPair() public {
        vm.prank(emergency);
        cacher.disable("");
        vm.prank(admin);
        cacher.reEnable();

        _addSucceeds(admin, alice, usds);
        assertTrue(cacher.isEnabled(), "cacher should remain enabled");
    }

    // Scenarios: PCACHER-ADD-PAIR-A02, PCACHER-ADD-PAIR-N01.
    function test_whenAdminAndPairDomainVary_thenExactAppend(
        address caller_,
        address asset_,
        address quote_,
        uint8 count_,
        bool overlap_
    ) public {
        vm.assume(asset_ != address(0) && quote_ != address(0) && asset_ != quote_);
        _grantTestRole(ADMIN_ROLE, caller_);
        if (overlap_) {
            _grantTestRole(EMERGENCY_ROLE, caller_);
            _grantTestRole(HEART_ROLE, caller_);
        }
        _seedPairs(bound(count_, 0, 32));
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        for (uint256 i; i < pairs.length; ++i)
            vm.assume(
                !((asset_ == pairs[i].asset && quote_ == pairs[i].quote) ||
                    (asset_ == pairs[i].quote && quote_ == pairs[i].asset))
            );
        _addSucceeds(caller_, asset_, quote_);
    }

    // Scenarios: PCACHER-ADD-PAIR-A02, PCACHER-ADD-PAIR-N01.
    function test_whenPairAndCollectionBoundarySeedsUsed() public {
        test_whenAdminAndPairDomainVary_thenExactAppend(
            admin,
            address(1),
            address(type(uint160).max),
            0,
            false
        );
        test_whenAdminAndPairDomainVary_thenExactAppend(
            heart,
            address(type(uint160).max),
            address(1),
            1,
            true
        );
        test_whenAdminAndPairDomainVary_thenExactAppend(
            emergency,
            address(1),
            address(type(uint160).max),
            32,
            true
        );
    }

    // Scenarios: PCACHER-ADD-PAIR-L03.
    function test_givenInactive_whenPairAdded_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setTaskMembership(false);
        _expectConfigRejected(
            admin,
            abi.encodeCall(cacher.addAssetPair, (alice, usds)),
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
    }

    // Scenarios: PCACHER-ADD-PAIR-P02.
    function test_whenPairGetterHasArbitraryCallerAndLifecycle(
        address caller_,
        bool active_,
        bool enabled_,
        uint8 count_
    ) public {
        _seedPairs(bound(count_, 0, 32));
        IPriceCacherTask.AssetPair[] memory expected = cacher.getAssetPairs();
        _setTaskEnabled(enabled_);
        _setTaskMembership(active_);
        vm.record();
        vm.prank(caller_);
        IPriceCacherTask.AssetPair[] memory actual = cacher.getAssetPairs();
        assertEq(abi.encode(actual), abi.encode(expected), "getter returns exact pair copy");
        (, bytes32[] memory writes) = vm.accesses(address(cacher));
        assertEq(writes.length, 0, "getter writes no storage");
        if (actual.length != 0) actual[0].asset = address(0);
        _assertPairs(expected);
    }

    function _addSucceeds(address caller_, address asset_, address quote_) internal {
        IPriceCacherTask.AssetPair[] memory beforePairs = cacher.getAssetPairs();
        IPriceCacherTask.AssetPair[] memory expected = new IPriceCacherTask.AssetPair[](
            beforePairs.length + 1
        );
        for (uint256 i; i < beforePairs.length; ++i) expected[i] = beforePairs[i];
        expected[beforePairs.length] = IPriceCacherTask.AssetPair(asset_, quote_);
        bool enabled = cacher.isEnabled();
        uint48 transition = cacher.lastTransitionAt();
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.AssetPairAdded(asset_, quote_);
        vm.prank(caller_);
        cacher.addAssetPair(asset_, quote_);
        _assertPairs(expected);
        assertEq(cacher.isEnabled(), enabled, "append preserves pause state");
        assertEq(cacher.lastTransitionAt(), transition, "append preserves history");
        assertEq(priceCache.callCount(), 0, "append does not refresh cache");
    }

    // Scenarios: PCACHER-ADD-PAIR-L06.
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
        cacher.addAssetPair(address(0), address(0));
    }
}
