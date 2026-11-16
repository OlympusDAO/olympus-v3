// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {PriceCacheTest} from "./PriceCacheTest.sol";

contract MockStaticMetadataTokenDecimals {
    function symbol() external pure returns (string memory) {
        return "LATE";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}

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

    function test_givenAssetIsUnregisteredNonContractAsset_reverts() public {
        address unregisteredNonContractAsset = makeAddr("UNREGISTERED_NON_CONTRACT_ASSET");

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCache.PriceCache_NonContractAssetNotRegistered.selector,
                unregisteredNonContractAsset
            )
        );
        cache.assetDecimals(unregisteredNonContractAsset);
    }

    function test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractDecimals()
        public
    {
        address nonContractAsset = makeAddr("NON_CONTRACT_ASSET");
        _registerNonContractAsset(nonContractAsset);
        _setNonContractAssetMetadata(nonContractAsset, 8, "NCA");

        assertEq(
            cache.assetDecimals(nonContractAsset),
            8,
            "Registered metadata decimals should be returned before code exists"
        );

        MockStaticMetadataTokenDecimals tokenWithDifferentDecimals = new MockStaticMetadataTokenDecimals();
        vm.etch(nonContractAsset, address(tokenWithDifferentDecimals).code);

        assertEq(
            cache.assetDecimals(nonContractAsset),
            6,
            "Contract decimals should take precedence once code exists at the address"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
