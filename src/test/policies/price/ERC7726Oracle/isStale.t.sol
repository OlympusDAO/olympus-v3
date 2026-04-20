// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";

contract ERC7726OracleIsStaleTest is ERC7726OracleTest {
    function test_givenFreshCache_returnsFalse(uint48 warpDelta_) public {
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));
        vm.warp(cachedAt + warpDelta);

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Fresh cache should not be stale");
    }

    function test_givenCacheOlderThanMaxAge_returnsTrue(uint48 warpDelta_) public {
        uint48 cachedAt = uint48(block.timestamp);
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(cachedAt + warpDelta);

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, true, "Cache older than maxAge should be stale");
    }

    function test_givenOnlyBaseUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(collateralToken), priceModule.unitOfAccount());

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Direct pair freshness should be unchanged");
    }

    function test_givenOnlyQuoteUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(loanToken), priceModule.unitOfAccount());

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Direct pair freshness should be unchanged");
    }

    function test_givenBaseAndQuoteUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        priceModule.cachePrice(address(collateralToken), priceModule.unitOfAccount());
        priceModule.cachePrice(address(loanToken), priceModule.unitOfAccount());

        bool stale = oracle.isStale(address(collateralToken), address(loanToken));
        assertEq(stale, false, "Direct pair freshness should be unchanged");
    }

    function test_gasSnapshot_isStale() public {
        vm.startSnapshotGas("ERC7726OracleCloneable.isStale");
        oracle.isStale(address(collateralToken), address(loanToken));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenBaseAssetIsNotApproved_reverts() public {
        address unapprovedBase = makeAddr("UNAPPROVED_BASE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedBase)
        );
        oracle.isStale(unapprovedBase, address(loanToken));
    }

    function test_givenQuoteAssetIsNotApproved_reverts() public {
        address unapprovedQuote = makeAddr("UNAPPROVED_QUOTE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedQuote)
        );
        oracle.isStale(address(collateralToken), unapprovedQuote);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
