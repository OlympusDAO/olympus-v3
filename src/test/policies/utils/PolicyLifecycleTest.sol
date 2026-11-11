// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel, Policy} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

abstract contract PolicyLifecycleTest is Test {
    address internal _lifecycleTarget;
    Kernel internal _lifecycleKernel;
    OlympusRoles internal _lifecycleRoles;
    RolesAdmin internal _lifecycleRolesAdmin;
    address internal _lifecycleAdmin;
    address internal _lifecycleExecutor;
    address internal _lifecycleEmergency;
    address internal _lifecycleSecondary;
    bytes32 internal _lifecycleSecondaryRole;

    function _preservedState() internal view virtual returns (bytes32);

    modifier givenLifecycleDisabled() {
        _pause();
        _;
    }

    modifier givenLifecycleInactive() {
        _setMembership(false);
        _;
    }

    modifier givenLifecycleAdmin(address caller_) {
        _grantLifecycleRole(ADMIN_ROLE, caller_);
        _;
    }

    modifier givenLifecycleAdminOnly(address caller_) {
        vm.assume(!_lifecycleRoles.hasRole(caller_, EMERGENCY_ROLE));
        _grantLifecycleRole(ADMIN_ROLE, caller_);
        _;
    }

    modifier givenLifecycleEmergencyOnly(address caller_) {
        vm.assume(!_lifecycleRoles.hasRole(caller_, ADMIN_ROLE));
        _grantLifecycleRole(EMERGENCY_ROLE, caller_);
        _;
    }

    modifier givenLifecycleOverlap(address caller_) {
        _grantLifecycleRole(ADMIN_ROLE, caller_);
        _grantLifecycleRole(EMERGENCY_ROLE, caller_);
        _;
    }

    modifier givenNonemptyPayload(bytes memory data_) {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _;
    }

    function _grantLifecycleRole(bytes32 role_, address caller_) internal {
        if (_lifecycleRoles.hasRole(caller_, role_)) return;
        vm.prank(_lifecycleExecutor);
        _lifecycleRolesAdmin.grantRole(role_, caller_);
    }

    function _excludeEnableCallers(address caller_) internal view {
        vm.assume(!_lifecycleRoles.hasRole(caller_, ADMIN_ROLE));
    }

    function _excludeDisableCallers(address caller_) internal view {
        _excludeEnableCallers(caller_);
        vm.assume(!_lifecycleRoles.hasRole(caller_, EMERGENCY_ROLE));
    }

    function _excludeReEnableCallers(address caller_) internal view {
        _excludeEnableCallers(caller_);
        vm.assume(!_lifecycleRoles.hasRole(caller_, _lifecycleSecondaryRole));
    }

    function _pause() internal {
        vm.prank(_lifecycleAdmin);
        IEnabler(_lifecycleTarget).disable("");
    }

    function _setMembership(bool active_) internal {
        vm.prank(_lifecycleExecutor);
        _lifecycleKernel.executeAction(
            active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
            _lifecycleTarget
        );
    }

    function _enableSucceeds(address caller_) internal {
        _transitionSucceeds(caller_, abi.encodeCall(IEnabler.enable, (bytes(""))), true);
    }

    function _disableSucceeds(address caller_) internal {
        _transitionSucceeds(caller_, abi.encodeCall(IEnabler.disable, (bytes(""))), false);
    }

    function _reEnableSucceeds(address caller_) internal {
        _transitionSucceeds(caller_, abi.encodeCall(IReEnabler.reEnable, ()), true);
    }

    function _transitionSucceeds(address caller_, bytes memory call_, bool enabled_) private {
        bytes32 beforeState = _preservedState();
        uint256 transitionAt = vm.getBlockTimestamp();
        bool activeBefore = _lifecycleKernel.isPolicyActive(Policy(_lifecycleTarget));
        vm.record();
        assertEq(
            IEnabler(_lifecycleTarget).isEnabled(),
            !enabled_,
            "transition starts in opposite state"
        );
        (bytes32[] memory lifecycleSlots, bytes32[] memory getterWrites) = vm.accesses(
            _lifecycleTarget
        );
        assertEq(lifecycleSlots.length, 1, "enabled getter reads its packed lifecycle slot");
        assertEq(getterWrites.length, 0, "enabled getter writes no storage");
        vm.recordLogs();
        vm.record();
        vm.prank(caller_);
        (bool success, bytes memory result) = _lifecycleTarget.call(call_);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
        assertEq(result.length, 0, "lifecycle transition has no return data");
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(_lifecycleTarget);
        assertGt(reads.length, 0, "transition reads current lifecycle state");
        assertGt(writes.length, 0, "transition writes lifecycle state");
        for (uint256 i; i < writes.length; ++i) {
            assertEq(writes[i], lifecycleSlots[0], "only packed enabled/timestamp slot written");
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "exactly legacy event and Transition");
        assertEq(logs[0].emitter, _lifecycleTarget, "legacy event emitter");
        assertEq(logs[0].topics.length, 1, "legacy event has no indexed fields");
        assertEq(
            logs[0].topics[0],
            enabled_ ? keccak256("Enabled()") : keccak256("Disabled()"),
            "legacy event direction"
        );
        assertEq(logs[0].data.length, 0, "legacy event has no data");
        assertEq(logs[1].emitter, _lifecycleTarget, "Transition emitter");
        assertEq(logs[1].topics.length, 3, "Transition indexed field count");
        assertEq(
            logs[1].topics[0],
            keccak256("Transition(address,bool,bytes,uint48)"),
            "Transition signature"
        );
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(caller_))), "Transition caller");
        assertEq(logs[1].topics[2], bytes32(uint256(enabled_ ? 1 : 0)), "Transition direction");
        assertEq(
            logs[1].data,
            abi.encode(bytes(""), transitionAt),
            "Transition empty payload and exact timestamp"
        );
        assertEq(IEnabler(_lifecycleTarget).isEnabled(), enabled_, "new enabled state");
        assertEq(
            uint256(IEnablerV2(_lifecycleTarget).lastTransitionAt()),
            transitionAt,
            "transition timestamp"
        );
        assertEq(
            _lifecycleKernel.isPolicyActive(Policy(_lifecycleTarget)),
            activeBefore,
            "membership preserved"
        );
        assertEq(_preservedState(), beforeState, "configuration and authoritative data preserved");
    }

    function _lifecycleReverts(address caller_, bytes memory call_, bytes memory error_) internal {
        bytes32 beforeState = _preservedState();
        bool enabledBefore = IEnabler(_lifecycleTarget).isEnabled();
        uint48 transitionBefore = IEnablerV2(_lifecycleTarget).lastTransitionAt();
        vm.prank(caller_);
        (bool success, bytes memory result) = _lifecycleTarget.call(call_);
        assertFalse(success, "lifecycle call rejects");
        assertEq(result, error_, "exact lifecycle error and arguments");
        assertEq(
            IEnabler(_lifecycleTarget).isEnabled(),
            enabledBefore,
            "rejection preserves enabled state"
        );
        assertEq(
            IEnablerV2(_lifecycleTarget).lastTransitionAt(),
            transitionBefore,
            "rejection preserves transition timestamp"
        );
        assertEq(
            _preservedState(),
            beforeState,
            "rejection preserves configuration and authoritative data"
        );
    }

    function _setGrace(uint32 grace_) internal {
        vm.prank(_lifecycleAdmin);
        IGracePeriod(_lifecycleTarget).setGracePeriod(grace_);
    }

    function _graceSucceeds(address caller_, uint32 grace_) internal {
        bool enabledBefore = IEnabler(_lifecycleTarget).isEnabled();
        bool activeBefore = _lifecycleKernel.isPolicyActive(Policy(_lifecycleTarget));
        uint48 transitionBefore = IEnablerV2(_lifecycleTarget).lastTransitionAt();
        vm.record();
        assertGt(IGracePeriod(_lifecycleTarget).gracePeriod(), 0, "configured grace is nonzero");
        (bytes32[] memory graceSlots, bytes32[] memory getterWrites) = vm.accesses(
            _lifecycleTarget
        );
        assertEq(graceSlots.length, 1, "grace getter reads one slot");
        assertEq(getterWrites.length, 0, "grace getter writes no storage");
        vm.recordLogs();
        vm.record();
        vm.prank(caller_);
        IGracePeriod(_lifecycleTarget).setGracePeriod(grace_);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(_lifecycleTarget);
        assertGt(reads.length, 0, "grace setter reads admission state");
        for (uint256 i; i < writes.length; ++i)
            assertEq(writes[i], graceSlots[0], "only grace slot written");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one GracePeriodSet event, including unchanged values");
        assertEq(logs[0].emitter, _lifecycleTarget, "grace event emitter");
        assertEq(logs[0].topics.length, 1, "grace event has no indexed fields");
        assertEq(logs[0].topics[0], keccak256("GracePeriodSet(uint32)"), "grace event signature");
        assertEq(logs[0].data, abi.encode(grace_), "exact grace event value");
        assertEq(IGracePeriod(_lifecycleTarget).gracePeriod(), grace_, "exact stored grace");
        assertEq(
            IEnabler(_lifecycleTarget).isEnabled(),
            enabledBefore,
            "grace setter preserves enabled state"
        );
        assertEq(
            IEnablerV2(_lifecycleTarget).lastTransitionAt(),
            transitionBefore,
            "grace setter preserves transition timestamp"
        );
        assertEq(
            _lifecycleKernel.isPolicyActive(Policy(_lifecycleTarget)),
            activeBefore,
            "grace setter preserves membership"
        );
    }

    function _pauseAt(uint48 at_) internal {
        vm.warp(at_);
        _pause();
    }
}
