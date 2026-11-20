// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";

contract BurnerLoansCoreDisableTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-DISABLE-A01, BLCORE-DISABLE-L01, BLCORE-DISABLE-L02.
    function test_whenDisablingRoleClassesSeeded() public {
        uint256 snapshot = vm.snapshotState();
        test_givenAuthorized_whenDisabled(_recipient, true, false, true);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenAuthorized_whenDisabled(_recipient, false, false, false);
        vm.revertToState(snapshot);
        test_givenAuthorized_whenDisabled(_recipient, true, true, true);
    }

    // Scenarios: BLCORE-DISABLE-A01, BLCORE-DISABLE-L01, BLCORE-DISABLE-L02.
    function test_givenAuthorized_whenDisabled(
        address caller_,
        bool admin_,
        bool overlap_,
        bool active_
    ) public {
        _grantLifecycleCaller(caller_, EMERGENCY_ROLE, admin_, overlap_);
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        bytes32 ledger = _ledger();
        vm.expectEmit(false, false, false, true, address(_core));
        emit IEnabler.Disabled();
        vm.expectEmit(true, false, false, true, address(_core));
        emit IEnablerV2.Transition(caller_, false, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _core.disable("");
        assertFalse(_core.isEnabled(), "Authorized pause succeeds even when inactive");
        assertEq(_core.lastTransitionAt(), vm.getBlockTimestamp(), "Pause timestamp");
        assertEq(_ledger(), ledger, "Pause preserves custody");
    }

    // Scenarios: BLCORE-DISABLE-A03, BLCORE-DISABLE-I04.
    function test_givenUnauthorized_whenDisabled_reverts(address caller_, bool payload_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _core.disable(payload_ ? bytes(hex"01") : bytes(""));
        assertTrue(_core.isEnabled(), "Unauthorized pause preserves flag");
    }

    // Scenarios: BLCORE-DISABLE-L03, BLCORE-DISABLE-L04, BLCORE-DISABLE-I03.
    function test_givenAlreadyDisabled_whenDisabled_reverts(
        address caller_,
        bool active_,
        bool payload_
    ) public {
        _setCoreLifecycle(active_, false);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _core.disable(payload_ ? bytes(hex"01") : bytes(""));
    }

    // Scenarios: BLCORE-DISABLE-I01.
    function test_givenPayload_whenDisabled_reverts(bytes memory payload_) public {
        vm.assume(payload_.length > 0);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _core.disable(payload_);
        assertTrue(_core.isEnabled(), "Invalid payload cannot pause");
    }

    // Scenarios: BLCORE-DISABLE-L05.
    function test_givenNeverConfigured_whenDisabled_reverts() public {
        BurnerLoansCore fresh = new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            _depositManager
        );
        vm.expectRevert(IEnabler.NotEnabled.selector);
        fresh.disable("");
    }

    // Scenarios: BLCORE-DISABLE-C01.
    function test_givenBusyCore_whenAdminDisables_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("disable(bytes)", bytes("")),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized pause cannot interrupt settlement"
        );
        assertTrue(_core.isEnabled(), "Nested pause leaves flag enabled");
    }

    // Scenarios: BLCORE-DISABLE-C02.
    function test_givenBusyCore_whenEmergencyDisables_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("disable(bytes)", bytes("")),
            false
        );
        _rolesAdmin.revokeRole(ADMIN_ROLE, address(token));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(token));
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized pause cannot interrupt settlement"
        );
        assertTrue(_core.isEnabled(), "Nested pause leaves flag enabled");
    }

    // Scenarios: BLCORE-DISABLE-I05.
    function test_givenBusyCore_whenPayloadDisables_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("disable(bytes)", hex"01"),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized pause cannot interrupt settlement"
        );
        assertTrue(_core.isEnabled(), "Nested pause leaves flag enabled");
    }
}
