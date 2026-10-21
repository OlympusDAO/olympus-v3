// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheIsStaleTest is PriceCacheTest {
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.isStale(address(assetToken), address(quoteToken), SHORT_MAX_AGE);
    }

    function test_whenNoSnapshotExists_returnsTrue() public view {
        bool stale = cache.isStale(address(assetToken), address(quoteToken), SHORT_MAX_AGE);
        assertEq(stale, true, "Missing snapshot should be stale");
    }

    function test_whenSnapshotIsFresh_returnsFalse(uint48 maxAge_, uint48 elapsed_) public {
        _cachePair();
        uint48 updatedAt = _cachedPair().updatedAt;

        maxAge_ = SafeCast.toUint48(bound(uint256(maxAge_), 1, LONG_MAX_AGE));
        elapsed_ = SafeCast.toUint48(bound(uint256(elapsed_), 0, maxAge_));

        vm.warp(uint256(updatedAt) + uint256(elapsed_));
        bool stale = cache.isStale(address(assetToken), address(quoteToken), maxAge_);
        assertEq(stale, false, "Fresh snapshot should not be stale");
    }

    function test_whenSnapshotIsOlderThanMaxAge_returnsTrue(
        uint48 maxAge_,
        uint48 additionalAge_
    ) public {
        _cachePair();
        uint48 updatedAt = _cachedPair().updatedAt;

        maxAge_ = SafeCast.toUint48(bound(uint256(maxAge_), 0, LONG_MAX_AGE));
        additionalAge_ = SafeCast.toUint48(bound(uint256(additionalAge_), 1, LONG_MAX_AGE));

        vm.warp(uint256(updatedAt) + uint256(maxAge_) + uint256(additionalAge_));
        bool stale = cache.isStale(address(assetToken), address(quoteToken), maxAge_);
        assertEq(stale, true, "Snapshot older than maxAge should be stale");
    }

    function test_whenPRICEModuleIsUpgraded_returnsTrue() public {
        _cachePair();
        _upgradePriceModuleAndReconfigure(18);

        bool stale = cache.isStale(address(assetToken), address(quoteToken), LONG_MAX_AGE);
        assertEq(stale, true, "Module upgrade should invalidate snapshot and report stale");
    }

    function test_whenUnitOfAccountDecimalsChange_returnsTrueForPairsUsingThatAsset() public {
        address unitOfAccount = _unitOfAccount();
        _setNonContractAssetMetadata(unitOfAccount, 2, "NCA");
        cache.cachePrice(address(assetToken), unitOfAccount);

        _setNonContractAssetMetadata(unitOfAccount, 3, "NCA");

        bool forward = cache.isStale(address(assetToken), unitOfAccount, LONG_MAX_AGE);
        bool reverse = cache.isStale(unitOfAccount, address(assetToken), LONG_MAX_AGE);

        assertEq(forward, true, "Forward orientation should be stale after decimals change");
        assertEq(reverse, true, "Reverse orientation should be stale after decimals change");
    }

    function test_whenRegisteredNonContractAssetDecimalsChange_returnsTrueForPairsUsingThatAsset()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, NON_CONTRACT_PRICE_USD);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");
        cache.cachePrice(address(assetToken), nonContractAsset);

        _setNonContractAssetMetadata(nonContractAsset, UPDATED_NON_CONTRACT_DECIMALS, "NCA");

        bool forward = cache.isStale(address(assetToken), nonContractAsset, LONG_MAX_AGE);
        bool reverse = cache.isStale(nonContractAsset, address(assetToken), LONG_MAX_AGE);

        assertEq(forward, true, "Forward orientation should be stale after decimals change");
        assertEq(reverse, true, "Reverse orientation should be stale after decimals change");
    }

    function test_whenUnrelatedNonContractAssetDecimalsChange_existingPairRemainsFresh() public {
        address unitOfAccount = _unitOfAccount();
        address otherNonContractAsset = makeAddr("OTHER_NON_CONTRACT_ASSET");

        _registerNonContractAsset(otherNonContractAsset);
        _setNonContractAssetMetadata(unitOfAccount, 2, "NCA");
        _setNonContractAssetMetadata(otherNonContractAsset, NON_CONTRACT_DECIMALS, "NCA");
        cache.cachePrice(address(assetToken), unitOfAccount);

        _setNonContractAssetMetadata(otherNonContractAsset, UPDATED_NON_CONTRACT_DECIMALS, "NCA");

        bool stale = cache.isStale(address(assetToken), unitOfAccount, LONG_MAX_AGE);
        assertEq(stale, false, "Unrelated decimals change should not invalidate the pair");
    }

    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.isStale(address(assetToken), address(quoteToken), SHORT_MAX_AGE);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
