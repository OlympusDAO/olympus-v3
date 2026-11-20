// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;
import {Actions} from "src/Kernel.sol";

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacheTest} from "./PriceCacheTest.sol";
import {MockStaticMetadataToken} from "./fixtures/MockStaticMetadataToken.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

contract PriceCacheRemoveNonContractAssetDecimalsTest is PriceCacheTest {
    // Scenarios: PCACHE-REMOVE-METADATA-L01.
    function test_givenPolicyDisabled_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        vm.prank(admin);
        cache.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.removeNonContractAssetMetadata(nonContractAsset);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-A01.
    function test_givenCallerIsNeitherPriceAdminNorAdmin_reverts(address unauthorised) public {
        vm.assume(unauthorised != admin);
        vm.assume(unauthorised != priceManager);

        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        vm.prank(unauthorised);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        cache.removeNonContractAssetMetadata(nonContractAsset);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-P01.
    function test_givenCallerIsPriceAdminOrAdmin_givenAssetIsRegisteredNonContractAsset_removesConfiguredScale(
        bool usePriceAdmin_
    ) public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        vm.prank(usePriceAdmin_ ? priceManager : admin);
        cache.removeNonContractAssetMetadata(nonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nonContractAsset
            )
        );
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.assetDecimals(nonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered.selector,
                nonContractAsset
            )
        );
        // The expected revert makes the return value unreachable.
        // forge-lint: disable-next-line(unused-return)
        cache.assetSymbol(nonContractAsset);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-I01.
    function test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_reverts() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IPriceCache.PriceCache_InvalidAsset.selector, unitOfAccount)
        );
        cache.removeNonContractAssetMetadata(unitOfAccount);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-I02.
    function test_givenCallerIsAdmin_givenAssetDoesNotHaveRegisteredDecimals_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nonContractAsset
            )
        );
        cache.removeNonContractAssetMetadata(nonContractAsset);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-I03.
    function test_givenCallerIsAdmin_givenAssetIsERC20_reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                address(assetToken)
            )
        );
        cache.removeNonContractAssetMetadata(address(assetToken));
    }

    // Scenarios: PCACHE-REMOVE-METADATA-P02.
    function test_givenCallerIsAdmin_givenNcaDecimalsAreRegistered_thenErc20IsDeployed_removesConfiguredScale()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        MockStaticMetadataToken tokenWithDifferentDecimals = new MockStaticMetadataToken();
        vm.etch(nonContractAsset, address(tokenWithDifferentDecimals).code);

        vm.prank(admin);
        cache.removeNonContractAssetMetadata(nonContractAsset);

        assertEq(
            cache.assetDecimals(nonContractAsset),
            6,
            "Contract decimals should still be returned after removing the stale non-contract entry"
        );
        assertEq(
            cache.assetSymbol(nonContractAsset),
            "LATE",
            "Contract symbol should still be returned after removing the stale non-contract entry"
        );
    }

    // Scenarios: PCACHE-REMOVE-METADATA-L02.
    function test_givenInactive_whenMetadataRemoved_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");
        _deactivateCachePolicy();
        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        vm.prank(admin);
        cache.removeNonContractAssetMetadata(nonContractAsset);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-P01.
    function test_givenAdminOnly_whenMetadataRemoved(address caller_) public {
        vm.assume(caller_ != priceManager);
        _grantMetadataRole(ADMIN_ROLE, caller_);
        _metadataRemovalSucceeds(caller_);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-P01.
    function test_givenPriceAdminOnly_whenMetadataRemoved(address caller_) public {
        vm.assume(caller_ != admin);
        _grantMetadataRole(PRICE_ADMIN_ROLE, caller_);
        _metadataRemovalSucceeds(caller_);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-P01.
    function test_givenBothRoles_whenMetadataRemoved(address caller_) public {
        _grantMetadataRole(ADMIN_ROLE, caller_);
        _grantMetadataRole(PRICE_ADMIN_ROLE, caller_);
        _metadataRemovalSucceeds(caller_);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-I04.
    function test_givenAlreadyRemoved_whenMetadataRemoved_revertsWithoutWrites() public {
        address asset = _metadataAsset();
        _removeNonContractAssetMetadata(asset);
        vm.record();
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                asset
            )
        );
        _removeNonContractAssetMetadata(asset);
        (, bytes32[] memory writes) = vm.accesses(address(cache));
        assertEq(writes.length, 0, "repeated removal changes no metadata or epochs");
    }

    // Scenarios: PCACHE-REMOVE-METADATA-P03.
    function test_givenMetadataRemoved_whenPairsQueried_revertsUntilRestored() public {
        address asset = _metadataAsset();
        _cachePair();
        IPriceCache.CachedPrice memory unrelated = _cachedPair();
        cache.cachePrice(asset, address(quoteToken));
        _removeNonContractAssetMetadata(asset);
        bytes memory expected = abi.encodeWithSelector(
            IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
            asset
        );
        _assertPairReadReverts(
            abi.encodeCall(cache.getCachedPrice, (asset, address(quoteToken))),
            expected
        );
        _assertPairReadReverts(
            abi.encodeCall(cache.getCachedPrice, (address(quoteToken), asset)),
            expected
        );
        _assertPairReadReverts(
            abi.encodeCall(cache.isStale, (asset, address(quoteToken), type(uint48).max)),
            expected
        );
        _assertPairReadReverts(
            abi.encodeCall(cache.isStale, (address(quoteToken), asset, type(uint48).max)),
            expected
        );
        vm.expectRevert(expected);
        cache.cachePrice(asset, address(quoteToken));
        vm.expectRevert(expected);
        cache.cachePrice(address(quoteToken), asset);
        _assertCachedPriceEq(_cachedPair(), unrelated);
        _setNonContractAssetMetadata(asset, NON_CONTRACT_DECIMALS, "NCA");
        _assertUncached(asset, address(quoteToken));
        _assertUncached(address(quoteToken), asset);
        assertTrue(
            cache.isStale(asset, address(quoteToken), type(uint48).max),
            "restoring metadata never resurrects old snapshot"
        );
        IPriceCache.CachedPrice memory snapshot = cache.cachePriceIfNecessary(
            asset,
            address(quoteToken),
            type(uint48).max
        );
        assertEq(snapshot.roundId, 2, "restoration recaches using existing round counter");
        _assertCachedPriceEq(_cachedPair(), unrelated);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-L03.
    function test_givenReEnabled_whenMetadataRemoved() public givenCacheReEnabled {
        _metadataRemovalSucceeds(admin);
    }

    // Scenarios: PCACHE-REMOVE-METADATA-L03.
    function test_givenReactivated_whenMetadataRemoved() public givenCacheReactivated {
        _metadataRemovalSucceeds(admin);
    }

    function _metadataRemovalSucceeds(address caller_) internal {
        address asset = _metadataAsset();
        vm.prank(caller_);
        cache.removeNonContractAssetMetadata(asset);
        _assertPairReadReverts(
            abi.encodeCall(cache.assetDecimals, (asset)),
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                asset
            )
        );
        _assertPairReadReverts(
            abi.encodeCall(cache.assetSymbol, (asset)),
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered.selector,
                asset
            )
        );
    }

    function _assertPairReadReverts(bytes memory call_, bytes memory expected_) internal view {
        (bool success, bytes memory result) = address(cache).staticcall(call_);
        assertFalse(success, "metadata-dependent read must revert");
        assertEq(result, expected_, "exact missing-metadata error");
    }

    // Scenarios: PCACHE-REMOVE-METADATA-L04.
    function test_givenInactiveAndDisabled_whenAnyCallerChangesMetadata_revertsActivityFirst(
        address caller_
    ) public {
        vm.startPrank(admin);
        cache.disable("");
        vm.stopPrank();
        vm.startPrank(kernel.executor());
        kernel.executeAction(Actions.DeactivatePolicy, address(cache));
        vm.stopPrank();
        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        vm.prank(caller_);
        cache.removeNonContractAssetMetadata(address(0));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
