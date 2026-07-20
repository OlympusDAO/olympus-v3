// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigGetAssetFeeConfigTest is BurnerLoansTest {
    function test_givenMissingMarket_getAssetFeeConfig_returnsZeroConfig() public view {
        IBurnerLoans.AssetFeeConfig memory config = burnerLoansConfig.getAssetFeeConfig(
            address(burnerLoans),
            address(usds)
        );

        assertEq(config.baseFeeBps, 0, "base fee");
        assertEq(config.kinkBps, 0, "kink");
        assertEq(config.preKinkSlopeBps, 0, "pre-kink slope");
        assertEq(config.postKinkSlopeBps, 0, "post-kink slope");
    }

    function test_givenConfiguredMarket_getAssetFeeConfig_returnsDecodedFields() public {
        _addDefaultUsdsAsset();

        assertEq(
            abi.encode(burnerLoansConfig.getAssetFeeConfig(address(burnerLoans), address(usds))),
            abi.encode(_defaultAssetFeeConfig()),
            "fee config"
        );
    }

    function test_givenAmbiguousMarkets_getAssetFeeConfig_reverts() public {
        _addDefaultUsdsAsset();
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoansConfig.getAssetFeeConfig(address(burnerLoans), address(usds));
    }
}
