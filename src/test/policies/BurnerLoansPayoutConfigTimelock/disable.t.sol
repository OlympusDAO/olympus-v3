// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";

contract BurnerLoansPayoutConfigTimelockDisableTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCUCT-DISABLE-A01, BLCUCT-DISABLE-L01, BLCUCT-DISABLE-L02, BLCUCT-DISABLE-I01, BLCUCT-DISABLE-D01.
    function test_givenPermittedCaller_whenDisabled_thenExactTransition(
        address caller_,
        bool emergency_,
        bool overlap_,
        bool active_
    ) public givenPendingRecovery {
        vm.assume(caller_ != address(0) && caller_ != address(this) && caller_ != _recipient);
        _grantRoleIfMissing(emergency_ ? EMERGENCY_ROLE : ADMIN_ROLE, caller_);
        if (overlap_) _grantRoleIfMissing(emergency_ ? ADMIN_ROLE : EMERGENCY_ROLE, caller_);
        _setState(_payoutTimelock, active_, true);
        _payout.setConfigOperator(_recipient);
        _rejectTargetReads();
        bytes32 beforeQueue = _queueDigest(_pendingId);
        vm.warp(2);
        vm.recordLogs();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnablerV2.Transition(caller_, false, "", 2);
        vm.prank(caller_);
        _payoutTimelock.disable("");
        assertFalse(_payoutTimelock.isEnabled(), "Disabled without target reads");
        assertEq(_payoutTimelock.lastTransitionAt(), 2, "Exact transition time");
        assertEq(_timelockLogCount(), 2, "Exactly one transition pair");
        assertEq(_queueDigest(_pendingId), beforeQueue, "Queue and keys preserved");
    }

    // Scenarios: BLCUCT-DISABLE-A02.
    function test_givenUnauthorizedCaller_whenDisabled_reverts(
        address caller_,
        bytes memory data_
    ) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.disable, (data_)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-DISABLE-L03, BLCUCT-DISABLE-L04.
    function test_givenDisabled_whenDisabled_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, active_, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.disable, (data_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-DISABLE-I02.
    function test_whenNonemptyPayload_reverts(
        address caller_,
        bool emergency_,
        bool overlap_,
        bytes memory data_
    ) public givenPendingRecovery {
        vm.assume(caller_ != address(0));
        vm.assume(data_.length > 0 && data_.length <= 256);
        _grantRoleIfMissing(emergency_ ? EMERGENCY_ROLE : ADMIN_ROLE, caller_);
        if (overlap_) _grantRoleIfMissing(emergency_ ? ADMIN_ROLE : EMERGENCY_ROLE, caller_);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.disable, (data_)),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-DISABLE-A01, BLCUCT-DISABLE-L01, BLCUCT-DISABLE-L02, BLCUCT-DISABLE-I01, BLCUCT-DISABLE-I02, BLCUCT-DISABLE-D01.
    function test_whenRoleAndPayloadSeedsUsed() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 a; a < 2; ++a) {
            test_givenPermittedCaller_whenDisabled_thenExactTransition(
                address(0x111),
                false,
                false,
                a != 0
            );
            _restore(checkpoint);
            test_givenPermittedCaller_whenDisabled_thenExactTransition(
                address(0x112),
                true,
                false,
                a != 0
            );
            _restore(checkpoint);
            test_givenPermittedCaller_whenDisabled_thenExactTransition(
                address(0x113),
                false,
                true,
                a != 0
            );
            _restore(checkpoint);
        }
        test_whenNonemptyPayload_reverts(address(0x111), false, false, new bytes(1));
        _restore(checkpoint);
        test_whenNonemptyPayload_reverts(address(0x112), true, false, abi.encode(uint256(0)));
        _restore(checkpoint);
        test_whenNonemptyPayload_reverts(address(0x113), false, true, new bytes(256));
        _restore(checkpoint);
    }

    // Scenarios: BLCUCT-DISABLE-I02.
    function test_givenExistingAdmin_whenNonemptyDisablePayload_reverts() public {
        test_whenNonemptyPayload_reverts(address(this), false, true, hex"01");
    }
}
