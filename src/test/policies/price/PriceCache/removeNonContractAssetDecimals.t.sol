// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";

import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheRemoveNonContractAssetDecimalsTest is PriceCacheTest {
    function test_givenPolicyDisabled_reverts() public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetDecimals(nonContractAsset, 8);

        vm.prank(admin);
        cache.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        cache.removeNonContractAssetDecimals(nonContractAsset);
    }

    function testFuzz_givenCallerIsNeitherPriceAdminNorAdmin_reverts(address unauthorised) public {
        vm.assume(unauthorised != admin);
        vm.assume(unauthorised != priceManager);

        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetDecimals(nonContractAsset, 8);

        vm.prank(unauthorised);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        cache.removeNonContractAssetDecimals(nonContractAsset);
    }

    function testFuzz_givenCallerIsPriceAdminOrAdmin_givenAssetIsRegisteredNonContractAsset_removesConfiguredScale(
        bool usePriceAdmin_
    ) public {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");

        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetDecimals(nonContractAsset, 8);

        vm.prank(usePriceAdmin_ ? priceManager : admin);
        cache.removeNonContractAssetDecimals(nonContractAsset);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nonContractAsset
            )
        );
        cache.assetDecimals(nonContractAsset);
    }

    function test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_reverts() public {
        address unitOfAccount = _unitOfAccount();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IPriceCache.PriceCache_InvalidAsset.selector, unitOfAccount)
        );
        cache.removeNonContractAssetDecimals(unitOfAccount);
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
        cache.removeNonContractAssetDecimals(nonContractAsset);
    }

    function test_givenCallerIsAdmin_givenAssetIsERC20_reverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                address(assetToken)
            )
        );
        cache.removeNonContractAssetDecimals(address(assetToken));
    }

    function test_givenCallerIsAdmin_givenNcaDecimalsAreRegistered_thenErc20IsDeployed_removesConfiguredScale()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetDecimals(nonContractAsset, 8);

        MockERC20 tokenWithDifferentDecimals = new MockERC20("Later Token", "LATE", 6);
        vm.etch(nonContractAsset, address(tokenWithDifferentDecimals).code);

        vm.prank(admin);
        cache.removeNonContractAssetDecimals(nonContractAsset);

        assertEq(
            cache.assetDecimals(nonContractAsset),
            6,
            "Contract decimals should still be returned after removing the stale non-contract entry"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
