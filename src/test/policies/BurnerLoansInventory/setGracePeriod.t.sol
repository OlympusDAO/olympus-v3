// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySetGracePeriodTest is BurnerLoansInventoryTest {
    uint32 internal constant _ONE_DAY = 1 days;

    function test_givenConstructed_setsDefaultGracePeriod() public view {
        assertEq(
            inventory.gracePeriod(),
            BurnerLoansConstants.REENABLE_GRACE_PERIOD,
            "default grace period"
        );
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        _initializeAndEnable();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        inventory.setGracePeriod(_ONE_DAY);
    }

    function test_givenBurnerLoansAdminCaller_reverts() public {
        _initializeAndEnable();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(burnerLoansAdmin);
        inventory.setGracePeriod(_ONE_DAY);
    }

    function test_givenZeroPeriod_reverts() public {
        _initializeAndEnable();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        inventory.setGracePeriod(0);
    }

    function test_givenDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        inventory.setGracePeriod(_ONE_DAY);
    }

    function test_givenValidPeriod_setsPeriod(uint32 period_) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _initializeAndEnable();

        vm.prank(admin);
        inventory.setGracePeriod(period_);

        assertEq(inventory.gracePeriod(), period_, "grace period should be updated");
    }

    function test_givenMaximumPeriod_setsPeriod() public {
        _initializeAndEnable();

        vm.prank(admin);
        inventory.setGracePeriod(type(uint32).max);

        assertEq(inventory.gracePeriod(), type(uint32).max, "maximum grace period");
    }
}
