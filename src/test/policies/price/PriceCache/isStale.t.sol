// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheIsStaleTest is PriceCacheTest {
    function _stalenessBoundary(uint48 age_) private {
        uint256 checkpoint = vm.snapshotState();
        priceModule.setTimestamp(1);
        _cachePair();
        vm.warp(1);
        assertFalse(
            cache.isStale(address(assetToken), address(quoteToken), age_),
            "observation time fresh"
        );
        vm.warp(uint256(age_) + 1);
        assertFalse(
            cache.isStale(address(assetToken), address(quoteToken), age_),
            "exact deadline fresh"
        );
        vm.warp(uint256(age_) + 2);
        assertTrue(
            cache.isStale(address(assetToken), address(quoteToken), age_),
            "next instant stale"
        );
        assertTrue(vm.revertToStateAndDelete(checkpoint), "restore independent boundary fixture");
    }

    // Scenarios: PCACHE-STALE-L01.
    function test_whenPolicyDisabled_reverts() public {
        vm.prank(admin);
        cache.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.isStale(address(assetToken), address(quoteToken), SHORT_MAX_AGE);
    }

    // Scenarios: PCACHE-STALE-P01.
    function test_whenNoSnapshotExists_returnsTrue() public view {
        bool stale = cache.isStale(address(assetToken), address(quoteToken), SHORT_MAX_AGE);
        assertEq(stale, true, "Missing snapshot should be stale");
    }

    // Scenarios: PCACHE-STALE-P02.
    function test_whenPRICEModuleIsUpgraded_returnsTrue() public {
        _cachePair();
        _upgradePriceModuleAndReconfigure(18);

        bool stale = cache.isStale(address(assetToken), address(quoteToken), LONG_MAX_AGE);
        assertEq(stale, true, "Module upgrade should invalidate snapshot and report stale");
    }

    // Scenarios: PCACHE-METADATA-P08.
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

    // Scenarios: PCACHE-METADATA-P09.
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

    // Scenarios: PCACHE-METADATA-P10.
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

    // Scenarios: PCACHE-STALE-L02.
    function test_whenPolicyIsDeactivated_reverts() public {
        _deactivateCachePolicy();

        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.isStale(address(assetToken), address(quoteToken), SHORT_MAX_AGE);
    }

    // Scenarios: PCACHE-STALE-I01.
    function test_whenAssetZero_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(0),
                address(quoteToken)
            )
        );
        vm.prank(caller_);
        cache.isStale(address(0), address(quoteToken), 0);
    }

    // Scenarios: PCACHE-STALE-I02.
    function test_whenQuoteZero_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(0)
            )
        );
        vm.prank(caller_);
        cache.isStale(address(assetToken), address(0), 0);
    }

    // Scenarios: PCACHE-STALE-I03.
    function test_whenSamePair_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidPair.selector,
                address(assetToken),
                address(assetToken)
            )
        );
        vm.prank(caller_);
        cache.isStale(address(assetToken), address(assetToken), 0);
    }

    // Scenarios: PCACHE-STALE-I04.
    function test_whenAssetUnapproved_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        vm.prank(caller_);
        cache.isStale(unapprovedAsset, address(quoteToken), 0);
    }

    // Scenarios: PCACHE-STALE-I05.
    function test_whenQuoteUnapproved_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedAsset)
        );
        vm.prank(caller_);
        cache.isStale(address(assetToken), unapprovedAsset, 0);
    }

    // Scenarios: PCACHE-STALE-I06.
    function test_whenAssetMetadataMissing_reverts(address caller_) public {
        address nca = makeAddr("MISSING_METADATA");
        _registerNonContractAsset(nca);
        priceModule.setPrice(nca, 3e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nca
            )
        );
        vm.prank(caller_);
        cache.isStale(nca, address(quoteToken), 0);
    }

    // Scenarios: PCACHE-STALE-I07.
    function test_whenQuoteMetadataMissing_reverts(address caller_) public {
        address nca = makeAddr("MISSING_METADATA");
        _registerNonContractAsset(nca);
        priceModule.setPrice(nca, 3e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nca
            )
        );
        vm.prank(caller_);
        cache.isStale(address(assetToken), nca, 0);
    }

    // Scenarios: PCACHE-STALE-N01.
    function test_whenFullUint48AgeIsFresh(
        address caller_,
        uint48 at_,
        uint48 age_,
        uint48 elapsed_
    ) public {
        uint48 observedAt = SafeCast.toUint48(bound(at_, 1, type(uint48).max));
        priceModule.setTimestamp(observedAt);
        _cachePair();
        vm.warp(uint256(observedAt) + bound(elapsed_, 0, age_));
        vm.prank(caller_);
        assertFalse(
            cache.isStale(address(assetToken), address(quoteToken), age_),
            "inclusive full-range freshness"
        );
    }

    // Scenarios: PCACHE-STALE-N02.
    function test_whenFullUint48AgeIsStale(address caller_, uint48 age_, uint256 now_) public {
        priceModule.setTimestamp(1);
        _cachePair();
        vm.warp(bound(now_, uint256(age_) + 2, type(uint256).max));
        vm.prank(caller_);
        assertTrue(
            cache.isStale(address(assetToken), address(quoteToken), age_),
            "full stale interval including maximum age"
        );
    }

    // Scenarios: PCACHE-STALE-L03.
    function test_givenReEnabled_whenStalenessQueried(address caller_) public givenCacheReEnabled {
        _cachePair();
        vm.prank(caller_);
        assertFalse(
            cache.isStale(address(assetToken), address(quoteToken), 0),
            "current observation fresh after restoration"
        );
        assertEq(_cachedPair().roundId, 1, "query preserves snapshot");
    }

    // Scenarios: PCACHE-STALE-L03.
    function test_givenReactivated_whenStalenessQueried(
        address caller_
    ) public givenCacheReactivated {
        _cachePair();
        vm.prank(caller_);
        assertFalse(
            cache.isStale(address(assetToken), address(quoteToken), 0),
            "current observation fresh after restoration"
        );
        assertEq(_cachedPair().roundId, 1, "query preserves snapshot");
    }

    // Scenarios: PCACHE-STALE-N01, PCACHE-STALE-N02, PCACHE-STALE-N03.
    function test_whenAgeBoundarySeeds() public {
        _stalenessBoundary(0);
        _stalenessBoundary(1);
        _stalenessBoundary(type(uint48).max);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
