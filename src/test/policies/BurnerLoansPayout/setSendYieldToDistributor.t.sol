// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// Literal amounts and endpoints are independent expected test values.
// Tests read state after calls to assert exact effects and rollback.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {Kernel, Actions} from "src/Kernel.sol";

contract BurnerLoansPayoutSetSendYieldToDistributorTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-YIELD-A01.
    function test_whenUnauthorized_reverts(address caller_) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && caller_ != _payout.configOperator());
        _expectFlagRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_,
            false
        );
    }

    // Scenarios: BLCU-YIELD-P01.
    function test_whenEnabled_thenOnlyFlagChanges(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool otherFlag_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendFeesToDistributor(otherFlag_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        bytes32 state = _ledgerDigest();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.SendYieldToDistributorSet(true);
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(true);
        assertTrue(_payout.sendYieldToDistributor(), "Requested route stored");
        assertEq(_ledgerDigest(), state, "Flag change moves no funds or obligations");
    }

    // Scenarios: BLCU-YIELD-P03, BLCU-YIELD-P05.
    function test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool otherFlag_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendFeesToDistributor(otherFlag_);
        _payout.setSendYieldToDistributor(true);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        bytes32 state = _ledgerDigest();
        vm.recordLogs();
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(true);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged true emits no event");
        assertTrue(_payout.sendYieldToDistributor(), "True retained");
        assertEq(_ledgerDigest(), state, "Same-value route preserves custody");
    }

    // Scenarios: BLCU-YIELD-L01, BLCU-YIELD-L20, BLCU-YIELD-L21, BLCU-YIELD-L07.
    function test_givenPayoutActive_whenDisabled_thenRepairWorks(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendYieldToDistributor(true);
        _distributor.disable("");
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _setState(_payout, true, enabled_);
        _setState(_core, coreActive_, coreEnabled_);
        bytes32 state = _ledgerDigest();
        vm.mockCallRevert(
            address(_distributor),
            abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.SendYieldToDistributorSet(false);
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(false);
        assertFalse(_payout.sendYieldToDistributor(), "Repair clears route");
        assertEq(_ledgerDigest(), state, "Repair changes no obligation or balance");
    }

    // Scenarios: BLCU-YIELD-L09, BLCU-YIELD-P05.
    function test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _bindDistributor();
        _distributor.disable("");
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        bytes32 state = _ledgerDigest();
        vm.mockCallRevert(
            address(_distributor),
            abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );
        vm.recordLogs();
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(false);
        assertEq(vm.getRecordedLogs().length, 0, "False no-op emits no event");
        assertFalse(_payout.sendYieldToDistributor(), "False retained");
        assertEq(_ledgerDigest(), state, "False no-op preserves custody");
    }

    // Scenarios: BLCU-YIELD-I01.
    function test_givenUnsetDistributor_whenSetTrue_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectFlagRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_RevenueDistributorRequired.selector
            ),
            caller_,
            true
        );
    }

    function _expectFlagRejected(bytes memory reason_, address caller_, bool value_) internal {
        bytes32 state = _ledgerDigest();
        bool beforeFlag = _payout.sendYieldToDistributor();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(value_);
        assertEq(_payout.sendYieldToDistributor(), beforeFlag, "Rejected update preserves flag");
        assertEq(_ledgerDigest(), state, "Rejected update preserves liabilities and custody");
    }

    // Scenarios: BLCU-YIELD-L03.
    function test_givenInactiveDistributor_whenSetTrue_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool old_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendYieldToDistributor(old_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_distributor));
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectFlagRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_distributor)
            ),
            caller_,
            true
        );
    }

    // Scenarios: BLCU-YIELD-L05.
    function test_givenPausedDistributor_whenSetTrue_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool old_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendYieldToDistributor(old_);
        _distributor.disable("");
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectFlagRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_distributor)
            ),
            caller_,
            true
        );
    }

    // Scenarios: BLCU-YIELD-D04.
    function test_givenDistributorKernelDrift_whenSetTrue_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool old_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendYieldToDistributor(old_);
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _distributor.changeKernel(next);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectFlagRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_distributor),
                address(_kernel),
                address(next)
            ),
            caller_,
            true
        );
    }

    // Scenarios: BLCU-YIELD-D05.
    function test_givenDistributorKernelDrift_whenSetFalse_thenRepairWorks(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendYieldToDistributor(true);
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _distributor.changeKernel(next);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        bytes32 state = _ledgerDigest();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.SendYieldToDistributorSet(false);
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(false);
        assertFalse(_payout.sendYieldToDistributor(), "Broken target route cleared");
        assertEq(_ledgerDigest(), state, "Repair preserves balances and obligations");
    }

    // Scenarios: BLCU-YIELD-D01, BLCU-YIELD-D02, BLCU-YIELD-D03.
    function test_givenUnavailableStoredController_whenOperatorDisables_thenIdentitySuffices(
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _bindDistributor();
        _payout.setSendYieldToDistributor(true);
        _payout.setConfigOperator(address(_config));
        _setState(_config, active_, enabled_);
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        bytes32 state = _ledgerDigest();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.SendYieldToDistributorSet(false);
        vm.prank(address(_config));
        _payout.setSendYieldToDistributor(false);
        assertFalse(_payout.sendYieldToDistributor(), "Upstream controller identity accepted");
        assertEq(_ledgerDigest(), state, "No reverse check or custody mutation");
    }

    // Scenarios: BLCU-YIELD-P01.
    function test_givenEachRecoveryRole_whenEnabled_thenOnlyFlagChanges() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_whenEnabled_thenOnlyFlagChanges(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-P03, BLCU-YIELD-P05.
    function test_givenAlreadyTrue_givenEachRecoveryRole_whenSetTrue_thenValidatedNoOp() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenAlreadyTrue_whenSetTrue_thenValidatedNoOp(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-L01, BLCU-YIELD-L07, BLCU-YIELD-L20, BLCU-YIELD-L21.
    function test_givenPayoutActive_givenEachRecoveryRole_whenDisabled_thenRepairWorks() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenPayoutActive_whenDisabled_thenRepairWorks(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true,
                true,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-L09, BLCU-YIELD-P05.
    function test_givenAlreadyFalseAndInvalidDistributor_givenEachRecoveryRole_whenSetFalse_thenNoOp()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenAlreadyFalseAndInvalidDistributor_whenSetFalse_thenNoOp(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-I01.
    function test_givenUnsetDistributor_givenEachRecoveryRole_whenSetTrue_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenUnsetDistributor_whenSetTrue_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-L03.
    function test_givenInactiveDistributor_givenEachRecoveryRole_whenSetTrue_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenInactiveDistributor_whenSetTrue_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-L05.
    function test_givenPausedDistributor_givenEachRecoveryRole_whenSetTrue_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenPausedDistributor_whenSetTrue_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-D04.
    function test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetTrue_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenDistributorKernelDrift_whenSetTrue_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-D05.
    function test_givenDistributorKernelDrift_givenEachRecoveryRole_whenSetFalse_thenRepairWorks()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenDistributorKernelDrift_whenSetFalse_thenRepairWorks(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-YIELD-L01, BLCU-YIELD-L20, BLCU-YIELD-L21, BLCU-YIELD-L07.
    function test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable() public {
        uint256 checkpoint = vm.snapshotState();

        for (uint256 enabled; enabled < 2; ++enabled) {
            for (uint256 coreActive; coreActive < 2; ++coreActive) {
                for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                    test_givenPayoutActive_whenDisabled_thenRepairWorks(
                        address(0xabc1),
                        false,
                        false,
                        enabled != 0,
                        coreActive != 0,
                        coreEnabled != 0
                    );
                    _restore(checkpoint);
                }
            }
        }
    }

    function test_givenValidYieldRoute_whenQueried_thenDirectRecipient(address caller_) public {
        _useDistributor();
        _payout.setSendYieldToDistributor(true);
        bytes32 state = _ledgerDigest();
        vm.prank(caller_);
        assertEq(_payout.yieldRecipient(), address(_distributor), "Yield bypasses Payout custody");
        _payout.setSendYieldToDistributor(false);
        vm.prank(caller_);
        assertEq(_payout.yieldRecipient(), _treasury(), "Disabled routing resolves live Treasury");
        assertEq(_ledgerDigest(), state, "Direct yield route creates no Payout liability");
    }

    function test_givenPayoutPaused_whenYieldRecipientQueried_reverts() public {
        _payout.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _payout.yieldRecipient();
    }

    function test_givenPayoutInactive_whenYieldRecipientQueried_reverts() public {
        _setState(_payout, false, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            )
        );
        _payout.yieldRecipient();
    }

    // Scenarios: BLCU-YIELD-P03, BLCU-YIELD-P05.
    function test_whenSameFlagValue_thenRoutingSlotNotWritten(bool value_) public {
        _bindDistributor();
        _payout.setSendYieldToDistributor(value_);
        uint256 slot = _flagSlot("sendYieldToDistributor()");
        vm.record();
        vm.recordLogs();
        _payout.setSendYieldToDistributor(value_);
        _assertNoWriteToFlag(slot);
        assertEq(vm.getRecordedLogs().length, 0, "Same value emits no setter event");
    }

    // Scenarios: BLCU-YIELD-L22, BLCU-YIELD-L23.
    function test_givenPayoutInactive_whenCalled_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool enabled_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);

        _setState(_payout, false, enabled_);
        bytes32 state = _ledgerDigest();

        _expectInactivePayout();
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(false);
        assertEq(_ledgerDigest(), state, "Inactive Payout preserves balances and obligations");
    }

    // Scenarios: BLCU-YIELD-L24.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.setSendYieldToDistributor(false);
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)
