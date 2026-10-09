// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerReEnableTest is DepositManagerTest {
    function test_givenContractWasNeverEnabled_reverts() public {
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(ADMIN);
        depositManager.reEnable();
    }

    function test_givenContractIsEnabled_reverts() public givenIsEnabled {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(ADMIN);
        depositManager.reEnable();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        vm.prank(EMERGENCY);
        depositManager.disable("");

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        depositManager.reEnable();
    }

    function test_givenAdminWithinGracePeriod_reenables(uint32 elapsed_) public givenIsEnabled {
        uint256 elapsed = bound(elapsed_, 0, depositManager.gracePeriod());
        vm.prank(EMERGENCY);
        depositManager.disable("");
        uint48 disabledAt = depositManager.lastTransitionAt();

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(ADMIN);
        depositManager.reEnable();

        assertTrue(depositManager.isEnabled(), "admin should re-enable DepositManager");
        assertEq(
            uint256(depositManager.lastTransitionAt()),
            block.timestamp,
            "re-enable should update transition timestamp"
        );
    }

    function test_givenDepositManagerAdminWithinGracePeriod_reenables(
        uint48 disabledAt_,
        uint32 elapsed_
    ) public givenIsEnabled {
        uint256 gracePeriod = depositManager.gracePeriod();
        uint256 disabledAt = bound(disabledAt_, 1, uint256(type(uint48).max) - gracePeriod);
        uint256 elapsed = bound(elapsed_, 0, gracePeriod);
        vm.warp(disabledAt);
        vm.prank(EMERGENCY);
        depositManager.disable("");

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        depositManager.reEnable();

        assertTrue(depositManager.isEnabled(), "Deposit Manager admin should re-enable");
    }

    function test_givenDepositManagerAdminAtGraceDeadline_reenables() public givenIsEnabled {
        vm.prank(EMERGENCY);
        depositManager.disable("");
        uint48 deadline = depositManager.lastTransitionAt() + depositManager.gracePeriod();

        vm.warp(deadline);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        depositManager.reEnable();

        assertTrue(depositManager.isEnabled(), "grace deadline should be inclusive");
    }

    function test_givenGracePeriodElapsed_reverts(
        uint48 elapsedAfterDeadline_
    ) public givenIsEnabled {
        uint256 elapsedAfterDeadline = bound(elapsedAfterDeadline_, 1, 365 days);
        vm.prank(EMERGENCY);
        depositManager.disable("");
        uint48 deadline = depositManager.lastTransitionAt() + depositManager.gracePeriod();
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        depositManager.reEnable();
    }
}
