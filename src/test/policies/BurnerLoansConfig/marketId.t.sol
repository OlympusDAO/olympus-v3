// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigMarketIdTest is BurnerLoansTest {
    // marketId
    // given exactly one market
    //  when marketId is called
    //   then it returns canonical id
    function test_givenExactlyOneMarket_marketId_returnsCanonicalId() public {
        _addDefaultUsdsAsset();

        assertEq(burnerLoansConfig.marketId(address(burnerLoans), address(usds)), 0, "market id");
    }

    // marketId
    // given missing market
    //  when marketId is called
    //   then it reverts
    function test_givenMissingMarket_marketId_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.marketId(address(burnerLoans), address(usds));
    }

    // marketId
    // given ambiguous markets
    //  when marketId is called
    //   then it reverts
    function test_givenAmbiguousMarkets_marketId_reverts() public {
        _addDefaultUsdsAsset();
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoansConfig.marketId(address(burnerLoans), address(usds));
    }
}
