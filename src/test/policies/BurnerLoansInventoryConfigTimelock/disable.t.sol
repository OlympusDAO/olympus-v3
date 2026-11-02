// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, reentrancy-no-eth)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";

contract BurnerLoansInventoryConfigTimelockDisableTest is BurnerLoansInventoryConfigTimelockTest {
    // Scenarios: BLINCT-DISABLE-A01, BLINCT-DISABLE-L01, BLINCT-DISABLE-L02.
    function test_givenPermittedCaller_whenDisabled_thenExactTransition(
        address caller_,
        bool emergency_,
        bool overlap_,
        bool active_
    ) public givenProviderSurplus givenPendingRecovery {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(emergency_ ? EMERGENCY_ROLE : ADMIN_ROLE, caller_);
        if (overlap_) _rolesAdmin.grantRole(emergency_ ? ADMIN_ROLE : EMERGENCY_ROLE, caller_);
        _setState(_timelock, active_, true);
        bytes32 state = _queueDigest(_pendingId);
        vm.warp(2);
        vm.expectEmit(address(_timelock));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_timelock));
        emit IEnablerV2.Transition(caller_, false, "", 2);
        vm.prank(caller_);
        _timelock.disable("");
        assertFalse(_timelock.isEnabled(), "Disabled locally");
        assertEq(_timelock.lastTransitionAt(), 2, "Exact disable timestamp");
        assertEq(_timelock.isActive(), active_, "Own membership unchanged");
        assertEq(_queueDigest(_pendingId), state, "Pause preserves all queued work and funds");
    }

    // Scenarios: BLINCT-DISABLE-A02.
    function test_givenUnauthorizedCaller_whenDisabled_reverts(
        address caller_
    ) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        _expectDisableRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_,
            ""
        );
    }

    // Scenarios: BLINCT-DISABLE-L03, BLINCT-DISABLE-L04.
    function test_givenAlreadyDisabled_whenDisabled_reverts(
        bool active_,
        address caller_
    ) public givenPendingRecovery {
        _setState(_timelock, active_, false);
        _expectDisableRejected(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_, "");
    }

    // Scenarios: BLINCT-DISABLE-I01.
    function test_givenNonemptyData_whenDisabled_reverts(
        bytes memory data_
    ) public givenPendingRecovery {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _expectDisableRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector),
            address(this),
            data_
        );
    }

    function _expectDisableRejected(
        bytes memory reason_,
        address caller_,
        bytes memory data_
    ) internal {
        bytes32 state = _queueDigest(_pendingId);
        uint48 last = _timelock.lastTransitionAt();
        bool enabled = _timelock.isEnabled();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.disable(data_);
        assertEq(_timelock.isEnabled(), enabled, "Failed disable preserves state");
        assertEq(_timelock.lastTransitionAt(), last, "Failed disable preserves history");
        assertEq(_queueDigest(_pendingId), state, "Failed disable preserves queue and funds");
    }

    // Scenarios: BLINCT-DISABLE-D01.
    function test_givenInactiveInventory_whenDisabled_thenNoDependencyRead()
        public
        givenPendingRecovery
    {
        _setState(_inventory, false, true);
        _disableWithoutReadiness();
    }

    // Scenarios: BLINCT-DISABLE-D02.
    function test_givenPausedInventory_whenDisabled_thenNoDependencyRead()
        public
        givenPendingRecovery
    {
        _inventory.disable("");
        _disableWithoutReadiness();
    }

    // Scenarios: BLINCT-DISABLE-D03.
    function test_givenInventoryKernelMismatch_whenDisabled_thenNoDependencyRead()
        public
        givenPendingRecovery
    {
        _mockInventoryKernel(address(0xbeef));
        _disableWithoutReadiness();
    }

    // Scenarios: BLINCT-DISABLE-D04.
    function test_givenControllerReplaced_whenDisabled_thenNoDependencyRead()
        public
        givenPendingRecovery
    {
        _inventory.setConfigOperator(_inventoryConfigurator);
        _disableWithoutReadiness();
    }

    // Scenarios: BLINCT-DISABLE-I01.
    function test_givenNonemptyPayloadBoundaries_whenCalled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNonemptyData_whenDisabled_reverts(hex"00");
        _restore(checkpoint);
        test_givenNonemptyData_whenDisabled_reverts(hex"01");
        _restore(checkpoint);
        test_givenNonemptyData_whenDisabled_reverts(abi.encode(uint256(0)));
        _restore(checkpoint);
        test_givenNonemptyData_whenDisabled_reverts(new bytes(256));
    }

    // Scenarios: BLINCT-DISABLE-A01, BLINCT-DISABLE-L01, BLINCT-DISABLE-L02.
    function test_givenEachPermittedRole_whenDisabled_thenExactTransition() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            test_givenPermittedCaller_whenDisabled_thenExactTransition(
                address(0xabc1),
                false,
                false,
                active != 0
            );
            _restore(checkpoint);
            test_givenPermittedCaller_whenDisabled_thenExactTransition(
                address(0xabc2),
                true,
                false,
                active != 0
            );
            _restore(checkpoint);
            test_givenPermittedCaller_whenDisabled_thenExactTransition(
                address(0xabc3),
                false,
                true,
                active != 0
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLINCT-DISABLE-A02.
    function test_givenBurnerLoansAdminOnly_whenDisabled_reverts() public {
        test_givenUnauthorizedCaller_whenDisabled_reverts(_recipient);
    }

    function _disableWithoutReadiness() internal {
        _rejectInventoryReadinessReads();
        bytes32 state = _queueDigest(_pendingId);
        _timelock.disable("");
        assertFalse(_timelock.isEnabled(), "Broken target cannot prevent pause");
        assertEq(_queueDigest(_pendingId), state, "Pause preserves pending work and key");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, reentrancy-no-eth)
