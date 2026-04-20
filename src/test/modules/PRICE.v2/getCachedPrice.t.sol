// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {PriceV2BaseTest} from "src/test/modules/PRICE.v2/PriceV2BaseTest.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

contract PriceV2GetCachedPriceTest is PriceV2BaseTest {
    address internal constant _UNIT_OF_ACCOUNT = address(840);

    function setUp() public override {
        super.setUp();
        _addBaseAssets(0);
    }

    function test_givenAssetNotApproved_reverts() public {
        address unapproved = makeAddr("unapprovedAsset");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapproved)
        );
        price.getCachedPrice(unapproved, address(reserve));
    }

    function test_givenQuoteAssetNotApproved_reverts() public {
        address unapproved = makeAddr("unapprovedQuote");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapproved)
        );
        price.getCachedPrice(address(reserve), unapproved);
    }

    function test_givenAssetIsZeroAddress_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(0))
        );
        price.getCachedPrice(address(0), address(reserve));
    }

    function test_givenQuoteIsZeroAddress_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(0))
        );
        price.getCachedPrice(address(reserve), address(0));
    }

    function test_whenPairIsUncached_returnsZeroValues() public view {
        (uint256 assetPriceUsd, uint256 quotePriceUsd, uint48 updatedAt, uint80 roundId) = price
            .getCachedPrice(address(ohm), address(reserve));

        assertEq(assetPriceUsd, 0, "Asset USD leg should be zero");
        assertEq(quotePriceUsd, 0, "Quote USD leg should be zero");
        assertEq(updatedAt, 0, "Timestamp should be zero");
        assertEq(roundId, 0, "Round ID should be zero");
    }

    function test_whenPairIsCached_returnsRequestedOrientation() public {
        (uint256 ohmUsd, ) = price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
        (uint256 reserveUsd, ) = price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);

        vm.prank(priceWriter);
        price.cachePrice(address(ohm), address(reserve));

        (uint256 assetPriceUsd, uint256 quotePriceUsd, uint48 updatedAt, uint80 roundId) = price
            .getCachedPrice(address(ohm), address(reserve));

        assertEq(assetPriceUsd, ohmUsd, "Asset USD leg mismatch");
        assertEq(quotePriceUsd, reserveUsd, "Quote USD leg mismatch");
        assertEq(updatedAt, uint48(block.timestamp), "Timestamp mismatch");
        assertEq(roundId, 1, "Round ID mismatch");
    }

    function test_whenRequestedOrientationIsReversed_returnsReversedLegs() public {
        (uint256 ohmUsd, ) = price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
        (uint256 reserveUsd, ) = price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);

        vm.prank(priceWriter);
        price.cachePrice(address(ohm), address(reserve));

        (uint256 assetPriceUsd, uint256 quotePriceUsd, uint48 updatedAt, uint80 roundId) = price
            .getCachedPrice(address(reserve), address(ohm));

        assertEq(assetPriceUsd, reserveUsd, "Reversed asset USD leg mismatch");
        assertEq(quotePriceUsd, ohmUsd, "Reversed quote USD leg mismatch");
        assertEq(updatedAt, uint48(block.timestamp), "Timestamp mismatch");
        assertEq(roundId, 1, "Round ID mismatch");
    }

    function test_whenAddressOrderingDiffers_lowerToHigherOrientationFollowsParameters() public {
        address lower = address(ohm) < address(reserve) ? address(ohm) : address(reserve);
        address higher = lower == address(ohm) ? address(reserve) : address(ohm);

        (uint256 ohmUsd, ) = price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
        (uint256 reserveUsd, ) = price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);

        vm.prank(priceWriter);
        price.cachePrice(address(ohm), address(reserve));

        (uint256 lowerAssetPriceUsd, uint256 higherQuotePriceUsd, , ) = price.getCachedPrice(
            lower,
            higher
        );

        if (lower == address(ohm)) {
            assertEq(
                lowerAssetPriceUsd,
                ohmUsd,
                "Lower-address asset leg should follow parameters"
            );
            assertEq(
                higherQuotePriceUsd,
                reserveUsd,
                "Higher-address quote leg should follow parameters"
            );
        } else {
            assertEq(
                lowerAssetPriceUsd,
                reserveUsd,
                "Lower-address asset leg should follow parameters"
            );
            assertEq(
                higherQuotePriceUsd,
                ohmUsd,
                "Higher-address quote leg should follow parameters"
            );
        }
    }

    function test_whenAddressOrderingDiffers_higherToLowerOrientationFollowsParameters() public {
        address lower = address(ohm) < address(reserve) ? address(ohm) : address(reserve);
        address higher = lower == address(ohm) ? address(reserve) : address(ohm);

        (uint256 ohmUsd, ) = price.getPrice(address(ohm), IPRICEv2.Variant.CURRENT);
        (uint256 reserveUsd, ) = price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);

        vm.prank(priceWriter);
        price.cachePrice(address(ohm), address(reserve));

        (, , uint48 firstTimestamp, uint80 firstRoundId) = price.getCachedPrice(lower, higher);
        (
            uint256 higherAssetPriceUsd,
            uint256 lowerQuotePriceUsd,
            uint48 secondTimestamp,
            uint80 secondRoundId
        ) = price.getCachedPrice(higher, lower);

        if (higher == address(ohm)) {
            assertEq(
                higherAssetPriceUsd,
                ohmUsd,
                "Higher-address asset leg should follow parameters"
            );
            assertEq(
                lowerQuotePriceUsd,
                reserveUsd,
                "Lower-address quote leg should follow parameters"
            );
        } else {
            assertEq(
                higherAssetPriceUsd,
                reserveUsd,
                "Higher-address asset leg should follow parameters"
            );
            assertEq(
                lowerQuotePriceUsd,
                ohmUsd,
                "Lower-address quote leg should follow parameters"
            );
        }
        assertEq(
            firstTimestamp,
            secondTimestamp,
            "Both orientations should share one cache entry timestamp"
        );
        assertEq(
            firstRoundId,
            secondRoundId,
            "Both orientations should share one cache entry round ID"
        );
    }

    function test_givenAssetEqualsQuote_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsPairInvalid.selector,
                address(ohm),
                address(ohm)
            )
        );
        price.getCachedPrice(address(ohm), address(ohm));
    }

    function test_givenUnitOfAccountEqualsQuote_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_ParamsPairInvalid.selector,
                _UNIT_OF_ACCOUNT,
                _UNIT_OF_ACCOUNT
            )
        );
        price.getCachedPrice(_UNIT_OF_ACCOUNT, _UNIT_OF_ACCOUNT);
    }

    function test_whenQuoteIsUnitOfAccount_returnsAssetLegAndQuoteLeg() public {
        (uint256 reserveUsd, ) = price.getPrice(address(reserve), IPRICEv2.Variant.CURRENT);
        (, , , uint80 roundIdBefore) = price.getCachedPrice(_UNIT_OF_ACCOUNT, address(reserve));

        vm.prank(priceWriter);
        price.cachePrice(address(reserve), _UNIT_OF_ACCOUNT);

        (uint256 assetPriceUsd, uint256 quotePriceUsd, uint48 updatedAt, uint80 roundId) = price
            .getCachedPrice(_UNIT_OF_ACCOUNT, address(reserve));

        assertEq(assetPriceUsd, 10 ** price.decimals(), "Asset leg should equal the unit price");
        assertEq(quotePriceUsd, reserveUsd, "Quote leg should equal the reserve USD price");
        assertEq(updatedAt, uint48(block.timestamp), "Timestamp mismatch");
        assertEq(roundId, roundIdBefore + 1, "Round ID mismatch");
    }
}
