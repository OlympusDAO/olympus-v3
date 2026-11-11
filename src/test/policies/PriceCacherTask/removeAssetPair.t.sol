// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";

contract PriceCacherTaskRemoveAssetPairTest is PriceCacherTaskTest {
    // when caller has neither configuration role
    //  then the call reverts
    // Scenarios: PCACHER-REMOVE-PAIR-A01.
    function test_whenCallerIsNotAuthorized_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, PRICE_ADMIN_ROLE));

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        cacher.removeAssetPair(ohm, usds);
    }

    // Scenarios: PCACHER-REMOVE-PAIR-A03, PCACHER-REMOVE-PAIR-L04.
    function test_whenPriceAdminRemovesPair(address caller_, bool enabled_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        _grantTestRole(PRICE_ADMIN_ROLE, caller_);
        _setTaskEnabled(enabled_);
        _removeSucceeds(caller_, ohm, usds);
    }

    // Scenarios: PCACHER-REMOVE-PAIR-A04.
    function test_whenBothRolesRemovePair(address caller_) public {
        _grantTestRole(ADMIN_ROLE, caller_);
        _grantTestRole(PRICE_ADMIN_ROLE, caller_);
        _removeSucceeds(caller_, ohm, usds);
    }

    // Scenarios: PCACHER-REMOVE-PAIR-L05.
    function test_givenInactive_whenPriceAdminRemovesPair_reverts(bool enabled_) public {
        address caller = makeAddr("priceAdmin");
        _grantTestRole(PRICE_ADMIN_ROLE, caller);
        _setTaskEnabled(enabled_);
        _setTaskMembership(false);
        _expectConfigRejected(
            caller,
            abi.encodeCall(cacher.removeAssetPair, (ohm, usds)),
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
    }

    // when asset is zero
    //  then the call reverts
    // Scenarios: PCACHER-REMOVE-PAIR-I01.
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.removeAssetPair(address(0), usds);
    }

    // when quote is zero
    //  then the call reverts
    // Scenarios: PCACHER-REMOVE-PAIR-I02.
    function test_whenQuoteIsZero_reverts() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.removeAssetPair(ohm, address(0));
    }

    // when asset equals quote
    //  then the call reverts
    // Scenarios: PCACHER-REMOVE-PAIR-I03.
    function test_whenAssetEqualsQuote_reverts() public {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.removeAssetPair(ohm, ohm);
    }

    // when pair does not exist
    //  then the call reverts
    // Scenarios: PCACHER-REMOVE-PAIR-I04.
    function test_whenPairDoesNotExist_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_AssetPairNotFound.selector,
                alice,
                usds
            )
        );
        vm.prank(admin);
        cacher.removeAssetPair(alice, usds);
    }

    // given the pair is no longer supported
    //  when admin removes pair
    //   then the matching pair is removed
    // Scenarios: PCACHER-REMOVE-PAIR-D01.
    function test_givenPairIsNoLongerSupported_whenAdminRemovesPair() public {
        priceCache.setUnsupportedPair(ohm, usds);
        vm.mockCallRevert(
            address(priceCache),
            abi.encodeWithSignature("validateAssetPair(address,address)"),
            hex"deadbeef"
        );
        _removeSucceeds(admin, ohm, usds);
    }

    // given the pair exists in reverse order
    //  when admin removes pair
    //   then the matching pair is removed
    // Scenarios: PCACHER-REMOVE-PAIR-P01.
    function test_givenPairExistsInReverseOrder_whenAdminRemovesPair() public {
        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacherTask.AssetPairRemoved(ohm, usds);
        vm.prank(admin);
        cacher.removeAssetPair(usds, ohm);

        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        assertEq(pairs.length, 1, "pair count");
        assertEq(pairs[0].asset, ohm, "remaining asset");
        assertEq(pairs[0].quote, usde, "remaining quote");
    }

    // given multiple entries exist
    //  when admin removes multiple pairs
    //   then the matching pair is removed
    // Scenarios: PCACHER-REMOVE-PAIR-P02.
    function test_givenMultipleEntries_whenAdminRemovesMultiplePairs() public {
        address secondAsset = makeAddr("secondAsset");
        vm.startPrank(admin);
        cacher.addAssetPair(alice, usds);
        cacher.addAssetPair(secondAsset, usde);

        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacherTask.AssetPairRemoved(ohm, usds);
        cacher.removeAssetPair(ohm, usds);
        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacherTask.AssetPairRemoved(alice, usds);
        cacher.removeAssetPair(alice, usds);
        vm.stopPrank();

        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        assertEq(pairs.length, 2, "pair count");
        assertEq(pairs[0].asset, secondAsset, "remaining asset");
        assertEq(pairs[0].quote, usde, "remaining quote");
        assertEq(pairs[1].asset, ohm, "second remaining asset");
        assertEq(pairs[1].quote, usde, "second remaining quote");
    }

    // given PriceCacherTask is disabled
    //  when admin removes pair
    //   then the matching pair is removed
    // Scenarios: PCACHER-REMOVE-PAIR-L01.
    function test_givenDisabled_whenAdminRemovesPair() public {
        vm.prank(emergency);
        cacher.disable("");

        _removeSucceeds(admin, ohm, usds);
        assertFalse(cacher.isEnabled(), "cacher should remain disabled");
    }

    // given PriceCacherTask is re-enabled
    //  when admin removes pair
    //   then the matching pair is removed
    // Scenarios: PCACHER-REMOVE-PAIR-L02.
    function test_givenReEnabled_whenAdminRemovesPair() public {
        vm.prank(emergency);
        cacher.disable("");
        vm.prank(admin);
        cacher.reEnable();

        _removeSucceeds(admin, ohm, usds);
        assertTrue(cacher.isEnabled(), "cacher should remain enabled");
    }

    // given one pair remains
    //  when admin removes pair
    //   then it allows an empty configuration
    // Scenarios: PCACHER-REMOVE-PAIR-P03.
    function test_givenOnePair_whenAdminRemovesPair_allowsEmptyConfiguration() public {
        vm.startPrank(admin);
        cacher.removeAssetPair(ohm, usds);
        cacher.removeAssetPair(ohm, usde);
        vm.stopPrank();

        assertEq(cacher.getAssetPairs().length, 0, "pair count");
    }

    // Scenarios: PCACHER-REMOVE-PAIR-A02, PCACHER-REMOVE-PAIR-N01.
    function test_whenAdminAndRemovalIndexVary_thenExactSurvivors(
        address caller_,
        uint8 count_,
        uint8 index_,
        bool reverse_
    ) public {
        _grantTestRole(ADMIN_ROLE, caller_);
        _seedPairs(bound(count_, 1, 32));
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        uint256 index = bound(index_, 0, pairs.length - 1);
        _removeSucceeds(
            caller_,
            reverse_ ? pairs[index].quote : pairs[index].asset,
            reverse_ ? pairs[index].asset : pairs[index].quote
        );
    }

    // Scenarios: PCACHER-REMOVE-PAIR-N01.
    function test_whenRemovalBoundarySeedsUsed() public {
        test_whenAdminAndRemovalIndexVary_thenExactSurvivors(admin, 1, 0, false);
        test_whenAdminAndRemovalIndexVary_thenExactSurvivors(admin, 2, 0, true);
        test_whenAdminAndRemovalIndexVary_thenExactSurvivors(admin, 32, 31, false);
    }

    // Scenarios: PCACHER-REMOVE-PAIR-N01.
    function test_whenFullAddressPairRemoved(address asset_, address quote_, bool reverse_) public {
        vm.assume(asset_ != address(0) && quote_ != address(0) && asset_ != quote_);
        _seedPairs(0);
        vm.prank(admin);
        cacher.addAssetPair(asset_, quote_);
        _removeSucceeds(admin, reverse_ ? quote_ : asset_, reverse_ ? asset_ : quote_);
    }

    // Scenarios: PCACHER-REMOVE-PAIR-L03.
    function test_givenInactive_whenPairRemoved_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setTaskMembership(false);
        _expectConfigRejected(
            admin,
            abi.encodeCall(cacher.removeAssetPair, (ohm, usds)),
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
    }

    // Scenarios: PCACHER-REMOVE-PAIR-N01.
    function test_whenAddressBoundaryPairRemoved() public {
        test_whenFullAddressPairRemoved(address(1), address(type(uint160).max), true);
    }

    function _removeSucceeds(address caller_, address asset_, address quote_) internal {
        IPriceCacherTask.AssetPair[] memory pairs = cacher.getAssetPairs();
        uint256 index;
        while (
            !((pairs[index].asset == asset_ && pairs[index].quote == quote_) ||
                (pairs[index].asset == quote_ && pairs[index].quote == asset_))
        ) ++index;
        IPriceCacherTask.AssetPair memory removed = pairs[index];
        IPriceCacherTask.AssetPair[] memory expected = new IPriceCacherTask.AssetPair[](
            pairs.length - 1
        );
        for (uint256 i; i < expected.length; ++i)
            expected[i] = i == index ? pairs[pairs.length - 1] : pairs[i];
        bool enabled = cacher.isEnabled();
        uint48 transition = cacher.lastTransitionAt();
        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.AssetPairRemoved(removed.asset, removed.quote);
        vm.prank(caller_);
        cacher.removeAssetPair(asset_, quote_);
        _assertPairs(expected);
        assertEq(cacher.isEnabled(), enabled, "removal preserves pause state");
        assertEq(cacher.lastTransitionAt(), transition, "removal preserves history");
        assertEq(priceCache.callCount(), 0, "removal never refreshes prices");
    }

    // Scenarios: PCACHER-REMOVE-PAIR-L06.
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
        cacher.removeAssetPair(address(0), address(0));
    }
}
