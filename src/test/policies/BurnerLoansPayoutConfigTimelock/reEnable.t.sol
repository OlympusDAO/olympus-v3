// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansPayoutConfigTimelock} from "src/policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol";

contract BurnerLoansPayoutConfigTimelockReEnableTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCUCT-REENABLE-A01, BLCUCT-REENABLE-L03, BLCUCT-REENABLE-D06.
    function test_givenReadyBinding_whenActivated_thenExactTransition(
        address caller_,
        bool bl_,
        bool overlap_,
        bool payoutEnabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        _payoutTimelock.disable("");
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, true, payoutEnabled_);
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        bytes32 beforeQueue = _queueDigest(_pendingId);
        bytes32 funds = _payoutDigest();
        vm.warp(2);
        vm.recordLogs();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnablerV2.Transition(caller_, true, "", 2);
        vm.prank(caller_);
        _payoutTimelock.reEnable();
        assertEq(_timelockLogCount(), 2, "Exactly one legacy and one transition event");
        assertTrue(_payoutTimelock.isEnabled(), "Enabled");
        assertEq(_payoutTimelock.lastTransitionAt(), 2, "Exact activation time");
        assertEq(_queueDigest(_pendingId), beforeQueue, "Queue preserved");
        assertEq(_payoutDigest(), funds, "Target preserved");
    }

    // Scenarios: BLCUCT-REENABLE-A02.
    function test_givenUnauthorizedCaller_whenActivated_reverts(
        address caller_
    ) public givenPendingRecovery {
        _excludeProposers(caller_);
        _payoutTimelock.disable("");
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-L01, BLCUCT-REENABLE-L02.
    function test_givenAlreadyEnabled_whenActivated_reverts(
        address caller_,
        bool active_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, active_, true);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(IEnabler.NotDisabled.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-L04.
    function test_givenInactivePolicy_whenActivated_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        _setState(_payoutTimelock, false, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-D01.
    function test_givenWrongKernel_whenActivated_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        address other_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        vm.assume(other_ != address(_kernel));
        _payoutTimelock.disable("");
        _mockPayoutKernel(other_);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_payout),
                address(_kernel),
                other_
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-D02.
    function test_givenControllerChanged_whenActivated_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        _payoutTimelock.disable("");
        _payout.setConfigOperator(_recipient);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(
                IBurnerLoansPayoutConfigTimelock.BurnerLoansPayoutTimelock_NotController.selector
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-D04.
    function test_givenKernelGetterReverts_whenActivated_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        _payoutTimelock.disable("");
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_payout)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-D05.
    function test_givenControllerGetterReverts_whenActivated_reverts(
        address caller_,
        bool bl_,
        bool overlap_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        _payoutTimelock.disable("");
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(
                IBurnerLoansPayoutConfigTimelock.BurnerLoansPayoutTimelock_InvalidPayout.selector,
                address(_payout)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-I01.
    function test_givenNeverEnabled_whenReEnabled_reverts(address caller_, bool active_) public {
        BurnerLoansPayoutConfigTimelock fresh = new BurnerLoansPayoutConfigTimelock(
            _kernel,
            _payout
        );
        if (active_) _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertFalse(fresh.isEnabled(), "No uninitialized activation");
        assertEq(fresh.lastTransitionAt(), 0, "No history");
    }

    // Scenarios: BLCUCT-REENABLE-N01, BLCUCT-REENABLE-N02.
    function test_givenWithinGrace_whenReEnabled_thenExactTransition(
        address caller_,
        bool bl_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_));
        now_ = uint48(bound(now_, last_, uint256(last_) + grace_));
        _payoutTimelock.setGracePeriod(grace_);
        vm.warp(last_);
        _payoutTimelock.disable("");
        vm.warp(now_);
        bytes32 queue = _queueDigest(_pendingId);
        vm.recordLogs();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_payoutTimelock));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.prank(caller_);
        _payoutTimelock.reEnable();
        assertEq(_timelockLogCount(), 2, "Exactly one transition pair");
        assertEq(_payoutTimelock.lastTransitionAt(), now_, "Exact time");
        assertEq(_queueDigest(_pendingId), queue, "Queue preserved");
    }

    // Scenarios: BLCUCT-REENABLE-N03.
    function test_givenExpiredGrace_whenReEnabled_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_ - 1));
        uint48 deadline = last_ + grace_;
        now_ = uint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        _payoutTimelock.setGracePeriod(grace_);
        vm.warp(last_);
        _payoutTimelock.disable("");
        vm.warp(now_);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-N04.
    function test_givenGraceOverflow_whenReEnabled_reverts(
        address caller_,
        bool bl_,
        bool overlap_,
        uint32 grace_,
        uint48 last_
    ) public givenPendingRecovery {
        _grantProposer(caller_, bl_, overlap_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max));
        _payoutTimelock.setGracePeriod(grace_);
        vm.warp(last_);
        _payoutTimelock.disable("");
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(last_) + grace_
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-REENABLE-N01, BLCUCT-REENABLE-N02, BLCUCT-REENABLE-N03, BLCUCT-REENABLE-N04.
    function test_whenGraceBoundarySeedsUsed() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenWithinGrace_whenReEnabled_thenExactTransition(
            address(0x111),
            false,
            false,
            1,
            1,
            1
        );
        _restore(checkpoint);
        test_givenWithinGrace_whenReEnabled_thenExactTransition(
            address(0x112),
            true,
            false,
            1,
            1,
            2
        );
        _restore(checkpoint);
        test_givenWithinGrace_whenReEnabled_thenExactTransition(
            address(0x113),
            false,
            true,
            type(uint48).max - type(uint32).max,
            type(uint32).max,
            type(uint48).max
        );
        _restore(checkpoint);
        test_givenExpiredGrace_whenReEnabled_reverts(address(0x111), false, false, 1, 1, 3);
        _restore(checkpoint);
        test_givenExpiredGrace_whenReEnabled_reverts(
            address(0x112),
            true,
            false,
            1,
            type(uint32).max,
            type(uint48).max
        );
        _restore(checkpoint);
        test_givenGraceOverflow_whenReEnabled_reverts(
            address(0x113),
            false,
            true,
            1,
            type(uint48).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLCUCT-REENABLE-D03.
    function test_givenInactivePayout_whenActivated_reverts(
        bool enabled_
    ) public givenPendingRecovery {
        _payoutTimelock.disable("");
        _setState(_payout, false, enabled_);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.reEnable, ()),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_payout)
            ),
            address(this)
        );
    }

    // Scenarios: BLCUCT-REENABLE-D07.
    function test_givenMissingConsumedInterface_whenActivated_reverts(bool enabled_) public {
        _payoutTimelock.disable("");
        _setState(_payout, true, enabled_);
        bytes4[3] memory ids = [
            type(IBurnerLoansPayout).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IEnabler).interfaceId
        ];
        for (uint256 i; i < ids.length; ++i) {
            vm.mockCall(
                address(_payout),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(false)
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansPayoutConfigTimelock
                        .BurnerLoansPayoutTimelock_InvalidPayout
                        .selector,
                    address(_payout)
                )
            );
            _payoutTimelock.reEnable();
            assertFalse(_payoutTimelock.isEnabled(), "Incompatible target cannot activate queue");
            vm.mockCall(
                address(_payout),
                abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                abi.encode(true)
            );
        }
    }
}
