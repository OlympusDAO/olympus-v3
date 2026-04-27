// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheSetNonContractAssetDecimalsTest is PriceCacheTest {
    function test_givenPolicyDisabled_reverts() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(admin);
        cache.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.setNonContractAssetMetadata(unitOfAccount, 2, "USD2");
    }

    function testFuzz_givenCallerIsNeitherPriceAdminNorAdmin_reverts(address unauthorised) public {
        vm.assume(unauthorised != admin);
        vm.assume(unauthorised != priceManager);

        address unitOfAccount = _unitOfAccount();

        vm.prank(unauthorised);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        cache.setNonContractAssetMetadata(unitOfAccount, 2, "USD2");
    }

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

    function test_givenCallerIsAdmin_givenAssetIsRegisteredNonContractAsset_setsConfiguredMetadata()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        cache.setNonContractAssetMetadata(nonContractAsset, 8, "NCA");

        assertEq(
            cache.assetDecimals(nonContractAsset),
            8,
            "Non-contract asset decimals should use the configured cache registry value"
        );
        assertEq(
            cache.assetSymbol(nonContractAsset),
            "NCA",
            "Non-contract asset symbol should use the configured cache value"
        );
    }

    function testFuzz_givenCallerIsAdmin_givenAssetIsNotRegisteredInPRICE_reverts(
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
        cache.setNonContractAssetMetadata(nonContractAsset, 8, "NCA");
    }

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

    function test_givenCallerIsAdmin_givenSymbolIsEmpty_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        cache.setNonContractAssetMetadata(nonContractAsset, 8, "");
    }

    function test_givenCallerIsAdmin_givenSymbolExceedsMaxLength_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        cache.setNonContractAssetMetadata(nonContractAsset, 8, "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
