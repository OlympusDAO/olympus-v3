// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test bounds prove casts fit; reverted-call returns and scenario literals are intentional.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansConfigTimelockDistributorFlagTest} from "src/test/policies/BurnerLoansConfigTimelock/fixtures/BurnerLoansConfigTimelockDistributorFlagTest.sol";

contract BurnerLoansConfigTimelockQueueSetSendFeesToDistributorTest is
    BurnerLoansConfigTimelockDistributorFlagTest
{
    // Scenarios: QFEES-A01, QFEES-A02, QFEES-A03, QFEES-A04
    function test_givenLifecycleState_whenUnauthorizedCallerQueues_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);
        _installValidDistributor(false);
        if (!active_) _deactivatePolicy(address(configTimelock));
        if (!enabled_) _disableTimelock();
        uint64 next = configTimelock.nextActionId();

        if (!enabled_) vm.expectRevert(IEnabler.NotEnabled.selector);
        else if (!active_)
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                    address(configTimelock)
                )
            );
        else vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.queueSetSendFeesToDistributor(true);

        _assertQueueRejected(next, true, false);
    }

    // Scenarios: QFEES-L01, QFEES-L02, QFEES-L03
    function test_givenTimelockUnavailable_whenPermittedCallerQueues_reverts(
        bool useAdmin_,
        bool active_,
        bool enabled_,
        bool value_
    ) public {
        vm.assume(!active_ || !enabled_);
        if (!active_) _deactivatePolicy(address(configTimelock));
        if (!enabled_) _disableTimelock();
        uint64 next = configTimelock.nextActionId();

        if (!enabled_) vm.expectRevert(IEnabler.NotEnabled.selector);
        else
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                    address(configTimelock)
                )
            );
        _queueFlag(true, value_, _permittedProposer(useAdmin_));
        _assertQueueRejected(next, true, false);
    }

    // Scenarios: QFEES-L04, QFEES-L05, QFEES-L06, QFEES-L07
    function test_givenConfigUnavailable_whenPermittedCallerQueues_reverts(
        bool useAdmin_,
        uint8 state_,
        bool value_
    ) public {
        state_ = uint8(bound(state_, 0, 3));
        if (state_ == 0) _deactivatePolicy(address(burnerLoansConfig));
        if (state_ == 1) _disableConfig();
        if (state_ == 2) _setConfigOperator(address(0xBEEF));
        if (state_ == 3) {
            _deactivatePolicy(address(burnerLoansConfig));
            _disableConfig();
        }
        uint64 next = configTimelock.nextActionId();

        if (state_ == 0 || state_ == 3)
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_PolicyInactive.selector,
                    address(burnerLoansConfig)
                )
            );
        if (state_ == 1) vm.expectRevert(IEnabler.NotEnabled.selector);
        if (state_ == 2)
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                    address(configTimelock)
                )
            );
        _queueFlag(true, value_, _permittedProposer(useAdmin_));
        _assertQueueRejected(next, true, false);
    }

    // Scenarios: QFEES-P01, QFEES-P02
    function test_givenValidDistributor_whenPermittedCallerQueuesAndExecutorRuns_succeeds(
        bool useAdmin_,
        bool assetListed_,
        address executor_
    ) public {
        RevenueDistributor distributor = _installValidDistributor(assetListed_);
        address proposer = _permittedProposer(useAdmin_);
        uint64 next = configTimelock.nextActionId();
        _expectSingleActionQueued(
            next,
            proposer,
            IBurnerLoansConfig.setSendFeesToDistributor.selector,
            abi.encode(true)
        );
        uint64 actionId = _queueFlag(true, true, proposer);
        bytes32 key = _assertFlagActionQueued(
            actionId,
            true,
            true,
            proposer,
            false,
            address(distributor)
        );

        _warpReady(actionId);
        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendFeesToDistributorSet(true);
        _expectSingleActionExecuted(
            actionId,
            IBurnerLoansConfig.setSendFeesToDistributor.selector,
            executor_
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertTrue(burnerLoans.sendFeesToDistributor(), "fee flag enabled");
        _assertFlagActionExecuted(actionId, key);
    }

    // Scenarios: QFEES-P04, QFEES-P05
    function test_givenDisableOrSameValue_whenQueuedAndExecuted_skipsDistributorValidation(
        bool current_,
        uint8 distributorState_,
        address executor_
    ) public {
        RevenueDistributor distributor = _installValidDistributor(false);
        if (current_) _setFeeFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        uint64 actionId = _queueFlag(true, current_, admin);
        bytes32 key = _assertFlagActionQueued(
            actionId,
            true,
            current_,
            admin,
            current_,
            address(distributor)
        );
        _warpReady(actionId);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(burnerLoans.sendFeesToDistributor(), current_, "same flag retained");
        _assertFlagActionExecuted(actionId, key);
        vm.clearMockedCalls();
    }

    // Scenarios: QFEES-P03
    function test_givenFeeRoutingEnabled_whenDisableQueuedAndExecuted_skipsDistributorValidation(
        uint8 distributorState_,
        address executor_
    ) public {
        RevenueDistributor distributor = _installValidDistributor(false);
        _setFeeFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        uint64 actionId = _queueFlag(true, false, burnerLoansAdmin);
        bytes32 key = _assertFlagActionQueued(
            actionId,
            true,
            false,
            burnerLoansAdmin,
            true,
            address(distributor)
        );
        _warpReady(actionId);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertFalse(burnerLoans.sendFeesToDistributor(), "fee flag disabled");
        _assertFlagActionExecuted(actionId, key);
        vm.clearMockedCalls();
    }

    // Scenarios: QFEES-I01
    function test_givenDistributorUnset_whenEnableQueued_revertsBeforeKeyAcquisition(
        bool useAdmin_
    ) public {
        uint64 next = configTimelock.nextActionId();
        vm.expectRevert(IBurnerLoans.BurnerLoans_RevenueDistributorRequired.selector);
        _queueFlag(true, true, _permittedProposer(useAdmin_));
        _assertQueueRejected(next, true, false);
        _assertNoQueueState(next);
    }

    // Scenarios: QFEES-I02
    function test_givenDistributorInactive_whenEnableQueued_reverts(bool useAdmin_) public {
        _checkInvalidDistributorQueue(true, useAdmin_, 0);
    }

    // Scenarios: QFEES-I03
    function test_givenDistributorDisabled_whenEnableQueued_reverts(bool useAdmin_) public {
        _checkInvalidDistributorQueue(true, useAdmin_, 1);
    }

    // Scenarios: QFEES-I04
    function test_givenDistributorKernelReadReverts_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(true, useAdmin_, 2);
    }

    // Scenarios: QFEES-I05
    function test_givenDistributorKernelReadMalformed_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(true, useAdmin_, 3);
    }

    // Scenarios: QFEES-I06
    function test_givenDistributorEnabledReadReverts_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(true, useAdmin_, 4);
    }

    // Scenarios: QFEES-I07
    function test_givenDistributorEnabledReadMalformed_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(true, useAdmin_, 5);
    }

    // Scenarios: QFEES-S01, QFEES-S02, QFEES-S12
    function test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction(
        bool queueEnable_,
        bool clearPointer_
    ) public {
        _installValidDistributor(false);
        if (!queueEnable_) _setFeeFlag(true);
        uint64 actionId = _queueFlag(true, queueEnable_, admin);
        (bytes32 key, bytes32 oldHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        if (!queueEnable_) clearPointer_ = false;
        address replacement;
        if (!clearPointer_) replacement = address(_deployRevenueDistributor(true, false));
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(replacement);
        _warpReady(actionId);
        _assertConfigConflict(actionId, key, oldHash, !queueEnable_, replacement);
    }

    // Scenarios: QFEES-S03, QFEES-S13
    function test_givenFlagQueued_whenFlagChanges_executionRetainsAction(bool queueEnable_) public {
        RevenueDistributor distributor = _installValidDistributor(false);
        if (!queueEnable_) _setFeeFlag(true);
        uint64 actionId = _queueFlag(true, queueEnable_, admin);
        (bytes32 key, bytes32 oldHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        _setFeeFlag(queueEnable_);
        _warpReady(actionId);
        _assertConfigConflict(actionId, key, oldHash, queueEnable_, address(distributor));
    }

    // Scenarios: QFEES-S04
    function test_givenEnableReady_whenFacilityInactive_executionRetainsAction() public {
        _checkInvalidReadyExecution(true, 0);
    }

    // Scenarios: QFEES-S05
    function test_givenEnableReady_whenDistributorInactive_executionRetainsAction() public {
        _checkInvalidReadyExecution(true, 1);
    }

    // Scenarios: QFEES-S06
    function test_givenEnableReady_whenDistributorDisabled_executionRetainsAction() public {
        _checkInvalidReadyExecution(true, 2);
    }

    // Scenarios: QFEES-S07
    function test_givenEnableReady_whenFacilityDisabled_executionRetainsAction() public {
        _checkInvalidReadyExecution(true, 3);
    }

    // Scenarios: QFEES-S08
    function test_givenEnableReady_whenDistributorKernelReadReverts_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(true, 4);
    }

    // Scenarios: QFEES-S09
    function test_givenEnableReady_whenDistributorKernelReadMalformed_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(true, 5);
    }

    // Scenarios: QFEES-S10
    function test_givenEnableReady_whenDistributorEnabledReadReverts_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(true, 6);
    }

    // Scenarios: QFEES-S11
    function test_givenEnableReady_whenDistributorEnabledReadMalformed_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(true, 7);
    }

    // Scenarios: QFEES-R01, QFEES-R02
    function test_givenPendingPayouts_whenFlagExecutes_reassignsFeeOnly(
        bool enable_,
        address executor_
    ) public {
        RevenueDistributor distributor = _installValidDistributor(true);
        if (!enable_) _setFeeFlag(true);
        _seedPendingPayouts(enable_ ? address(trsry) : address(distributor));
        RoutingSnapshot memory before_ = _snapshotRouting();
        uint64 actionId = _queueFlag(true, enable_, admin);
        (bytes32 key, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        _assertPendingStatePreserved(before_);
        _warpReady(actionId);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(enable_ ? address(distributor) : address(trsry));
        _assertFlagActionExecuted(actionId, key);
    }

    // Scenarios: QFEES-Q01, QFEES-Q02
    function test_givenFeeActionPending_whenSecondFeeActionQueued_revertsWithKeyOwner(
        bool secondValue_
    ) public {
        _installValidDistributor(false);
        uint64 owner = _queueFlag(true, true, admin);
        (bytes32 key, ) = configTimelock.getQueuedConfigState(owner, 0, 0);
        uint64 next = configTimelock.nextActionId();
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                owner
            )
        );
        _queueFlag(true, secondValue_, burnerLoansAdmin);
        assertEq(configTimelock.nextActionId(), next, "conflict consumes no action id");
        _assertFlagActionPending(owner, key);
    }
}
