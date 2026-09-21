// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetPriceCacheMaxAgeTest is BurnerLoansTest {
    // when caller is not admin or config operator
    //  then the call reverts
    function test_whenCallerIsNotAdminOrConfigOperator_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));
        _setDefaultConfigOperator();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        burnerLoansConfig.setPriceCacheMaxAge(1);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // given Burner Loans Config is disabled
    //  when the maximum cache age is set
    //   then the call reverts
    function test_givenConfigIsDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        burnerLoansConfig.setPriceCacheMaxAge(1);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // given the Burner Loans facility is disabled
    //  when the maximum cache age is set
    //   then it propagates the disabled-state error
    function test_givenFacilityIsDisabled_propagatesNotEnabled() public {
        vm.prank(admin);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        burnerLoansConfig.setPriceCacheMaxAge(1);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should remain unchanged");
    }

    // given the caller is admin
    //  when PriceCache max age is zero
    //   then it forwards the configuration
    function test_givenAdmin_whenPriceCacheMaxAgeIsZero_forwardsConfiguration() public {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setPriceCacheMaxAge(1);

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.PriceCacheMaxAgeSet(0);
        vm.prank(admin);
        burnerLoansConfig.setPriceCacheMaxAge(0);

        assertEq(burnerLoans.priceCacheMaxAge(), 0, "maximum cache age should be zero");
    }

    // given the caller is admin
    //  when PriceCache max age is maximum
    //   then it forwards the configuration
    function test_givenAdmin_whenPriceCacheMaxAgeIsMaximum_forwardsConfiguration() public {
        vm.prank(admin);
        burnerLoansConfig.setPriceCacheMaxAge(type(uint48).max);

        assertEq(
            burnerLoans.priceCacheMaxAge(),
            type(uint48).max,
            "maximum cache age should accept uint48 maximum"
        );
    }

    // given the caller is the config operator
    //  when the maximum cache age is set
    //   then it forwards the full uint48 range
    function test_givenConfigOperator_forwardsAnyUint48(uint48 priceCacheMaxAge_) public {
        _setDefaultConfigOperator();

        vm.prank(address(configTimelock));
        burnerLoansConfig.setPriceCacheMaxAge(priceCacheMaxAge_);

        assertEq(
            burnerLoans.priceCacheMaxAge(),
            priceCacheMaxAge_,
            "maximum cache age should equal forwarded value"
        );
    }
}
