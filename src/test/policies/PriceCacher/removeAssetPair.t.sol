// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {PriceCacherTest} from "./PriceCacherTest.sol";

contract PriceCacherRemoveAssetPairTest is PriceCacherTest {
    // when caller is not admin
    //  then the call reverts
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        cacher.removeAssetPair(ohm, usds);
    }

    // when asset is zero
    //  then the call reverts
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(IPriceCacher.PriceCacher_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.removeAssetPair(address(0), usds);
    }

    // when quote is zero
    //  then the call reverts
    function test_whenQuoteIsZero_reverts() public {
        vm.expectRevert(IPriceCacher.PriceCacher_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.removeAssetPair(ohm, address(0));
    }

    // when asset equals quote
    //  then the call reverts
    function test_whenAssetEqualsQuote_reverts() public {
        vm.expectRevert(IPriceCacher.PriceCacher_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.removeAssetPair(ohm, ohm);
    }

    // when pair does not exist
    //  then the call reverts
    function test_whenPairDoesNotExist_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPriceCacher.PriceCacher_AssetPairNotFound.selector, alice, usds)
        );
        vm.prank(admin);
        cacher.removeAssetPair(alice, usds);
    }

    // given the pair is no longer supported
    //  when admin removes pair
    //   then the matching pair is removed
    function test_givenPairIsNoLongerSupported_whenAdminRemovesPair() public {
        priceCache.setUnsupportedPair(ohm, usds);

        vm.prank(admin);
        cacher.removeAssetPair(ohm, usds);

        assertEq(cacher.getAssetPairs().length, 1, "pair count");
    }

    // given the pair exists in reverse order
    //  when admin removes pair
    //   then the matching pair is removed
    function test_givenPairExistsInReverseOrder_whenAdminRemovesPair() public {
        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacher.AssetPairRemoved(ohm, usds);
        vm.prank(admin);
        cacher.removeAssetPair(usds, ohm);

        IPriceCacher.AssetPair[] memory pairs = cacher.getAssetPairs();
        assertEq(pairs.length, 1, "pair count");
        assertEq(pairs[0].asset, ohm, "remaining asset");
        assertEq(pairs[0].quote, usde, "remaining quote");
    }

    // given multiple entries exist
    //  when admin removes multiple pairs
    //   then the matching pair is removed
    function test_givenMultipleEntries_whenAdminRemovesMultiplePairs() public {
        address secondAsset = makeAddr("secondAsset");
        vm.startPrank(admin);
        cacher.addAssetPair(alice, usds);
        cacher.addAssetPair(secondAsset, usde);

        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacher.AssetPairRemoved(ohm, usds);
        cacher.removeAssetPair(ohm, usds);
        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacher.AssetPairRemoved(alice, usds);
        cacher.removeAssetPair(alice, usds);
        vm.stopPrank();

        IPriceCacher.AssetPair[] memory pairs = cacher.getAssetPairs();
        assertEq(pairs.length, 2, "pair count");
        assertEq(pairs[0].asset, secondAsset, "remaining asset");
        assertEq(pairs[0].quote, usde, "remaining quote");
        assertEq(pairs[1].asset, ohm, "second remaining asset");
        assertEq(pairs[1].quote, usde, "second remaining quote");
    }

    // given PriceCacher is disabled
    //  when admin removes pair
    //   then the matching pair is removed
    function test_givenDisabled_whenAdminRemovesPair() public {
        vm.prank(emergency);
        cacher.disable("");

        vm.prank(admin);
        cacher.removeAssetPair(ohm, usds);

        assertEq(cacher.getAssetPairs().length, 1, "pair count");
        assertFalse(cacher.isEnabled(), "cacher should remain disabled");
    }

    // given PriceCacher is re-enabled
    //  when admin removes pair
    //   then the matching pair is removed
    function test_givenReEnabled_whenAdminRemovesPair() public {
        vm.prank(emergency);
        cacher.disable("");
        vm.prank(admin);
        cacher.reEnable();

        vm.prank(admin);
        cacher.removeAssetPair(ohm, usds);

        assertEq(cacher.getAssetPairs().length, 1, "pair count");
        assertTrue(cacher.isEnabled(), "cacher should remain enabled");
    }

    // given one pair remains
    //  when admin removes pair
    //   then it allows an empty configuration
    function test_givenOnePair_whenAdminRemovesPair_allowsEmptyConfiguration() public {
        vm.startPrank(admin);
        cacher.removeAssetPair(ohm, usds);
        cacher.removeAssetPair(ohm, usde);
        vm.stopPrank();

        assertEq(cacher.getAssetPairs().length, 0, "pair count");
    }
}
