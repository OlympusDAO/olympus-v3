// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BackingOracleTest, IPolicyAdmin, IEnabler} from "./fixtures/BackingOracleTest.sol";

contract BackingOracleReEnableTest is BackingOracleTest {
    // Scenarios: BO-REENABLE-01.
    function test_givenDisabled_whenAuthorized(
        address caller_,
        uint48 elapsed_
    ) public givenEnabled {
        if (!_roles.hasRole(caller_, _BACKING_ADMIN))
            _rolesAdmin.grantRole(_BACKING_ADMIN, caller_);
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_CONFIG_OPERATOR);
        vm.prank(_ADMIN);
        _oracle.disable("");
        elapsed_ = uint48(bound(elapsed_, 0, 7 days));
        vm.warp(vm.getBlockTimestamp() + elapsed_);
        vm.expectEmit(address(_oracle));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_oracle));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _oracle.reEnable();
        assertTrue(_oracle.isEnabled(), "re-enabled");
        assertEq(_oracle.backing(), 100e18, "fast recovery preserves backing");
        assertEq(_oracle.configOperator(), _CONFIG_OPERATOR, "fast recovery preserves delegation");
        assertEq(_oracle.lastTransitionAt(), vm.getBlockTimestamp(), "transition timestamp");
    }

    // Scenarios: BO-REENABLE-02.
    function test_givenDisabled_whenAdminAtDeadline() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.warp(vm.getBlockTimestamp() + 7 days);
        vm.prank(_ADMIN);
        _oracle.reEnable();
        assertEq(_oracle.backing(), 100e18, "inclusive grace boundary preserves backing");
    }

    // Scenarios: BO-REENABLE-03.
    function test_givenDisabled_whenAfterDeadline_reverts() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.disable("");
        uint48 deadline = uint48(vm.getBlockTimestamp() + 7 days);
        vm.warp(uint256(deadline) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(_PROPOSER);
        _oracle.reEnable();
    }

    // Scenarios: BO-REENABLE-04.
    function test_givenNeverEnabled_whenRecover_reverts() public {
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(_ADMIN);
        _oracle.reEnable();
    }

    // Scenarios: BO-REENABLE-05.
    function test_givenEnabled_whenRecover_reverts() public givenEnabled {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(_ADMIN);
        _oracle.reEnable();
    }

    // Scenarios: BO-REENABLE-06.
    function test_givenDisabled_whenUnauthorized_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != _ADMIN && caller_ != _PROPOSER);
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _oracle.reEnable();
    }

    // Scenarios: BO-REENABLE-07.
    function test_givenInactive_whenRecover_reverts() public givenEnabled givenInactive {
        vm.prank(_EMERGENCY);
        _oracle.disable("");
        _expectInactive();
        vm.prank(_PROPOSER);
        _oracle.reEnable();
    }

    // Scenarios: BO-REENABLE-08.
    function test_givenDeadlineOverflow_whenRecover_reverts() public givenEnabled {
        vm.warp(type(uint48).max);
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + 7 days
            )
        );
        vm.prank(_ADMIN);
        _oracle.reEnable();
    }

    // Scenarios: BO-REENABLE-09.
    function test_givenDisabled_whenImmediatelyBeforeDeadline() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.warp(vm.getBlockTimestamp() + 7 days - 1);
        vm.prank(_PROPOSER);
        _oracle.reEnable();
        assertTrue(_oracle.isEnabled(), "last second before grace deadline");
    }
}
