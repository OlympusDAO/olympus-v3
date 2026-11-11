// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansRiskConfigTimelockDisableTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-DISABLE-P01.
    function test_whenAdminOrEmergencyDisables(address caller_, uint8 role_, bool active_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        uint8 role = uint8(bound(role_, 0, 2));
        if (role != 1) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (role != 0) _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        bytes32 queued = _queueDigest(id);
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.mockCallRevert(address(_risk), abi.encodeWithSignature("kernel()"), hex"ff");
        vm.expectEmit(address(_timelock));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(caller_, false, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _timelock.disable("");
        assertFalse(_timelock.isEnabled(), "paused independently of target");
        assertEq(_timelock.lastTransitionAt(), vm.getBlockTimestamp(), "pause time");
        assertEq(_queueDigest(id), queued, "pause preserves intent");
    }

    // Scenarios: BLRCT-DISABLE-A01.
    function test_whenUnauthorized_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.disable("");
    }

    // Scenarios: BLRCT-DISABLE-L01.
    function test_givenDisabled_whenDisabledAgain_reverts(address caller_) public {
        _timelock.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _timelock.disable(hex"01");
    }

    // Scenarios: BLRCT-DISABLE-I01.
    function test_whenNonemptyPayload_reverts(bytes memory data_) public {
        vm.assume(data_.length > 0);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _timelock.disable(data_);
    }

    // Scenarios: BLRCT-DISABLE-P02.
    function test_givenDisabled_whenPendingCancelled() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _timelock.disable("");
        _timelock.cancelQueuedAction(id);
        assertTrue(_timelock.getQueuedAction(id).cancelled, "pause permits cancellation");
    }
}
