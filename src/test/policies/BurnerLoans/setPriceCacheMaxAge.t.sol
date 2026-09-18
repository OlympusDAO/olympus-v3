// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSetPriceCacheMaxAgeTest is BurnerLoansTest {
    event PriceCacheMaxAgeSet(uint48 priceCacheMaxAge);

    // when caller is not configurator
    //  then the call reverts
    function test_whenCallerIsNotConfigurator_reverts(address caller_) public {
        vm.assume(caller_ != address(burnerLoansConfig));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_OnlyConfigurator.selector, caller_)
        );
        vm.prank(caller_);
        burnerLoans.setPriceCacheMaxAge(1);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // given the Burner Loans policy is disabled
    //  when the maximum cache age is set
    //   then the call reverts
    function test_givenPolicyIsDisabled_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setPriceCacheMaxAge(1);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // when PriceCache max age is zero
    //  then it updates the configuration
    function test_whenPriceCacheMaxAgeIsZero_updatesConfiguration() public {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setPriceCacheMaxAge(1);

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit PriceCacheMaxAgeSet(0);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setPriceCacheMaxAge(0);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should be zero");
        assertEq(
            burnerLoans.context().priceCacheMaxAge,
            0,
            "context maximum cache age should be zero"
        );
    }

    // when PriceCache max age is one
    //  then it updates the configuration
    function test_whenPriceCacheMaxAgeIsOne_updatesConfiguration() public {
        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit PriceCacheMaxAgeSet(1);
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setPriceCacheMaxAge(1);

        assertEq(burnerLoans.priceCacheMaxAge(), 1, "maximum cache age should be one");
        assertEq(
            burnerLoans.context().priceCacheMaxAge,
            1,
            "context maximum cache age should be one"
        );
    }

    // when PriceCache max age is maximum
    //  then it updates the configuration
    function test_whenPriceCacheMaxAgeIsMaximum_updatesConfiguration() public {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setPriceCacheMaxAge(type(uint48).max);

        assertEq(
            burnerLoans.priceCacheMaxAge(),
            type(uint48).max,
            "maximum cache age should accept uint48 maximum"
        );
    }

    // when PriceCache max age is any uint48
    //  then it updates the configuration
    function test_whenPriceCacheMaxAgeIsAnyUint48_updatesConfiguration(
        uint48 priceCacheMaxAge_
    ) public {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setPriceCacheMaxAge(priceCacheMaxAge_);

        assertEq(
            burnerLoans.priceCacheMaxAge(),
            priceCacheMaxAge_,
            "maximum cache age should equal configured value"
        );
    }
}
