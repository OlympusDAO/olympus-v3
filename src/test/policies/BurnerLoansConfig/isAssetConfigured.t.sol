// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigIsAssetConfiguredTest is BurnerLoansTest {
    function test_givenMissingMarket_isAssetConfigured_returnsFalse() public view {
        assertFalse(
            burnerLoansConfig.isAssetConfigured(address(burnerLoans), address(usds)),
            "asset should not be configured"
        );
    }

    function test_givenExactlyOneMarket_isAssetConfigured_returnsTrue() public {
        _addDefaultUsdsAsset();

        assertTrue(
            burnerLoansConfig.isAssetConfigured(address(burnerLoans), address(usds)),
            "asset should be configured"
        );
    }

    function test_givenAmbiguousMarkets_isAssetConfigured_returnsTrue() public {
        _addDefaultUsdsAsset();
        _createDuplicateUsdsMarketForTest();

        assertTrue(
            burnerLoansConfig.isAssetConfigured(address(burnerLoans), address(usds)),
            "at least one market is configured"
        );
    }
}
