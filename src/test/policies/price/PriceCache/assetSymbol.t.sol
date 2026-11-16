// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract MockStaticMetadataTokenSymbol {
    function symbol() external pure returns (string memory) {
        return "LATE";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}

contract PriceCacheAssetSymbolTest is PriceCacheTest {
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
        priceModule.setPrice(nonContractAsset, 3e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered.selector,
                nonContractAsset
            )
        );
        cache.assetSymbol(nonContractAsset);
    }

    function test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractSymbol()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");

        MockStaticMetadataTokenSymbol tokenWithDifferentMetadata = new MockStaticMetadataTokenSymbol();
        vm.etch(nonContractAsset, address(tokenWithDifferentMetadata).code);

        assertEq(
            cache.assetSymbol(nonContractAsset),
            "LATE",
            "Contract symbol should take precedence once code exists at the address"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
