// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BackingOracleConfigTimelockTest, IEnabler, IPolicyAdmin} from "./fixtures/BackingOracleConfigTimelockTest.sol";

// Constants
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleTimelockDisableTest is BackingOracleConfigTimelockTest {
    // Scenarios: BO-TIMELOCK-DISABLE-01.
    function test_givenPending_whenAuthorized(
        bool asAdmin_,
        bool active_,
        bool overlap_
    ) public givenEnabled {
        uint64 id = _queue(110e18);
        bytes32 intent = _pendingIntentHash(id);
        if (overlap_) _rolesAdmin.grantRole(EMERGENCY_ROLE, _ADMIN);
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        address caller = asAdmin_ ? _ADMIN : _EMERGENCY;
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.mockCallRevert(
            address(_oracle),
            bytes(""),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        vm.expectEmit(address(_timelock));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(caller, false, "", uint48(vm.getBlockTimestamp()));
        vm.recordLogs();
        vm.prank(caller);
        _timelock.disable("");
        assertEq(vm.getRecordedLogs().length, 2, "exactly the two transition events");
        vm.clearMockedCalls();
        assertFalse(
            _timelock.isEnabled(),
            "authorized pause succeeds independent of own activity and target"
        );
        assertEq(
            _timelock.lastTransitionAt(),
            vm.getBlockTimestamp(),
            "pause records current timestamp"
        );
        assertEq(
            _pendingIntentHash(id),
            intent,
            "pause preserves all queued intent and oracle configuration"
        );
    }

    // Scenarios: BO-TIMELOCK-DISABLE-02.
    function test_whenUnauthorized_reverts(address caller_, bool active_) public givenEnabled {
        vm.assume(caller_ != _ADMIN && caller_ != _EMERGENCY);
        uint64 id = _queue(110e18);
        bytes32 intent = _pendingIntentHash(id);
        uint48 previousTransition = _timelock.lastTransitionAt();
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.disable(hex"01");
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized pause emits no events");
        assertTrue(_timelock.isEnabled(), "unauthorized pause preserves enablement");
        assertEq(
            _timelock.lastTransitionAt(),
            previousTransition,
            "unauthorized pause preserves timestamp"
        );
        assertEq(_pendingIntentHash(id), intent, "unauthorized pause preserves complete intent");
    }

    // Scenarios: BO-TIMELOCK-DISABLE-03.
    function test_givenDisabled_whenDisable_reverts(
        address caller_,
        bool active_
    ) public givenEnabled {
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _timelock.disable("");
        bytes32 intent = _pendingIntentHash(id);
        uint48 previousTransition = _timelock.lastTransitionAt();
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _timelock.disable(hex"01");
        assertEq(vm.getRecordedLogs().length, 0, "repeated pause emits no events");
        assertFalse(_timelock.isEnabled(), "repeated pause remains disabled");
        assertEq(
            _timelock.lastTransitionAt(),
            previousTransition,
            "repeated pause preserves timestamp"
        );
        assertEq(_pendingIntentHash(id), intent, "repeated pause preserves complete intent");
    }

    // Scenarios: BO-TIMELOCK-DISABLE-04.
    function test_whenNonemptyData_reverts(
        bytes calldata data_,
        bool asAdmin_,
        bool active_
    ) public givenEnabled {
        vm.assume(data_.length != 0);
        uint64 id = _queue(110e18);
        bytes32 intent = _pendingIntentHash(id);
        uint48 previousTransition = _timelock.lastTransitionAt();
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        vm.expectRevert(
            IBackingOracleConfigTimelock.BackingOracleTimelock_InvalidEnablerData.selector
        );
        vm.prank(asAdmin_ ? _ADMIN : _EMERGENCY);
        _timelock.disable(data_);
        assertEq(vm.getRecordedLogs().length, 0, "invalid pause emits no events");
        assertTrue(_timelock.isEnabled(), "invalid data preserves enablement");
        assertEq(
            _timelock.lastTransitionAt(),
            previousTransition,
            "invalid data preserves timestamp"
        );
        assertEq(_pendingIntentHash(id), intent, "invalid data preserves complete intent");
    }

    // Scenarios: BO-TIMELOCK-DISABLE-05.
    function test_givenReEnabled_whenDisable() public givenEnabled {
        uint64 id = _queue(110e18);
        bytes32 intent = _pendingIntentHash(id);
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.prank(_PROPOSER);
        _timelock.reEnable();
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(_ADMIN);
        _timelock.disable("");
        assertFalse(_timelock.isEnabled(), "recovered queue can be paused again");
        assertEq(
            _timelock.lastTransitionAt(),
            vm.getBlockTimestamp(),
            "new pause updates timestamp"
        );
        assertEq(
            _pendingIntentHash(id),
            intent,
            "repeated lifecycle transitions preserve pending intent"
        );
    }
}
