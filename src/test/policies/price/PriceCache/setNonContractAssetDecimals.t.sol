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
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

contract PriceCacheSetNonContractAssetDecimalsTest is PriceCacheTest {
    // Scenarios: PCACHE-METADATA-L01.
    function test_givenPolicyDisabled_reverts() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(admin);
        cache.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.setNonContractAssetMetadata(unitOfAccount, 2, "USD2");
    }

    // Scenarios: PCACHE-METADATA-A01.
    function test_givenCallerIsNeitherPriceAdminNorAdmin_reverts(address unauthorised) public {
        vm.assume(unauthorised != admin);
        vm.assume(unauthorised != priceManager);

        address unitOfAccount = _unitOfAccount();

        vm.prank(unauthorised);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        cache.setNonContractAssetMetadata(unitOfAccount, 2, "USD2");
    }

    // Scenarios: PCACHE-METADATA-A02.
    function test_givenCallerIsPriceAdmin_updatesConfiguredMetadata() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(priceManager);
        cache.setNonContractAssetMetadata(unitOfAccount, 2, "USD2");

        assertEq(
            cache.assetDecimals(unitOfAccount),
            2,
            "Unit of account decimals should use the updated cache registry value"
        );
        assertEq(cache.assetSymbol(unitOfAccount), "USD2", "Unit of account symbol should update");
    }

    // Scenarios: PCACHE-METADATA-P01.
    function test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_updatesConfiguredMetadata() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(admin);
        cache.setNonContractAssetMetadata(unitOfAccount, 2, "USD2");

        assertEq(
            cache.assetDecimals(unitOfAccount),
            2,
            "Unit of account decimals should use the updated cache registry value"
        );
        assertEq(cache.assetSymbol(unitOfAccount), "USD2", "Unit of account symbol should update");
    }

    // Scenarios: PCACHE-METADATA-P02.
    function test_givenCallerIsAdmin_givenAssetIsRegisteredNonContractAsset_setsConfiguredMetadata()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        cache.setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        assertEq(
            cache.assetDecimals(nonContractAsset),
            NON_CONTRACT_DECIMALS,
            "Non-contract asset decimals should use the configured cache registry value"
        );
        assertEq(
            cache.assetSymbol(nonContractAsset),
            "NCA",
            "Non-contract asset symbol should use the configured cache value"
        );
    }

    // Scenarios: PCACHE-METADATA-I01.
    function test_givenCallerIsAdmin_givenAssetIsNotRegisteredInPRICE_reverts(
        address nonContractAsset
    ) public {
        vm.assume(nonContractAsset != address(0));
        vm.assume(nonContractAsset != _unitOfAccount());
        vm.assume(nonContractAsset != address(assetToken));
        vm.assume(nonContractAsset != address(quoteToken));
        vm.assume(nonContractAsset.code.length == 0);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IPriceCache.PriceCache_InvalidAsset.selector, nonContractAsset)
        );
        cache.setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");
    }

    // Scenarios: PCACHE-METADATA-I02.
    function test_givenCallerIsAdmin_givenAssetIsERC20_reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidAsset.selector,
                address(assetToken)
            )
        );
        cache.setNonContractAssetMetadata(address(assetToken), 18, "AST");
    }

    // Scenarios: PCACHE-METADATA-I03.
    function test_givenCallerIsAdmin_givenSymbolIsEmpty_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        cache.setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "");
    }

    // Scenarios: PCACHE-METADATA-I04.
    function test_givenCallerIsAdmin_givenSymbolExceedsMaxLength_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        cache.setNonContractAssetMetadata(
            nonContractAsset,
            NON_CONTRACT_DECIMALS,
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567"
        );
    }

    // Scenarios: PCACHE-METADATA-L02.
    function test_givenInactive_whenMetadataSet_reverts() public {
        address unit = _unitOfAccount();
        _deactivateCachePolicy();
        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        vm.prank(admin);
        cache.setNonContractAssetMetadata(unit, 2, "USD2");
    }

    // Scenarios: PCACHE-METADATA-A02.
    function test_givenAdminOnly_whenMetadataSet(address caller_) public {
        vm.assume(caller_ != priceManager);
        _grantMetadataRole(ADMIN_ROLE, caller_);
        _metadataRoleSucceeds(caller_);
    }

    // Scenarios: PCACHE-METADATA-A02.
    function test_givenPriceAdminOnly_whenMetadataSet(address caller_) public {
        vm.assume(caller_ != admin);
        _grantMetadataRole(PRICE_ADMIN_ROLE, caller_);
        _metadataRoleSucceeds(caller_);
    }

    // Scenarios: PCACHE-METADATA-A02.
    function test_givenBothRoles_whenMetadataSet(address caller_) public {
        _grantMetadataRole(ADMIN_ROLE, caller_);
        _grantMetadataRole(PRICE_ADMIN_ROLE, caller_);
        _metadataRoleSucceeds(caller_);
    }

    // Scenarios: PCACHE-METADATA-I05.
    function test_givenPaused_whenInvalidMetadataSet_reverts(
        address caller_
    ) public givenCachePaused {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        cache.setNonContractAssetMetadata(address(0), 0, "");
    }

    // Scenarios: PCACHE-METADATA-I07.
    function test_givenUnauthorised_whenInvalidMetadataSet_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != priceManager);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        cache.setNonContractAssetMetadata(address(0), 0, "");
    }

    // Scenarios: PCACHE-METADATA-I08.
    function test_givenInactive_whenInvalidMetadataSet_reverts() public givenCacheInactive {
        vm.expectRevert(IPriceCache.PriceCache_PolicyNotActive.selector);
        vm.prank(admin);
        cache.setNonContractAssetMetadata(address(0), 0, "");
    }

    // Scenarios: PCACHE-METADATA-I06.
    function test_whenAssetZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPriceCache.PriceCache_InvalidAsset.selector, address(0))
        );
        vm.prank(admin);
        cache.setNonContractAssetMetadata(address(0), 0, "ZERO");
    }

    // Scenarios: PCACHE-METADATA-N01.
    function test_whenMetadataCoversFullDecimalsRange(
        uint8 decimals_,
        bytes memory symbol_
    ) public {
        vm.assume(symbol_.length > 0 && symbol_.length <= 32);
        vm.assume(
            decimals_ != NON_CONTRACT_DECIMALS || keccak256(symbol_) != keccak256(bytes("NCA"))
        );
        _changedMetadataSucceeds(decimals_, string(symbol_));
    }

    // Scenarios: PCACHE-METADATA-N01.
    function test_whenDecimalsZero_whenSymbolOneByte() public {
        _changedMetadataSucceeds(0, "A");
    }

    // Scenarios: PCACHE-METADATA-N01.
    function test_whenDecimalsOne_whenSymbolThirtyTwoBytes() public {
        _changedMetadataSucceeds(1, "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456");
    }

    // Scenarios: PCACHE-METADATA-N01.
    function test_whenDecimalsMaximum_whenSymbolContainsNulls() public {
        _changedMetadataSucceeds(type(uint8).max, string(abi.encodePacked(bytes32(0))));
    }

    // Scenarios: PCACHE-METADATA-P03.
    function test_whenMetadataUnchanged_preservesSnapshotWithoutWritesOrLogs() public {
        address asset = _metadataAsset();
        cache.cachePrice(asset, address(quoteToken));
        IPriceCache.CachedPrice memory beforeSnapshot = cache.getCachedPrice(
            asset,
            address(quoteToken)
        );
        vm.record();
        vm.recordLogs();
        _setNonContractAssetMetadata(asset, NON_CONTRACT_DECIMALS, "NCA");
        (, bytes32[] memory writes) = vm.accesses(address(cache));
        assertEq(writes.length, 0, "same metadata writes no storage");
        assertEq(vm.getRecordedLogs().length, 0, "same metadata emits no events");
        _assertCachedPriceEq(cache.getCachedPrice(asset, address(quoteToken)), beforeSnapshot);
    }

    // Scenarios: PCACHE-METADATA-P07.
    function test_whenOnlySymbolChanged_invalidatesOnlyAffectedPairs() public {
        _changedMetadataSucceeds(NON_CONTRACT_DECIMALS, "NEW");
    }

    // Scenarios: PCACHE-METADATA-P11.
    function test_givenMetadataChanged_whenRecached_advancesExistingRound(address caller_) public {
        address asset = _metadataAsset();
        cache.cachePrice(asset, address(quoteToken));
        _setNonContractAssetMetadata(asset, 9, "NEW");
        vm.prank(caller_);
        IPriceCache.CachedPrice memory snapshot = cache.cachePriceIfNecessary(
            asset,
            address(quoteToken),
            type(uint48).max
        );
        assertEq(snapshot.roundId, 2, "asset invalidation retains existing round counter");
        assertEq(snapshot.assetPriceUsd, 3e18, "asset observation recached");
        assertEq(snapshot.quotePriceUsd, 1e18, "quote observation recached");
        assertEq(cache.assetDecimals(asset), 9, "new decimals used");
        _assertCachedPriceEq(cache.getCachedPrice(asset, address(quoteToken)), snapshot);
    }

    // Scenarios: PCACHE-METADATA-L03.
    function test_givenReEnabled_whenMetadataSet() public givenCacheReEnabled {
        _metadataRoleSucceeds(admin);
    }

    // Scenarios: PCACHE-METADATA-L03.
    function test_givenReactivated_whenMetadataSet() public givenCacheReactivated {
        _metadataRoleSucceeds(admin);
    }

    function _metadataRoleSucceeds(address caller_) internal {
        address asset = _metadataAsset();
        vm.prank(caller_);
        cache.setNonContractAssetMetadata(asset, 9, "NEW");
        assertEq(cache.assetDecimals(asset), 9, "permitted caller updates decimals");
        assertEq(cache.assetSymbol(asset), "NEW", "permitted caller updates symbol");
    }

    function _changedMetadataSucceeds(uint8 decimals_, string memory symbol_) internal {
        address asset = _metadataAsset();
        _cachePair();
        IPriceCache.CachedPrice memory unrelated = _cachedPair();
        cache.cachePrice(asset, address(quoteToken));
        _setNonContractAssetMetadata(asset, decimals_, symbol_);
        assertEq(cache.assetDecimals(asset), decimals_, "full uint8 decimals round trip");
        assertEq(bytes(cache.assetSymbol(asset)), bytes(symbol_), "exact opaque symbol bytes");
        _assertUncached(asset, address(quoteToken));
        _assertUncached(address(quoteToken), asset);
        _assertCachedPriceEq(_cachedPair(), unrelated);
    }

    // Scenarios: PCACHE-METADATA-L04.
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
        cache.setNonContractAssetMetadata(address(0), type(uint8).max, "");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
