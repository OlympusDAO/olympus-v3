// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YieldRepurchaseFacilityConfigTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock/YieldRepurchaseFacilityConfigTimelockTestBase.sol";

contract YieldRepurchaseFacilityConfigTimelockTests_ReEnable is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // reEnable
    // given the caller does not hold the yrf_admin role
    //  when re-enabling the disabled policy
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenNonYrfAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.reEnable();
    }

    // reEnable
    // given the caller holds only the admin role
    //  when re-enabling the disabled policy
    //   then it reverts (the admin restarts through `enable` instead)
    function test_givenAdminCaller_reverts() public {
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.reEnable();
    }

    // reEnable
    // given the policy is enabled
    //  when re-enabling
    //   then it reverts with NotDisabled
    function test_givenAlreadyEnabled_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        configTimelock.reEnable();
    }

    // reEnable
    // given the grace window since the disable has elapsed
    //  when the yrf_admin re-enables at any such timestamp
    //   then it reverts with GracePeriod_Expired
    function test_givenGracePeriodElapsed_reverts(uint48 elapsed_) public {
        uint256 disabledAt = vm.getBlockTimestamp();
        vm.prank(guardian);
        configTimelock.disable("");
        // Keep the warped timestamp within the uint48 domain the grace check is measured
        // in; beyond it the contract's uint48 timestamp cast wraps (~8.9M years out).
        elapsed_ = uint48(bound(elapsed_, gracePeriod + 1, type(uint48).max - disabledAt));
        vm.warp(disabledAt + elapsed_);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGracePeriod.GracePeriod_Expired.selector,
                uint48(disabledAt + gracePeriod)
            )
        );
        configTimelock.reEnable();

        assertFalse(configTimelock.isEnabled(), "still disabled");
    }

    // reEnable
    // given any timestamp within the grace window since the disable
    //  when the yrf_admin re-enables
    //   then the policy is enabled and the transition events are emitted
    function test_givenYrfAdminCallerWithinGracePeriod_reenablesPolicy(uint48 elapsed_) public {
        uint256 disabledAt = vm.getBlockTimestamp();
        vm.prank(guardian);
        configTimelock.disable("");
        // The deadline is inclusive: the window closes strictly after
        // `lastTransitionAt + gracePeriod`.
        elapsed_ = uint48(bound(elapsed_, 0, gracePeriod));
        vm.warp(disabledAt + elapsed_);

        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit IEnablerV2.Transition(yrfAdmin, true, "", uint48(disabledAt + elapsed_));
        vm.prank(yrfAdmin);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "enabled");
        assertEq(configTimelock.lastTransitionAt(), disabledAt + elapsed_, "last transition at");
    }

    // reEnable
    // given an action was queued before the disable and its window has not expired
    //  when the policy is re-enabled within the grace window
    //   then the queued action becomes executable again
    function test_givenReEnabled_queuedActionBecomesExecutable() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        configTimelock.disable("");
        // One day of downtime: within the grace window, at the action's executableAt.
        _warpToExecutable(configTimelock, actionId);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.executeQueuedAction(actionId);

        vm.prank(yrfAdmin);
        configTimelock.reEnable();
        configTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 1e16, "discount applied");
    }
}
