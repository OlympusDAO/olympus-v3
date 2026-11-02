// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansInventoryConfigTimelockEnableTest is BurnerLoansInventoryConfigTimelockTest {
    // Scenarios: BLINCT-ENABLE-A01, BLINCT-ENABLE-D01.
    function test_givenReadyTarget_whenActivated_thenExactTransition(
        address caller_,
        bool inventoryEnabled_
    ) public givenProviderSurplus givenPendingRecovery {
        vm.assume(caller_ != address(0) && caller_ != address(this) && caller_ != _recipient);
        _timelock.disable("");
        _setState(_inventory, true, inventoryEnabled_);
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        bytes32 beforeQueue = _queueDigest(_pendingId);
        vm.warp(2);
        vm.expectEmit(address(_timelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(caller_, true, "", 2);
        vm.prank(caller_);
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "Activation succeeds");
        assertEq(_timelock.lastTransitionAt(), 2, "Exact activation timestamp");
        assertEq(
            _queueDigest(_pendingId),
            beforeQueue,
            "Activation preserves all queued work and Inventory accounting"
        );
        assertEq(_inventory.isEnabled(), inventoryEnabled_, "Target enabled flag preserved");
    }

    // Scenarios: BLINCT-ENABLE-A02.
    function test_givenUnauthorizedCaller_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _timelock.disable("");
        _expectActivationRejected(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE),
            caller_
        );
    }

    // Scenarios: BLINCT-ENABLE-L01.
    function test_givenOwnPolicyInactive_whenActivated_reverts() public givenPendingRecovery {
        _setState(_timelock, false, false);
        _expectActivationRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-ENABLE-L02, BLINCT-ENABLE-L03.
    function test_givenAlreadyEnabled_whenActivated_reverts(
        bool active_,
        address caller_
    ) public givenPendingRecovery {
        _setState(_timelock, active_, true);
        _expectActivationRejected(abi.encodeWithSelector(IEnabler.NotDisabled.selector), caller_);
    }

    // Scenarios: BLINCT-ENABLE-D03, BLINCT-ENABLE-D04.
    function test_givenInventoryInactive_whenActivated_reverts(
        bool enabled_
    ) public givenPendingRecovery {
        _timelock.disable("");
        _setState(_inventory, false, enabled_);
        _expectActivationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-ENABLE-D02.
    function test_givenAnotherController_whenActivated_reverts() public givenPendingRecovery {
        _timelock.disable("");
        _inventory.setConfigOperator(_inventoryConfigurator);
        _expectActivationRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            address(this)
        );
    }

    // Scenarios: BLINCT-ENABLE-D06.
    function test_givenClearedController_whenActivated_reverts() public givenPendingRecovery {
        _timelock.disable("");
        _inventory.setConfigOperator(address(0));
        _expectActivationRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            address(this)
        );
    }

    // Scenarios: BLINCT-ENABLE-D05.
    function test_givenTargetKernelDrift_whenActivated_reverts() public givenPendingRecovery {
        _timelock.disable("");
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _inventory.changeKernel(next);
        _expectActivationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_inventory),
                address(_kernel),
                address(next)
            ),
            address(this)
        );
    }

    function _expectActivationRejected(bytes memory reason_, address caller_) internal {
        bytes32 beforeQueue = _queueDigest(_pendingId);
        uint48 last = _timelock.lastTransitionAt();
        bool enabled = _timelock.isEnabled();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.enable("");
        assertEq(_timelock.isEnabled(), enabled, "Failed activation preserves local state");
        assertEq(_timelock.lastTransitionAt(), last, "Failed activation preserves history");
        assertEq(
            _queueDigest(_pendingId),
            beforeQueue,
            "Failed activation preserves queue, key, balances, claims and mint approval"
        );
    }

    // Scenarios: BLINCT-ENABLE-D01.
    function test_givenInventoryDisabled_whenTimelockEnabled_thenRecoveryRemainsAvailable() public {
        _timelock.disable("");
        _inventory.disable("");
        _timelock.enable("");
        assertTrue(_timelock.isEnabled(), "Paused Inventory can acquire a recovery controller");
        uint64 id = _timelock.queueRescueSurplus();
        assertEq(
            _timelock.getQueuedActionLength(id),
            1,
            "Recovery can be queued while Inventory paused"
        );
    }

    // Scenarios: BLINCT-ENABLE-I01.
    function test_givenNonemptyData_whenEnabled_reverts(
        bytes memory data_
    ) public givenPendingRecovery {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _timelock.disable("");
        bytes32 state = _queueDigest(_pendingId);
        uint48 last = _timelock.lastTransitionAt();
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _timelock.enable(data_);
        assertFalse(_timelock.isEnabled(), "Invalid data cannot activate");
        assertEq(_timelock.lastTransitionAt(), last, "History preserved");
        assertEq(_queueDigest(_pendingId), state, "Invalid data preserves queued work and funds");
    }

    // Scenarios: BLINCT-ENABLE-I01.
    function test_givenNonemptyPayloadBoundaries_whenCalled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNonemptyData_whenEnabled_reverts(hex"00");
        _restore(checkpoint);
        test_givenNonemptyData_whenEnabled_reverts(hex"01");
        _restore(checkpoint);
        test_givenNonemptyData_whenEnabled_reverts(abi.encode(uint256(0)));
        _restore(checkpoint);
        test_givenNonemptyData_whenEnabled_reverts(new bytes(256));
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth)
