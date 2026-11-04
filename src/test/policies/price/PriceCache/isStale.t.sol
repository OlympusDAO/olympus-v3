// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheIsStaleTest is PriceCacheTest {
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.isStale(address(assetToken), address(quoteToken), 1 hours);
    }

    function test_whenNoSnapshotExists_returnsTrue() public view {
        bool stale = cache.isStale(address(assetToken), address(quoteToken), 1 hours);
        assertEq(stale, true, "Missing snapshot should be stale");
    }

    function test_whenSnapshotIsFresh_returnsFalse(uint48 maxAge_, uint48 elapsed_) public {
        _cachePair();
        uint48 updatedAt = _cachedPair().updatedAt;

        maxAge_ = uint48(bound(uint256(maxAge_), 1, 365 days));
        elapsed_ = uint48(bound(uint256(elapsed_), 0, maxAge_));

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

        maxAge_ = uint48(bound(uint256(maxAge_), 0, 365 days));
        additionalAge_ = uint48(bound(uint256(additionalAge_), 1, 365 days));

        vm.warp(uint256(updatedAt) + uint256(maxAge_) + uint256(additionalAge_));
        bool stale = cache.isStale(address(assetToken), address(quoteToken), maxAge_);
        assertEq(stale, true, "Snapshot older than maxAge should be stale");
    }

    function test_whenPRICEModuleIsUpgraded_returnsTrue() public {
        _cachePair();
        _upgradePriceModuleAndReconfigure(18);

        bool stale = cache.isStale(address(assetToken), address(quoteToken), 365 days);
        assertEq(stale, true, "Module upgrade should invalidate snapshot and report stale");
    }

    function test_whenUnitOfAccountDecimalsChange_returnsTrueForPairsUsingThatAsset() public {
        address unitOfAccount = _unitOfAccount();
        _setNonContractAssetMetadata(unitOfAccount, 2, "NCA");
        cache.cachePrice(address(assetToken), unitOfAccount);

        _setNonContractAssetMetadata(unitOfAccount, 3, "NCA");

        bool forward = cache.isStale(address(assetToken), unitOfAccount, 365 days);
        bool reverse = cache.isStale(unitOfAccount, address(assetToken), 365 days);

        assertEq(forward, true, "Forward orientation should be stale after decimals change");
        assertEq(reverse, true, "Reverse orientation should be stale after decimals change");
    }

    function test_whenRegisteredNonContractAssetDecimalsChange_returnsTrueForPairsUsingThatAsset()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, 3e18);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");
        cache.cachePrice(address(assetToken), nonContractAsset);

        _setNonContractAssetMetadata(nonContractAsset, 9, "NCA");

        bool forward = cache.isStale(address(assetToken), nonContractAsset, 365 days);
        bool reverse = cache.isStale(nonContractAsset, address(assetToken), 365 days);

        assertEq(forward, true, "Forward orientation should be stale after decimals change");
        assertEq(reverse, true, "Reverse orientation should be stale after decimals change");
    }

    function test_whenUnrelatedNonContractAssetDecimalsChange_existingPairRemainsFresh() public {
        address unitOfAccount = _unitOfAccount();
        address otherNonContractAsset = makeAddr("OTHER_NON_CONTRACT_ASSET");

        _registerNonContractAsset(otherNonContractAsset);
        _setNonContractAssetMetadata(unitOfAccount, 2, "NCA");
        _setNonContractAssetMetadata(otherNonContractAsset, 8, "NCA");
        cache.cachePrice(address(assetToken), unitOfAccount);

        _setNonContractAssetMetadata(otherNonContractAsset, 9, "NCA");

        bool stale = cache.isStale(address(assetToken), unitOfAccount, 365 days);
        assertEq(stale, false, "Unrelated decimals change should not invalidate the pair");
    }

    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        cache.isStale(address(assetToken), address(quoteToken), 1 hours);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
