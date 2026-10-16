// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerReEnableTest is BurnerLoansSeizerTest {
    uint48 internal constant _DISABLED_AT = 1_000;

    function test_givenNeverEnabled_reverts() public {
        BurnerLoansSeizer fresh = new BurnerLoansSeizer(
            kernel,
            address(target),
            10,
            5,
            _EXECUTION_GAS_LIMIT
        );

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        fresh.reEnable();
    }

    function test_givenAlreadyEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(burnerLoansAdmin);
        seizer.reEnable();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        vm.prank(admin);
        seizer.disable("");

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        seizer.reEnable();
    }

    function test_givenGracePeriodElapsed_reverts(uint48 elapsedAfterDeadline_) public {
        uint256 elapsedAfterDeadline = bound(elapsedAfterDeadline_, 1, 365 days);
        vm.warp(_DISABLED_AT);
        vm.prank(admin);
        seizer.disable("");

        // deadline = disabled timestamp + the 7-day default grace period.
        uint48 deadline = _DISABLED_AT + BurnerLoansConstants.REENABLE_GRACE_PERIOD;
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(burnerLoansAdmin);
        seizer.reEnable();
    }

    function test_givenBurnerLoansPolicyInactive_reverts() public {
        vm.prank(admin);
        seizer.disable("");
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(target));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        vm.prank(admin);
        seizer.reEnable();
    }

    function test_givenBurnerLoansAdminWithinGracePeriod_reEnables(uint32 elapsed_) public {
        uint256 elapsed = bound(elapsed_, 0, BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.warp(_DISABLED_AT);
        vm.prank(admin);
        seizer.addAsset(assetOne);
        vm.prank(admin);
        seizer.disable("");
        vm.warp(uint256(_DISABLED_AT) + elapsed);

        vm.prank(burnerLoansAdmin);
        seizer.reEnable();

        assertTrue(seizer.isEnabled(), "Seizer should be enabled");
        assertEq(uint256(seizer.lastTransitionAt()), block.timestamp, "last transition");
        assertTrue(seizer.isAssetManaged(assetOne), "managed assets should be preserved");
    }

    function test_givenAdminAtGracePeriodDeadline_reEnables() public {
        vm.warp(_DISABLED_AT);
        vm.prank(admin);
        seizer.disable("");
        vm.warp(uint256(_DISABLED_AT) + BurnerLoansConstants.REENABLE_GRACE_PERIOD);

        vm.prank(admin);
        seizer.reEnable();

        assertTrue(seizer.isEnabled(), "Seizer should be enabled at the deadline");
    }
}
