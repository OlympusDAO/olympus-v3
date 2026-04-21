// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableIsStaleTest is MorphoOracleCloneableTest {
    function test_givenFreshCache_returnsFalse(uint48 warpDelta_) public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, uint48 cachedAt) = priceModule.getPriceIn(
            address(collateralToken),
            address(loanToken),
            IPRICEv2.Variant.LAST
        );
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));
        vm.warp(cachedAt + warpDelta);

        assertEq(oracle.isStale(), false, "Fresh cache should not be stale");
    }

    function test_givenCacheOlderThanMaxAge_returnsTrue(uint48 warpDelta_) public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, uint48 cachedAt) = priceModule.getPriceIn(
            address(collateralToken),
            address(loanToken),
            IPRICEv2.Variant.LAST
        );
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(cachedAt + warpDelta);

        assertEq(oracle.isStale(), true, "Cache older than maxAge should be stale");
    }

    function test_givenOnlyCollateralUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(collateralToken), priceModule.unitOfAccount());

        assertEq(oracle.isStale(), false, "Direct pair freshness should be unchanged");
    }

    function test_givenOnlyLoanUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(loanToken), priceModule.unitOfAccount());

        assertEq(oracle.isStale(), false, "Direct pair freshness should be unchanged");
    }

    function test_gasSnapshot_isStale() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));

        vm.startSnapshotGas("MorphoOracleCloneable.isStale");
        oracle.isStale();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenCollateralTokenRemovedFromPRICE_reverts() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        priceModule.removeAsset(address(collateralToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_AssetNotApproved.selector,
                address(collateralToken)
            )
        );
        oracle.isStale();
    }

    function test_givenLoanTokenRemovedFromPRICE_reverts() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        priceModule.removeAsset(address(loanToken));

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(loanToken))
        );
        oracle.isStale();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
