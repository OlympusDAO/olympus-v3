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

contract BurnerLoansConfigTimelockQueueSetSendYieldToDistributorTest is
    BurnerLoansConfigTimelockDistributorFlagTest
{
    // Scenarios: QYIELD-A01, QYIELD-A02, QYIELD-A03, QYIELD-A04
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
        configTimelock.queueSetSendYieldToDistributor(true);
        _assertQueueRejected(next, false, false);
    }

    // Scenarios: QYIELD-L01, QYIELD-L02, QYIELD-L03
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
        _queueFlag(false, value_, _permittedProposer(useAdmin_));
        _assertQueueRejected(next, false, false);
    }

    // Scenarios: QYIELD-L04, QYIELD-L05, QYIELD-L06, QYIELD-L07
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
        _queueFlag(false, value_, _permittedProposer(useAdmin_));
        _assertQueueRejected(next, false, false);
    }

    // Scenarios: QYIELD-P01, QYIELD-P02
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
            IBurnerLoansConfig.setSendYieldToDistributor.selector,
            abi.encode(true)
        );
        uint64 actionId = _queueFlag(false, true, proposer);
        bytes32 key = _assertFlagActionQueued(
            actionId,
            false,
            true,
            proposer,
            false,
            address(distributor)
        );
        _warpReady(actionId);
        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.SendYieldToDistributorSet(true);
        _expectSingleActionExecuted(
            actionId,
            IBurnerLoansConfig.setSendYieldToDistributor.selector,
            executor_
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertTrue(burnerLoans.sendYieldToDistributor(), "yield flag enabled");
        _assertFlagActionExecuted(actionId, key);
    }

    // Scenarios: QYIELD-P04, QYIELD-P05
    function test_givenSameValue_whenQueuedAndExecuted_skipsDistributorValidation(
        bool current_,
        uint8 distributorState_,
        address executor_
    ) public {
        RevenueDistributor distributor = _installValidDistributor(false);
        if (current_) _setYieldFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        uint64 actionId = _queueFlag(false, current_, admin);
        bytes32 key = _assertFlagActionQueued(
            actionId,
            false,
            current_,
            admin,
            current_,
            address(distributor)
        );
        _warpReady(actionId);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(burnerLoans.sendYieldToDistributor(), current_, "same flag retained");
        _assertFlagActionExecuted(actionId, key);
        vm.clearMockedCalls();
    }

    // Scenarios: QYIELD-P03
    function test_givenYieldRoutingEnabled_whenDisableQueuedAndExecuted_skipsDistributorValidation(
        uint8 distributorState_,
        address executor_
    ) public {
        RevenueDistributor distributor = _installValidDistributor(false);
        _setYieldFlag(true);
        _driftRevenueDistributor(distributor, distributorState_);
        uint64 actionId = _queueFlag(false, false, burnerLoansAdmin);
        bytes32 key = _assertFlagActionQueued(
            actionId,
            false,
            false,
            burnerLoansAdmin,
            true,
            address(distributor)
        );
        _warpReady(actionId);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertFalse(burnerLoans.sendYieldToDistributor(), "yield flag disabled");
        _assertFlagActionExecuted(actionId, key);
        vm.clearMockedCalls();
    }

    // Scenarios: QYIELD-I01
    function test_givenDistributorUnset_whenEnableQueued_revertsBeforeKeyAcquisition(
        bool useAdmin_
    ) public {
        uint64 next = configTimelock.nextActionId();
        vm.expectRevert(IBurnerLoans.BurnerLoans_RevenueDistributorRequired.selector);
        _queueFlag(false, true, _permittedProposer(useAdmin_));
        _assertQueueRejected(next, false, false);
        _assertNoQueueState(next);
    }

    // Scenarios: QYIELD-I02
    function test_givenDistributorInactive_whenEnableQueued_reverts(bool useAdmin_) public {
        _checkInvalidDistributorQueue(false, useAdmin_, 0);
    }

    // Scenarios: QYIELD-I03
    function test_givenDistributorDisabled_whenEnableQueued_reverts(bool useAdmin_) public {
        _checkInvalidDistributorQueue(false, useAdmin_, 1);
    }

    // Scenarios: QYIELD-I04
    function test_givenDistributorKernelReadReverts_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(false, useAdmin_, 2);
    }

    // Scenarios: QYIELD-I05
    function test_givenDistributorKernelReadMalformed_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(false, useAdmin_, 3);
    }

    // Scenarios: QYIELD-I06
    function test_givenDistributorEnabledReadReverts_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(false, useAdmin_, 4);
    }

    // Scenarios: QYIELD-I07
    function test_givenDistributorEnabledReadMalformed_whenEnableQueued_reverts(
        bool useAdmin_
    ) public {
        _checkInvalidDistributorQueue(false, useAdmin_, 5);
    }

    // Scenarios: QYIELD-S01, QYIELD-S02, QYIELD-S12
    function test_givenFlagQueued_whenDistributorPointerChanges_executionRetainsAction(
        bool queueEnable_,
        bool clearPointer_
    ) public {
        _installValidDistributor(false);
        if (!queueEnable_) _setYieldFlag(true);
        uint64 actionId = _queueFlag(false, queueEnable_, admin);
        (bytes32 key, bytes32 oldHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        if (!queueEnable_) clearPointer_ = false;
        address replacement;
        if (!clearPointer_) replacement = address(_deployRevenueDistributor(true, false));
        vm.prank(admin);
        burnerLoans.setRevenueDistributor(replacement);
        _warpReady(actionId);
        _assertConfigConflict(actionId, key, oldHash, !queueEnable_, replacement);
    }

    // Scenarios: QYIELD-S03, QYIELD-S13
    function test_givenFlagQueued_whenFlagChanges_executionRetainsAction(bool queueEnable_) public {
        RevenueDistributor distributor = _installValidDistributor(false);
        if (!queueEnable_) _setYieldFlag(true);
        uint64 actionId = _queueFlag(false, queueEnable_, admin);
        (bytes32 key, bytes32 oldHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        _setYieldFlag(queueEnable_);
        _warpReady(actionId);
        _assertConfigConflict(actionId, key, oldHash, queueEnable_, address(distributor));
    }

    // Scenarios: QYIELD-S04
    function test_givenEnableReady_whenFacilityInactive_executionRetainsAction() public {
        _checkInvalidReadyExecution(false, 0);
    }

    // Scenarios: QYIELD-S05
    function test_givenEnableReady_whenDistributorInactive_executionRetainsAction() public {
        _checkInvalidReadyExecution(false, 1);
    }

    // Scenarios: QYIELD-S06
    function test_givenEnableReady_whenDistributorDisabled_executionRetainsAction() public {
        _checkInvalidReadyExecution(false, 2);
    }

    // Scenarios: QYIELD-S07
    function test_givenEnableReady_whenFacilityDisabled_executionRetainsAction() public {
        _checkInvalidReadyExecution(false, 3);
    }

    // Scenarios: QYIELD-S08
    function test_givenEnableReady_whenDistributorKernelReadReverts_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(false, 4);
    }

    // Scenarios: QYIELD-S09
    function test_givenEnableReady_whenDistributorKernelReadMalformed_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(false, 5);
    }

    // Scenarios: QYIELD-S10
    function test_givenEnableReady_whenDistributorEnabledReadReverts_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(false, 6);
    }

    // Scenarios: QYIELD-S11
    function test_givenEnableReady_whenDistributorEnabledReadMalformed_executionRetainsAction()
        public
    {
        _checkInvalidReadyExecution(false, 7);
    }

    // Scenarios: QYIELD-R01, QYIELD-R02
    function test_givenPendingPayouts_whenYieldFlagExecutes_preservesAllPendingState(
        bool enable_,
        address executor_
    ) public {
        _installValidDistributor(true);
        if (!enable_) _setYieldFlag(true);
        _seedPendingPayouts(address(trsry));
        RoutingSnapshot memory before_ = _snapshotRouting();
        uint64 actionId = _queueFlag(false, enable_, admin);
        (bytes32 key, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        _warpReady(actionId);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        _assertPendingStatePreserved(before_);
        _assertPendingRecipients(address(trsry));
        _assertFlagActionExecuted(actionId, key);
    }

    // Scenarios: QYIELD-Q01, QYIELD-Q02
    function test_givenYieldActionPending_whenSecondYieldActionQueued_revertsWithKeyOwner(
        bool secondValue_
    ) public {
        _installValidDistributor(false);
        uint64 owner = _queueFlag(false, true, admin);
        (bytes32 key, ) = configTimelock.getQueuedConfigState(owner, 0, 0);
        uint64 next = configTimelock.nextActionId();
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                owner
            )
        );
        _queueFlag(false, secondValue_, burnerLoansAdmin);
        assertEq(configTimelock.nextActionId(), next, "conflict consumes no action id");
        _assertFlagActionPending(owner, key);
    }
}
