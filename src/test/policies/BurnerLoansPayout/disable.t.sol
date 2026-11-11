// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";

contract BurnerLoansPayoutDisableTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-DISABLE-L01, BLCU-DISABLE-L02.
    function test_givenPermittedCaller_whenDisabled_thenExactTransition(
        address caller_,
        bool emergency_,
        bool overlap_,
        bool active_
    ) public givenPendingBuckets {
        _grantPauseCaller(caller_, emergency_, overlap_);
        _setState(_payout, active_, true);
        bytes32 state = _ledgerDigest();
        vm.warp(2);
        vm.expectEmit(address(_payout));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_payout));
        emit IEnablerV2.Transition(caller_, false, "", 2);
        vm.prank(caller_);
        _payout.disable("");
        assertFalse(_payout.isEnabled(), "Paused");
        assertEq(_payout.lastTransitionAt(), 2, "Exact history");
        assertEq(_payout.isActive(), active_, "Kernel membership preserved");
        assertEq(_ledgerDigest(), state, "Pause preserves custody and obligations");
    }

    // Scenarios: BLCU-DISABLE-A01.
    function test_whenCallerLacksPauseRoles_reverts(address caller_) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        _expectDisableRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_,
            ""
        );
    }

    // Scenarios: BLCU-DISABLE-L03, BLCU-DISABLE-L04.
    function test_givenAlreadyPaused_whenDisabled_reverts(
        bool active_,
        address caller_,
        bool emergency_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantPauseCaller(caller_, emergency_, overlap_);
        _setState(_payout, active_, false);
        _expectDisableRejected(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_, "");
    }

    // Scenarios: BLCU-DISABLE-I01.
    function test_whenNonemptyData_reverts(
        bytes memory data_,
        address caller_,
        bool emergency_,
        bool overlap_
    ) public givenPendingBuckets {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _grantPauseCaller(caller_, emergency_, overlap_);
        _expectDisableRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector),
            caller_,
            data_
        );
    }

    // Scenarios: BLCU-DISABLE-I01.
    function test_whenNonemptyDataAtBoundaries_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenNonemptyData_reverts(hex"00", address(0xabc1), false, false);
        _restore(checkpoint);
        test_whenNonemptyData_reverts(abi.encode(uint256(0)), address(0xabc2), true, false);
        _restore(checkpoint);
        test_whenNonemptyData_reverts(new bytes(256), address(0xabc3), false, true);
    }

    // Scenarios: BLCU-DISABLE-L01, BLCU-DISABLE-L02.
    function test_givenEachPauseRole_whenDisabled_thenExactTransition() public {
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

    // Scenarios: BLCU-DISABLE-C02.
    function test_givenCoreBusy_whenDisabled_reverts(
        address caller_,
        bool emergency_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantPauseCaller(caller_, emergency_, overlap_);
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.requireNotReentrant, ()),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
        );
        _expectDisableRejected(
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            caller_,
            ""
        );
    }

    function _expectDisableRejected(
        bytes memory reason_,
        address caller_,
        bytes memory data_
    ) internal {
        bytes32 state = _ledgerDigest();
        bool enabled = _payout.isEnabled();
        uint48 last = _payout.lastTransitionAt();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.disable(data_);
        assertEq(_payout.isEnabled(), enabled, "Failed disable preserves state");
        assertEq(_payout.lastTransitionAt(), last, "Failed disable preserves history");
        assertEq(_ledgerDigest(), state, "Failed disable preserves obligations and balances");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
