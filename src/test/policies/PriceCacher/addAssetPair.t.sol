// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockPriceCacherCache} from "./MockPriceCacherCache.sol";
import {PriceCacherTest} from "./PriceCacherTest.sol";

contract PriceCacherAddAssetPairTest is PriceCacherTest {
    uint256 internal constant _PAIR_COUNT_AFTER_SINGLE_ADD = 3;
    uint256 internal constant _PAIR_COUNT_AFTER_MULTIPLE_ADDS = 4;

    // when caller is not admin
    //  then the call reverts
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        cacher.addAssetPair(alice, usds);
    }

    // when asset is zero
    //  then the call reverts
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(IPriceCacher.PriceCacher_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.addAssetPair(address(0), usds);
    }

    // when quote is zero
    //  then the call reverts
    function test_whenQuoteIsZero_reverts() public {
        vm.expectRevert(IPriceCacher.PriceCacher_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.addAssetPair(ohm, address(0));
    }

    // when asset equals quote
    //  then the call reverts
    function test_whenAssetEqualsQuote_reverts() public {
        vm.expectRevert(IPriceCacher.PriceCacher_InvalidAssetPair.selector);
        vm.prank(admin);
        cacher.addAssetPair(ohm, ohm);
    }

    // given the pair exists
    //  when the asset pair is added
    //   then the call reverts
    function test_givenPairExists_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_AssetPairAlreadyAdded.selector,
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
    function test_givenPairExistsInReverseOrder_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacher.PriceCacher_AssetPairAlreadyAdded.selector,
                usds,
                ohm
            )
        );
        vm.prank(admin);
        cacher.addAssetPair(usds, ohm);
    }

    // when pair is not supported by PriceCache
    //  then the call reverts
    function test_whenPairIsNotSupportedByPriceCache_reverts() public {
        priceCache.setUnsupportedPair(alice, usds);

        vm.expectRevert(
            abi.encodeWithSelector(MockPriceCacherCache.PairUnsupported.selector, alice, usds)
        );
        vm.prank(admin);
        cacher.addAssetPair(alice, usds);
    }

    // given PriceCacher is enabled
    //  when admin adds multiple pairs
    //   then the requested pair is stored
    function test_givenEnabled_whenAdminAddsMultiplePairs() public {
        address secondAsset = makeAddr("secondAsset");

        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacher.AssetPairAdded(alice, usds);
        vm.prank(admin);
        cacher.addAssetPair(alice, usds);
        vm.expectEmit(true, true, false, true, address(cacher));
        emit IPriceCacher.AssetPairAdded(secondAsset, usde);
        vm.prank(admin);
        cacher.addAssetPair(secondAsset, usde);

        IPriceCacher.AssetPair[] memory pairs = cacher.getAssetPairs();
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

    // given PriceCacher is disabled
    //  when admin adds pair
    //   then the requested pair is stored
    function test_givenDisabled_whenAdminAddsPair() public {
        vm.prank(emergency);
        cacher.disable("");

        vm.prank(admin);
        cacher.addAssetPair(alice, usds);

        assertEq(cacher.getAssetPairs().length, _PAIR_COUNT_AFTER_SINGLE_ADD, "pair count");
        assertFalse(cacher.isEnabled(), "cacher should remain disabled");
    }

    // given PriceCacher is re-enabled
    //  when admin adds pair
    //   then the requested pair is stored
    function test_givenReEnabled_whenAdminAddsPair() public {
        vm.prank(emergency);
        cacher.disable("");
        vm.prank(admin);
        cacher.reEnable();

        vm.prank(admin);
        cacher.addAssetPair(alice, usds);

        assertEq(cacher.getAssetPairs().length, _PAIR_COUNT_AFTER_SINGLE_ADD, "pair count");
        assertTrue(cacher.isEnabled(), "cacher should remain enabled");
    }
}
