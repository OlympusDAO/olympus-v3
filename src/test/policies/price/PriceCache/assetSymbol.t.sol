// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {Actions} from "src/Kernel.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";
import {MockStaticMetadataToken} from "./fixtures/MockStaticMetadataToken.sol";

contract PriceCacheAssetSymbolTest is PriceCacheTest {
    function test_whenConstructorSymbolIsEmpty_reverts() public {
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        new PriceCache(kernel, UNIT_OF_ACCOUNT_DECIMALS, "");
    }

    function test_whenConstructorSymbolExceedsMaximumLength_reverts() public {
        vm.expectRevert(IPriceCache.PriceCache_InvalidAssetSymbol.selector);
        new PriceCache(kernel, UNIT_OF_ACCOUNT_DECIMALS, "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567");
    }

    function test_whenConstructorSymbolHasMaximumLength_returnsEntireSymbol() public {
        string memory maximumSymbol = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";
        PriceCache maximumSymbolCache = new PriceCache(
            kernel,
            UNIT_OF_ACCOUNT_DECIMALS,
            maximumSymbol
        );
        kernel.executeAction(Actions.ActivatePolicy, address(maximumSymbolCache));

        assertEq(
            maximumSymbolCache.assetSymbol(_unitOfAccount()),
            maximumSymbol,
            "maximum-length constructor symbol should round-trip"
        );
    }

    function test_givenAssetIsContract_returnsERC20Symbol() public view {
        assertEq(
            cache.assetSymbol(address(assetToken)),
            assetToken.symbol(),
            "Contract asset symbol should come from the token"
        );
    }

    function test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredSymbol() public view {
        assertEq(
            cache.assetSymbol(_unitOfAccount()),
            UNIT_OF_ACCOUNT_SYMBOL,
            "Unit of account symbol should be initialized at deployment"
        );
    }

    function test_givenAssetIsRegisteredNonContractAsset_givenSymbolIsNotRegistered_reverts()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        priceModule.setPrice(nonContractAsset, NON_CONTRACT_PRICE_USD);

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

    function test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractSymbol()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, NON_CONTRACT_DECIMALS, "NCA");

        MockStaticMetadataToken tokenWithDifferentMetadata = new MockStaticMetadataToken();
        vm.etch(nonContractAsset, address(tokenWithDifferentMetadata).code);

        assertEq(
            cache.assetSymbol(nonContractAsset),
            "LATE",
            "Contract symbol should take precedence once code exists at the address"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
