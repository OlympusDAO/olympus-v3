// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigGetAssetConfigTest is BurnerLoansTest {
    // getAssetConfig
    // given missing market
    //  when getAssetConfig is called
    //   then it returns zero config
    function test_givenMissingMarket_getAssetConfig_returnsZeroConfig() public view {
        IBurnerLoans.AssetConfig memory config = burnerLoansConfig.getAssetConfig(
            address(burnerLoans),
            address(usds)
        );

        assertEq(
            abi.encode(config),
            abi.encode(IBurnerLoans.AssetConfig(false, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            "zero config"
        );
    }

    // getAssetConfig
    // given configured market
    //  when getAssetConfig is called
    //   then it returns decoded typed fields
    function test_givenConfiguredMarket_getAssetConfig_returnsDecodedTypedFields() public {
        _addDefaultUsdsAsset();

        assertEq(
            abi.encode(burnerLoansConfig.getAssetConfig(address(burnerLoans), address(usds))),
            abi.encode(_defaultAssetConfig(_collateralDecimals())),
            "asset config"
        );
    }

    // getAssetConfig
    // given ambiguous markets
    //  when getAssetConfig is called
    //   then it reverts
    function test_givenAmbiguousMarkets_getAssetConfig_reverts() public {
        _addDefaultUsdsAsset();
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoansConfig.getAssetConfig(address(burnerLoans), address(usds));
    }
}
