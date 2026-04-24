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
        cache.setNonContractAssetDecimals(unitOfAccount, 2);
    }

    function testFuzz_givenCallerIsNeitherPriceAdminNorAdmin_reverts(address unauthorised) public {
        vm.assume(unauthorised != admin);
        vm.assume(unauthorised != priceManager);

        address unitOfAccount = _unitOfAccount();

        vm.prank(unauthorised);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        cache.setNonContractAssetDecimals(unitOfAccount, 2);
    }

    function test_givenCallerIsPriceAdmin_updatesConfiguredScale() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(priceManager);
        cache.setNonContractAssetDecimals(unitOfAccount, 2);

        assertEq(
            cache.assetDecimals(unitOfAccount),
            2,
            "Unit of account decimals should use the updated cache registry value"
        );
    }

    function test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_updatesConfiguredScale() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(admin);
        cache.setNonContractAssetDecimals(unitOfAccount, 2);

        assertEq(
            cache.assetDecimals(unitOfAccount),
            2,
            "Unit of account decimals should use the updated cache registry value"
        );
    }

    function test_givenCallerIsAdmin_givenAssetIsRegisteredNonContractAsset_setsConfiguredScale()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);

        vm.prank(admin);
        cache.setNonContractAssetDecimals(nonContractAsset, 8);

        assertEq(
            cache.assetDecimals(nonContractAsset),
            8,
            "Non-contract asset decimals should use the configured cache registry value"
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
        cache.setNonContractAssetDecimals(nonContractAsset, 8);
    }

    function test_givenCallerIsAdmin_givenAssetIsERC20_reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_InvalidAsset.selector,
                address(assetToken)
            )
        );
        cache.setNonContractAssetDecimals(address(assetToken), 18);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
