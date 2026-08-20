// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

import {PriceCacheTest} from "./PriceCacheTest.sol";

contract MockStaticMetadataTokenRemove {
    function symbol() external pure returns (string memory) {
        return "LATE";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}

contract PriceCacheRemoveNonContractAssetDecimalsTest is PriceCacheTest {
    function test_givenPolicyDisabled_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");

        vm.prank(admin);
        cache.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.removeNonContractAssetMetadata(nonContractAsset);
    }

    function testFuzz_givenCallerIsNeitherPriceAdminNorAdmin_reverts(address unauthorised) public {
        vm.assume(unauthorised != admin);
        vm.assume(unauthorised != priceManager);

        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");

        vm.prank(unauthorised);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        cache.removeNonContractAssetMetadata(nonContractAsset);
    }

    function testFuzz_givenCallerIsPriceAdminOrAdmin_givenAssetIsRegisteredNonContractAsset_removesConfiguredScale(
        bool usePriceAdmin_
    ) public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");

        vm.prank(usePriceAdmin_ ? priceManager : admin);
        cache.removeNonContractAssetMetadata(nonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nonContractAsset
            )
        );
        cache.assetDecimals(nonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered.selector,
                nonContractAsset
            )
        );
        cache.assetSymbol(nonContractAsset);
    }

    function test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_reverts() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IPriceCache.PriceCache_InvalidAsset.selector, unitOfAccount)
        );
        cache.removeNonContractAssetMetadata(unitOfAccount);
    }

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

    function test_givenCallerIsAdmin_givenNcaDecimalsAreRegistered_thenErc20IsDeployed_removesConfiguredScale()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");

        MockStaticMetadataTokenRemove tokenWithDifferentDecimals = new MockStaticMetadataTokenRemove();
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
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
