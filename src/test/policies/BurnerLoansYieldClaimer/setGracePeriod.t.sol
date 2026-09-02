// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSetGracePeriodTest is BurnerLoansYieldClaimerTest {
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        claimer.setGracePeriod(1 days);
    }

    function test_givenZeroPeriod_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        claimer.setGracePeriod(0);
    }

    function test_givenDisabled_reverts() public {
        vm.prank(_emergency);
        claimer.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        claimer.setGracePeriod(1 days);
    }

    function test_givenValidPeriod_setsPeriod(uint32 period_) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));

        vm.prank(admin);
        claimer.setGracePeriod(period_);

        assertEq(claimer.gracePeriod(), period_, "grace period");
    }

    function test_givenMaximumPeriod_setsPeriod() public {
        vm.prank(admin);
        claimer.setGracePeriod(type(uint32).max);

        assertEq(claimer.gracePeriod(), type(uint32).max, "grace period");
    }
}
