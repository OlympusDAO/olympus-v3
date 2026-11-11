// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, reentrancy-no-eth)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansInventoryConfigTimelock} from "src/policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol";

contract BurnerLoansInventoryConfigTimelockReEnableTest is BurnerLoansInventoryConfigTimelockTest {
    // Scenarios: BLINCT-REENABLE-A01, BLINCT-REENABLE-D01.
    function test_givenReadyTarget_whenActivated_thenExactTransition(
        address caller_,
        bool inventoryEnabled_,
        bool blAdmin_,
        bool overlap_
    ) public givenProviderSurplus givenPendingRecovery {
        _timelock.disable("");
        _setState(_inventory, true, inventoryEnabled_);
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        bytes32 beforeQueue = _queueDigest(_pendingId);
        vm.warp(2);
        vm.expectEmit(address(_timelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(caller_, true, "", 2);
        vm.prank(caller_);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "Activation succeeds");
        assertEq(_timelock.lastTransitionAt(), 2, "Exact activation timestamp");
        assertEq(
            _queueDigest(_pendingId),
            beforeQueue,
            "Activation preserves all queued work and Inventory accounting"
        );
        assertEq(_inventory.isEnabled(), inventoryEnabled_, "Target enabled flag preserved");
    }

    // Scenarios: BLINCT-REENABLE-A02.
    function test_givenUnauthorizedCaller_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _timelock.disable("");
        _expectActivationRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLINCT-REENABLE-L01.
    function test_givenOwnPolicyInactive_whenActivated_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        _setState(_timelock, false, false);
        _expectActivationRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-REENABLE-L02, BLINCT-REENABLE-L03.
    function test_givenAlreadyEnabled_whenActivated_reverts(
        bool active_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        _setState(_timelock, active_, true);
        _expectActivationRejected(abi.encodeWithSelector(IEnabler.NotDisabled.selector), caller_);
    }

    // Scenarios: BLINCT-REENABLE-D03, BLINCT-REENABLE-D04.
    function test_givenInventoryInactive_whenActivated_reverts(
        bool enabled_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        _timelock.disable("");
        _setState(_inventory, false, enabled_);
        _expectActivationRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-REENABLE-D02.
    function test_givenAnotherController_whenActivated_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        _timelock.disable("");
        _inventory.setConfigOperator(_inventoryConfigurator);
        _expectActivationRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLINCT-REENABLE-D06.
    function test_givenClearedController_whenActivated_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        _timelock.disable("");
        _inventory.setConfigOperator(address(0));
        _expectActivationRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLINCT-REENABLE-D05.
    function test_givenTargetKernelDrift_whenActivated_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
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
            caller_
        );
    }

    function _expectActivationRejected(bytes memory reason_, address caller_) internal {
        bytes32 beforeQueue = _queueDigest(_pendingId);
        uint48 last = _timelock.lastTransitionAt();
        bool enabled = _timelock.isEnabled();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.reEnable();
        assertEq(_timelock.isEnabled(), enabled, "Failed activation preserves local state");
        assertEq(_timelock.lastTransitionAt(), last, "Failed activation preserves history");
        assertEq(
            _queueDigest(_pendingId),
            beforeQueue,
            "Failed activation preserves queue, key, balances, claims and mint approval"
        );
    }

    // Scenarios: BLINCT-REENABLE-N01.
    function test_givenNeverEnabled_whenReEnabled_reverts(
        address caller_,
        bool active_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        BurnerLoansInventoryConfigTimelock fresh = new BurnerLoansInventoryConfigTimelock(
            _kernel,
            _inventory
        );
        if (active_) _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertFalse(fresh.isEnabled(), "Uninitialized remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "No history created");
    }

    // Scenarios: BLINCT-REENABLE-N02, BLINCT-REENABLE-A01.
    function test_givenWithinGrace_whenReEnabled_thenInclusiveTransition(
        uint48 last_,
        uint32 grace_,
        uint48 now_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        last_ = SafeCast.toUint48(bound(last_, 1, uint256(type(uint48).max) - grace_));
        now_ = SafeCast.toUint48(bound(now_, last_, uint256(last_) + grace_));
        vm.warp(last_);
        _timelock.setGracePeriod(grace_);
        _timelock.disable("");
        vm.warp(now_);
        bytes32 beforeQueue = _queueDigest(_pendingId);
        vm.expectEmit(address(_timelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.prank(caller_);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "Inclusive grace permits activation");
        assertEq(_timelock.lastTransitionAt(), now_, "Exact transition time");
        assertEq(_queueDigest(_pendingId), beforeQueue, "Grace transition preserves pending work");
    }

    // Scenarios: BLINCT-REENABLE-N03.
    function test_givenExpiredGrace_whenReEnabled_reverts(
        uint48 last_,
        uint32 grace_,
        uint48 now_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        last_ = SafeCast.toUint48(bound(last_, 1, uint256(type(uint48).max) - grace_ - 1));
        uint48 deadline = last_ + grace_;
        now_ = SafeCast.toUint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.warp(last_);
        _timelock.setGracePeriod(grace_);
        _timelock.disable("");
        vm.warp(now_);
        _expectActivationRejected(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline),
            caller_
        );
    }

    // Scenarios: BLINCT-REENABLE-N04.
    function test_givenGraceOverflow_whenReEnabled_reverts(
        uint32 grace_,
        uint48 last_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantRecoveryAdmin(caller_, blAdmin_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        last_ = SafeCast.toUint48(
            bound(last_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max)
        );
        _timelock.setGracePeriod(grace_);
        vm.warp(last_);
        _timelock.disable("");
        _expectActivationRejected(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(last_) + grace_
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-REENABLE-A01, BLINCT-REENABLE-D01.
    function test_givenEachPermittedRole_whenReEnabled_thenExactTransition() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenReadyTarget_whenActivated_thenExactTransition(
            address(0xabc1),
            true,
            false,
            false
        );
        _restore(checkpoint);
        test_givenReadyTarget_whenActivated_thenExactTransition(address(0xabc2), true, true, false);
        _restore(checkpoint);
        test_givenReadyTarget_whenActivated_thenExactTransition(address(0xabc3), true, false, true);
        _restore(checkpoint);
        test_givenReadyTarget_whenActivated_thenExactTransition(
            address(0xabc1),
            false,
            false,
            false
        );
        _restore(checkpoint);
        test_givenReadyTarget_whenActivated_thenExactTransition(
            address(0xabc2),
            false,
            true,
            false
        );
        _restore(checkpoint);
        test_givenReadyTarget_whenActivated_thenExactTransition(
            address(0xabc3),
            false,
            false,
            true
        );
    }

    // Scenarios: BLINCT-REENABLE-N02, BLINCT-REENABLE-A01.
    function test_givenGraceEndpointSeeds_whenReEnabled_thenInclusiveTransition() public {
        uint256 checkpoint = vm.snapshotState();
        uint32[2] memory periods = [uint32(1), type(uint32).max];
        for (uint256 i; i < periods.length; ++i) {
            uint32 period = periods[i];
            uint48[2] memory starts = [uint48(1), type(uint48).max - period];
            for (uint256 j; j < starts.length; ++j) {
                uint48 last = starts[j];
                uint48 deadline = last + period;
                test_givenWithinGrace_whenReEnabled_thenInclusiveTransition(
                    last,
                    period,
                    last,
                    address(0xabc1),
                    false,
                    false
                );
                _restore(checkpoint);
                test_givenWithinGrace_whenReEnabled_thenInclusiveTransition(
                    last,
                    period,
                    deadline - 1,
                    address(0xabc2),
                    true,
                    false
                );
                _restore(checkpoint);
                test_givenWithinGrace_whenReEnabled_thenInclusiveTransition(
                    last,
                    period,
                    deadline,
                    address(0xabc3),
                    false,
                    true
                );
                _restore(checkpoint);
            }
        }
    }

    // Scenarios: BLINCT-REENABLE-N03.
    function test_givenExpiredGraceEndpointSeeds_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        uint32[2] memory periods = [uint32(1), type(uint32).max];
        for (uint256 i; i < periods.length; ++i) {
            uint32 period = periods[i];
            uint48[2] memory starts = [uint48(1), type(uint48).max - period - 1];
            for (uint256 j; j < starts.length; ++j) {
                test_givenExpiredGrace_whenReEnabled_reverts(
                    starts[j],
                    period,
                    starts[j] + period + 1,
                    address(0xabc1),
                    false,
                    false
                );
                _restore(checkpoint);
                test_givenExpiredGrace_whenReEnabled_reverts(
                    starts[j],
                    period,
                    type(uint48).max,
                    address(0xabc2),
                    true,
                    false
                );
                _restore(checkpoint);
            }
        }
    }

    // Scenarios: BLINCT-REENABLE-N04.
    function test_givenGraceOverflowEndpointSeeds_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        uint32[2] memory periods = [uint32(1), type(uint32).max];
        for (uint256 i; i < periods.length; ++i) {
            uint32 period = periods[i];
            test_givenGraceOverflow_whenReEnabled_reverts(
                period,
                type(uint48).max - period + 1,
                address(0xabc1),
                false,
                false
            );
            _restore(checkpoint);
            test_givenGraceOverflow_whenReEnabled_reverts(
                period,
                type(uint48).max,
                address(0xabc2),
                true,
                false
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLINCT-REENABLE-L01.
    function test_givenOwnPolicyInactive_whenEachPermittedRoleReEnables_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenOwnPolicyInactive_whenActivated_reverts(address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenOwnPolicyInactive_whenActivated_reverts(address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenOwnPolicyInactive_whenActivated_reverts(address(0xabc3), false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLINCT-REENABLE-L02, BLINCT-REENABLE-L03.
    function test_givenAlreadyEnabled_whenEachPermittedRoleReEnables_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAlreadyEnabled_whenActivated_reverts(true, address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenAlreadyEnabled_whenActivated_reverts(true, address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenAlreadyEnabled_whenActivated_reverts(true, address(0xabc3), false, true);
        _restore(checkpoint);
        test_givenAlreadyEnabled_whenActivated_reverts(false, address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenAlreadyEnabled_whenActivated_reverts(false, address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenAlreadyEnabled_whenActivated_reverts(false, address(0xabc3), false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLINCT-REENABLE-D03, BLINCT-REENABLE-D04.
    function test_givenInventoryInactive_whenEachPermittedRoleReEnables_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenInventoryInactive_whenActivated_reverts(true, address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenInventoryInactive_whenActivated_reverts(true, address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenInventoryInactive_whenActivated_reverts(true, address(0xabc3), false, true);
        _restore(checkpoint);
        test_givenInventoryInactive_whenActivated_reverts(false, address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenInventoryInactive_whenActivated_reverts(false, address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenInventoryInactive_whenActivated_reverts(false, address(0xabc3), false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLINCT-REENABLE-D02.
    function test_givenAnotherController_whenEachPermittedRoleReEnables_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAnotherController_whenActivated_reverts(address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenAnotherController_whenActivated_reverts(address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenAnotherController_whenActivated_reverts(address(0xabc3), false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLINCT-REENABLE-D06.
    function test_givenClearedController_whenEachPermittedRoleReEnables_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenClearedController_whenActivated_reverts(address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenClearedController_whenActivated_reverts(address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenClearedController_whenActivated_reverts(address(0xabc3), false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLINCT-REENABLE-D05.
    function test_givenTargetKernelDrift_whenEachPermittedRoleReEnables_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenTargetKernelDrift_whenActivated_reverts(address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenTargetKernelDrift_whenActivated_reverts(address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenTargetKernelDrift_whenActivated_reverts(address(0xabc3), false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLINCT-REENABLE-N01.
    function test_givenNeverEnabled_whenEachPermittedRoleReEnables_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNeverEnabled_whenReEnabled_reverts(address(0xabc1), true, false, false);
        _restore(checkpoint);
        test_givenNeverEnabled_whenReEnabled_reverts(address(0xabc2), true, true, false);
        _restore(checkpoint);
        test_givenNeverEnabled_whenReEnabled_reverts(address(0xabc3), true, false, true);
        _restore(checkpoint);
        test_givenNeverEnabled_whenReEnabled_reverts(address(0xabc1), false, false, false);
        _restore(checkpoint);
        test_givenNeverEnabled_whenReEnabled_reverts(address(0xabc2), false, true, false);
        _restore(checkpoint);
        test_givenNeverEnabled_whenReEnabled_reverts(address(0xabc3), false, false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLINCT-REENABLE-D07.
    function test_givenMissingConsumedInterface_whenActivated_reverts(bool enabled_) public {
        _timelock.disable("");
        _setState(_inventory, true, enabled_);
        bytes4[3] memory ids = [
            type(IBurnerLoansInventory).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        for (uint256 i; i < ids.length; ++i) {
            vm.mockCall(
                address(_inventory),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(false)
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansInventoryConfigTimelock
                        .BurnerLoansInventoryTimelock_InvalidInventory
                        .selector,
                    address(_inventory)
                )
            );
            _timelock.reEnable();
            assertFalse(_timelock.isEnabled(), "Incompatible target cannot activate queue");
            vm.mockCall(
                address(_inventory),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(true)
            );
        }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, reentrancy-no-eth)
