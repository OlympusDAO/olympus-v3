// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerReEnableTest is BurnerLoansYieldClaimerTest {
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        vm.prank(_emergency);
        claimer.disable("");

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.reEnable();
    }

    function test_givenAlreadyEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(burnerLoansAdmin);
        claimer.reEnable();
    }

    function test_givenBurnerLoansPolicyInactive_reverts() public {
        vm.prank(_emergency);
        claimer.disable("");
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(target));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        vm.prank(admin);
        claimer.reEnable();
    }

    function test_givenGracePeriodElapsed_reverts(uint48 elapsedAfterDeadline_) public {
        uint48 elapsedAfterDeadline = uint48(bound(elapsedAfterDeadline_, 1, 365 days));
        vm.warp(1_000);
        vm.prank(_emergency);
        claimer.disable("");
        uint48 deadline = uint48(1_000 + BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(burnerLoansAdmin);
        claimer.reEnable();
    }

    function test_givenBurnerLoansAdminWithinGrace_reEnables(uint32 elapsed_) public {
        uint32 elapsed = uint32(bound(elapsed_, 0, BurnerLoansConstants.REENABLE_GRACE_PERIOD));
        vm.warp(1_000);
        vm.prank(_emergency);
        claimer.disable("");
        vm.warp(1_000 + elapsed);

        vm.prank(burnerLoansAdmin);
        claimer.reEnable();

        assertTrue(claimer.isEnabled(), "enabled");
    }

    function test_givenAdminWithinGrace_reEnables() public {
        vm.prank(_emergency);
        claimer.disable("");

        vm.prank(admin);
        claimer.reEnable();

        assertTrue(claimer.isEnabled(), "enabled");
    }
}
