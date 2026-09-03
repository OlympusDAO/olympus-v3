// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Contracts
import {BurnerLoansTest} from "../BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigMarketIdTest is BurnerLoansTest {
    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
    }

    // marketId
    // given two matching markets for the configured facility and token pair
    //  when the unique market is requested
    //   then it rejects the ambiguous configuration
    function test_givenMultipleMatchingMarkets_marketIdReverts() public {
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoansConfig.marketId(address(usds));
    }
}
