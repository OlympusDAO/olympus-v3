// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BackingOracleConfigTimelockTest, PolicyDependency, IPolicyAdmin, IBackingOracle, IEnabler} from "./fixtures/BackingOracleConfigTimelockTest.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleTimelockEnableTest is BackingOracleConfigTimelockTest {
    error MetadataUnavailable();

    // Scenarios: BO-TIMELOCK-ENABLE-07.
    function test_givenPending_whenUnauthorized_reverts(
        address caller_,
        bool active_
    ) public givenEnabled {
        vm.assume(caller_ != _ADMIN);
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _timelock.disable("");
        bytes32 intent = _pendingIntentHash(id);
        uint48 previousTransition = _timelock.lastTransitionAt();
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _timelock.enable(hex"01");
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized enable emits no events");
        assertFalse(_timelock.isEnabled(), "unauthorized enable preserves disabled state");
        assertEq(
            _timelock.lastTransitionAt(),
            previousTransition,
            "unauthorized enable preserves timestamp"
        );
        assertEq(_pendingIntentHash(id), intent, "unauthorized enable preserves complete intent");
    }

    // Scenarios: BO-TIMELOCK-ENABLE-08.
    function test_givenEnabled_whenEnable_reverts(
        address caller_,
        bool active_
    ) public givenEnabled {
        uint64 id = _queue(110e18);
        bytes32 intent = _pendingIntentHash(id);
        uint48 previousTransition = _timelock.lastTransitionAt();
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _timelock.enable(hex"01");
        assertEq(vm.getRecordedLogs().length, 0, "repeated enable emits no events");
        assertTrue(_timelock.isEnabled(), "repeated enable preserves enabled state");
        assertEq(
            _timelock.lastTransitionAt(),
            previousTransition,
            "repeated enable preserves timestamp"
        );
        assertEq(_pendingIntentHash(id), intent, "repeated enable preserves complete intent");
    }

    // Scenarios: BO-TIMELOCK-ENABLE-09.
    function test_givenPending_whenAdminEnables() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _timelock.disable("");
        bytes32 intent = _pendingIntentHash(id);
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.expectEmit(address(_timelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(_ADMIN, true, "", uint48(vm.getBlockTimestamp()));
        vm.recordLogs();
        vm.prank(_ADMIN);
        _timelock.enable("");
        assertEq(vm.getRecordedLogs().length, 2, "exactly the two enable transition events");
        assertTrue(_timelock.isEnabled(), "ADMIN enables paused queue");
        assertEq(
            _timelock.lastTransitionAt(),
            vm.getBlockTimestamp(),
            "enable records current timestamp"
        );
        assertEq(
            _pendingIntentHash(id),
            intent,
            "enable preserves complete intent and oracle configuration"
        );
    }

    // Scenarios: BO-TIMELOCK-ENABLE-01.
    function test_givenTargetPaused_whenEnable(bool targetEnabled_) public {
        if (targetEnabled_) {
            vm.prank(_ADMIN);
            _oracle.enable(abi.encode(100e18));
        }
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(MetadataUnavailable.selector)
        );
        vm.prank(_ADMIN);
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "activation does not read target enablement");
    }

    // Scenarios: BO-TIMELOCK-ENABLE-02.
    function test_givenOperatorRevoked_whenEnable_reverts() public {
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(0));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_ADMIN);
        _timelock.enable("");
    }

    // Scenarios: BO-TIMELOCK-ENABLE-03.
    function test_givenTargetInactive_whenEnable_reverts(bool targetEnabled_) public givenEnabled {
        uint64 id = _queue(110e18);
        if (!targetEnabled_) {
            vm.prank(_ADMIN);
            _oracle.disable("");
        }
        _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        vm.prank(_ADMIN);
        _timelock.disable("");
        bytes32 intent = _pendingIntentHash(id);
        uint48 previousTransition = _timelock.lastTransitionAt();
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        _expectTargetUnavailable();
        vm.prank(_ADMIN);
        _timelock.enable("");
        assertEq(vm.getRecordedLogs().length, 0, "inactive target rejects enable without events");
        assertFalse(_timelock.isEnabled(), "failed enable leaves queue paused");
        assertEq(
            _timelock.lastTransitionAt(),
            previousTransition,
            "failed enable preserves timestamp"
        );
        assertEq(_pendingIntentHash(id), intent, "failed enable preserves pending intent");
        _kernel.executeAction(Actions.ActivatePolicy, address(_oracle));
        vm.prank(_ADMIN);
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "reactivating the target permits enable even if paused");
        assertEq(_pendingIntentHash(id), intent, "successful retry preserves pending intent");
    }

    // Scenarios: BO-TIMELOCK-ENABLE-04.
    function test_givenOwnInactive_whenEnable_reverts() public givenTimelockInactive {
        vm.prank(_ADMIN);
        _timelock.disable("");
        _expectTimelockInactive();
        vm.prank(_ADMIN);
        _timelock.enable("");
    }

    // Scenarios: BO-TIMELOCK-ENABLE-05.
    function test_whenEachConsumedInterfaceMissing_reverts() public {
        vm.prank(_ADMIN);
        _timelock.disable("");
        bytes4[3] memory ids = [
            type(IBackingOracle).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        for (uint256 i; i < ids.length; ++i) {
            vm.mockCall(
                address(_oracle),
                abi.encodeWithSignature("supportsInterface(bytes4)", ids[i]),
                abi.encode(false)
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBackingOracleConfigTimelock
                        .BackingOracleTimelock_InvalidBackingOracle
                        .selector,
                    address(_oracle)
                )
            );
            vm.prank(_ADMIN);
            _timelock.enable("");
            vm.clearMockedCalls();
        }
    }

    // Scenarios: BO-TIMELOCK-ENABLE-06.
    function test_whenMalformedEnableData_reverts(bytes calldata data_) public {
        vm.assume(data_.length != 0);
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.expectRevert(
            IBackingOracleConfigTimelock.BackingOracleTimelock_InvalidEnablerData.selector
        );
        vm.prank(_ADMIN);
        _timelock.enable(data_);
    }
}
