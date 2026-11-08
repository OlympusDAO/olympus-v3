// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";

contract BurnerLoansRiskConfigTimelockExecuteCacheAgeTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-EXECUTE-P02.
    function test_givenAgeDrift_whenAgeExecuted_thenRejected(address executor_) public {
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        uint64 id = _timelock.queueBatch(_single(a));
        bytes32 expected = _hash(a);
        _risk.setPriceCacheMaxAge(7200);
        _makeReady(id);
        _executeReverts(id, executor_, _stateChanged(id, 0, a, expected));
    }

    // Scenarios: BLRCT-EXECUTE-N02.
    function test_givenDirectRiskDispatch_whenAgeExecuted_thenApplied(address executor_) public {
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        uint64 id = _timelock.queueBatch(_single(a));
        bytes32 expected = _hash(a);
        _makeReady(id);
        vm.mockCallRevert(
            address(_config),
            abi.encodeWithSignature("setPriceCacheMaxAge(uint48)", uint48(3600)),
            hex"deadbeef"
        );
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setPriceCacheMaxAge, (uint48(3600))),
            1
        );
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLRCT-EXECUTE-D04.
    function test_givenRiskOperatorRevoked_whenAgeExecuted_thenRejected(
        address executor_,
        bool zero_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        uint64 id = _timelock.queueBatch(_single(a));
        bytes32 expected = _hash(a);
        _risk.setConfigOperator(zero_ ? address(0) : _recipient);
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-P05.
    function test_givenSameAge_whenExecuted_thenNoTargetEvent(
        address executor_,
        uint48 age_
    ) public {
        _risk.setPriceCacheMaxAge(age_);
        uint64 id = _timelock.queueBatch(_single(_ageAction(age_)));
        _makeReady(id);
        vm.recordLogs();
        vm.record();
        _executeAndAssert(id, executor_);
        _assertNoTargetLogs(vm.getRecordedLogs(), address(_risk));
        _assertNoTargetWrites(address(_risk));
    }

    // Scenarios: BLRCT-EXECUTE-D01.
    function test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeExecuted_reverts(
        address executor_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_ageAction(3600)));
        _setState(_risk, false, true);
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D02.
    function test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeExecuted_reverts(
        address executor_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_ageAction(3600)));
        _setState(_risk, true, false);
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D03.
    function test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeExecuted_reverts(
        address executor_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_ageAction(3600)));
        _setState(_risk, false, false);
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D05.
    function test_givenRiskKernelDrift_whenAgeExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_ageAction(3600)));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(_kernel),
                address(0x1234)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-P10.
    function test_givenConfigUnavailable_whenAgeExecuted_thenApplied(
        address executor_,
        bool active_,
        bool enabled_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_ageAction(3600)));
        _config.setConfigOperator(_recipient);
        _setState(_config, active_, enabled_);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLRCT-EXECUTE-P10.
    function test_givenCoreUnavailable_whenAgeExecuted_thenApplied(
        address executor_,
        bool active_,
        bool enabled_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_ageAction(3600)));
        _setState(_core, active_, enabled_);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLRCT-EXECUTE-P05.
    function test_givenUnchangedExecutedAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenSameAge_whenExecuted_thenNoTargetEvent(address(0xabc1), uint48(0));
        _restore(checkpoint);
        test_givenSameAge_whenExecuted_thenNoTargetEvent(address(0xabc1), type(uint48).max);
        _restore(checkpoint);
    }
}
