// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract PriceCacheAssetDecimalsTest is PriceCacheTest {
    function test_givenAssetIsContract_returnsERC20Decimals() public view {
        assertEq(
            cache.assetDecimals(address(assetToken)),
            assetToken.decimals(),
            "Contract asset decimals should come from the token"
        );
    }

    function test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredScale() public view {
        assertEq(
            cache.assetDecimals(_unitOfAccount()),
            UNIT_OF_ACCOUNT_DECIMALS,
            "Unit of account decimals should be initialized at deployment"
        );
    }

    function test_givenAssetIsRegisteredNonContractAsset_givenDecimalsAreNotRegistered_reverts()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, 3e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered.selector,
                nonContractAsset
            )
        );
        cache.assetDecimals(nonContractAsset);
    }

    function test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractDecimals()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetDecimals(nonContractAsset, 8);

        MockERC20 tokenWithDifferentDecimals = new MockERC20("Later Token", "LATE", 6);
        vm.etch(nonContractAsset, address(tokenWithDifferentDecimals).code);

        assertEq(
            cache.assetDecimals(nonContractAsset),
            6,
            "Contract decimals should take precedence once code exists at the address"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
