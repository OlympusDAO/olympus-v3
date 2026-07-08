// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansReEnableTest is BurnerLoansTest {
    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at);

    // reEnable
    // given caller has neither admin nor burner_loans_admin role
    //  when reEnable is called within the grace period
    //   then it reverts
    function test_givenNonAdminOrBurnerLoansAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);

        vm.prank(emergency);
        burnerLoans.disable("");

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoans.reEnable();
    }

    // reEnable
    // given the policy is already enabled
    //  when reEnable is called by burner_loans_admin
    //   then it reverts
    function test_givenAlreadyEnabled_reverts() public {
        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        burnerLoans.reEnable();
    }

    // reEnable
    // given the policy re-enable grace period has elapsed
    //  when reEnable is called by burner_loans_admin
    //   then it reverts
    function test_givenGracePeriodElapsed_reverts(
        uint32 gracePeriod_,
        uint48 elapsedAfterDeadline_
    ) public {
        uint32 gracePeriod = uint32(bound(gracePeriod_, 1, type(uint32).max));
        uint48 elapsedAfterDeadline = uint48(bound(elapsedAfterDeadline_, 1, 365 days));

        vm.prank(admin);
        burnerLoans.setGracePeriod(uint32(gracePeriod));

        vm.warp(1234);
        vm.prank(emergency);
        burnerLoans.disable("");

        uint48 deadline = uint48(1234 + uint48(gracePeriod));
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        burnerLoans.reEnable();
    }

    // reEnable
    // given caller has burner_loans_admin role and the grace period is active
    //  when reEnable is called
    //   then the policy is re-enabled
    function test_givenBurnerLoansAdminCallerWithinGracePeriod_reenablesPolicy() public {
        vm.warp(1234);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.warp(1234 + BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.prank(burnerLoansAdmin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(burnerLoansAdmin, true, "", uint48(block.timestamp));
        burnerLoans.reEnable();

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), uint48(block.timestamp), "last transition");
    }

    // reEnable
    // given caller has burner_loans_admin role and a fuzzed timestamp within the grace period
    //  when reEnable is called
    //   then the policy is re-enabled
    function test_givenBurnerLoansAdminCallerWithinGracePeriod_reenablesPolicy_fuzz(
        uint48 disabledAt_,
        uint32 elapsed_
    ) public {
        uint48 disabledAt = uint48(
            bound(
                disabledAt_,
                1,
                uint256(type(uint48).max) - BurnerLoansConstants.REENABLE_GRACE_PERIOD
            )
        );
        uint32 elapsed = uint32(bound(elapsed_, 0, BurnerLoansConstants.REENABLE_GRACE_PERIOD));

        vm.warp(disabledAt);
        vm.prank(emergency);
        burnerLoans.disable("");

        assertFalse(burnerLoans.isEnabled(), "disabled");
        assertEq(burnerLoans.lastTransitionAt(), disabledAt, "disabled at");

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(burnerLoansAdmin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(burnerLoansAdmin, true, "", uint48(block.timestamp));
        burnerLoans.reEnable();

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), uint48(block.timestamp), "last transition");
    }

    // reEnable
    // given caller has admin role and the configured grace period is active
    //  when reEnable is called
    //   then the policy is re-enabled
    function test_givenAdminCallerWithinConfiguredGracePeriod_reenablesPolicy() public {
        uint32 gracePeriod = 2 days;
        vm.prank(admin);
        burnerLoans.setGracePeriod(gracePeriod);

        vm.warp(1234);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.warp(1234 + gracePeriod);
        vm.prank(admin);
        vm.expectEmit(address(burnerLoans));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(burnerLoans));
        emit Transition(admin, true, "", uint48(block.timestamp));
        burnerLoans.reEnable();

        assertTrue(burnerLoans.isEnabled(), "enabled");
        assertEq(burnerLoans.lastTransitionAt(), uint48(block.timestamp), "last transition");
    }
}
