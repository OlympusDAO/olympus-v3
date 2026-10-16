// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheValidateAssetPairTest is PriceCacheTest {
    // when asset is zero
    //  then the call reverts
    function test_whenAssetIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(0),
                address(quoteToken)
            )
        );
        cache.validateAssetPair(address(0), address(quoteToken));
    }

    // when quote is zero
    //  then the call reverts
    function test_whenQuoteIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(0)
            )
        );
        cache.validateAssetPair(address(assetToken), address(0));
    }

    // when asset equals quote
    //  then the call reverts
    function test_whenAssetEqualsQuote_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(assetToken)
            )
        );
        cache.validateAssetPair(address(assetToken), address(assetToken));
    }

    // when asset is not approved
    //  then the call reverts
    function test_whenAssetIsNotApproved_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.validateAssetPair(unapprovedAsset, address(quoteToken));
    }

    // when quote is not approved
    //  then the call reverts
    function test_whenQuoteIsNotApproved_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        cache.validateAssetPair(address(assetToken), unapprovedAsset);
    }

    // when an approved non-contract asset has no cache decimals
    //  then the call reverts
    function test_whenApprovedNonContractAssetHasNoCacheDecimals_reverts() public {
        _registerNonContractAsset(unapprovedAsset);
        priceModule.setPrice(unapprovedAsset, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                unapprovedAsset
            )
        );
        cache.validateAssetPair(unapprovedAsset, address(quoteToken));
    }

    // given PriceCache is disabled
    //  when pair is supported
    //   then validation succeeds
    function test_givenCacheIsDisabled_whenPairIsSupported() public {
        vm.prank(admin);
        cache.disable("");

        cache.validateAssetPair(address(assetToken), address(quoteToken));
    }

    // given PriceCache is inactive
    //  when pair is supported
    //   then validation succeeds
    function test_givenCacheIsInactive_whenPairIsSupported() public {
        _deactivateCachePolicy();

        cache.validateAssetPair(address(assetToken), address(quoteToken));
    }

    // when caller is arbitrary
    //  when pair is supported
    //   then validation succeeds
    function test_whenCallerIsArbitrary_whenPairIsSupported(address caller_) public {
        vm.prank(caller_);
        cache.validateAssetPair(address(assetToken), address(quoteToken));
    }
}
