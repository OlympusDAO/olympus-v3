// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {Actions} from "src/Kernel.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableIsStaleTest is MorphoOracleCloneableTest {
    function test_givenFreshCache_returnsFalse(uint48 warpDelta_) public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 0, DEFAULT_MAX_AGE));
        vm.warp(cachedAt + warpDelta);

        assertEq(oracle.isStale(), false, "Fresh cache should not be stale");
    }

    function test_givenCacheOlderThanMaxAge_returnsTrue(uint48 warpDelta_) public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 cachedAt = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(
            bound(uint256(warpDelta_), DEFAULT_MAX_AGE + 1, DEFAULT_MAX_AGE * 30)
        );
        vm.warp(cachedAt + warpDelta);

        assertEq(oracle.isStale(), true, "Cache older than maxAge should be stale");
    }

    function test_givenOnlyCollateralUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 pairTimestampBefore = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        _setCachePrice(address(collateralToken), 3e18);
        priceCache.cachePrice(address(collateralToken), UNIT_OF_ACCOUNT);
        uint48 pairTimestampAfter = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertEq(
            pairTimestampAfter,
            pairTimestampBefore,
            "Direct pair timestamp should not change when only collateral/USD is refreshed"
        );
        assertEq(oracle.isStale(), false, "Direct pair freshness should be unchanged");
    }

    function test_givenOnlyLoanUsdCacheChanges_returnsFalse(uint48 warpDelta_) public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        uint48 pairTimestampBefore = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;
        uint48 warpDelta = uint48(bound(uint256(warpDelta_), 1, DEFAULT_MAX_AGE));
        vm.warp(block.timestamp + warpDelta);
        _setCachePrice(address(loanToken), 2e18);
        priceCache.cachePrice(address(loanToken), UNIT_OF_ACCOUNT);
        uint48 pairTimestampAfter = priceCache
            .getCachedPrice(address(collateralToken), address(loanToken))
            .updatedAt;

        assertEq(
            pairTimestampAfter,
            pairTimestampBefore,
            "Direct pair timestamp should not change when only loan/USD is refreshed"
        );
        assertEq(oracle.isStale(), false, "Direct pair freshness should be unchanged");
    }

    function test_gasSnapshot_isStale() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));

        vm.startSnapshotGas("MorphoOracleCloneable.isStale");
        oracle.isStale();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_whenPriceCachePolicyIsDeactivated_reverts() public {
        priceCache.setPolicyActive(false);

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        oracle.isStale();
    }

    function test_whenFactoryIsDisabled_reverts() public givenFactoryIsDisabled {
        vm.expectRevert(IMorphoOracle.MorphoOracle_NotEnabled.selector);
        oracle.isStale();
    }

    function test_whenFactoryPolicyIsDeactivated_reverts() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IOracleFactory.OracleFactory_PolicyNotActive.selector);
        oracle.isStale();
    }

    function test_givenCollateralTokenRemovedFromPRICE_reverts() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        priceCache.setAssetApproval(address(collateralToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(_PRICE_ASSET_NOT_APPROVED_SELECTOR, address(collateralToken))
        );
        oracle.isStale();
    }

    function test_givenLoanTokenRemovedFromPRICE_reverts() public {
        priceCache.cachePrice(address(collateralToken), address(loanToken));
        priceCache.setAssetApproval(address(loanToken), false);

        vm.expectRevert(
            abi.encodeWithSelector(_PRICE_ASSET_NOT_APPROVED_SELECTOR, address(loanToken))
        );
        oracle.isStale();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
