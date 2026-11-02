// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetPriceCacheMaxAgeTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-QUEUE-CACHE-AGE-A05.
    function test_givenPermittedProposer_whenAgeQueued_thenStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D03.
    function test_givenOperationalRisk_whenAgeQueued_thenStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-P01.
    function test_givenFreeRiskKey_whenAgeQueued_thenExactDirectTarget(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-P07.
    function test_givenSameAge_whenQueued_thenStillCommitted(
        address caller_,
        uint8 role_,
        uint48 age_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _risk.setPriceCacheMaxAge(age_);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(age_);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-I01.
    function test_givenNonzeroOldAge_whenZeroQueued_thenAccepted(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _risk.setPriceCacheMaxAge(1);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(0);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-N01.
    function test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload(
        address caller_,
        uint8 role_,
        uint48 age_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        age_ = uint48(bound(age_, 1, type(uint48).max));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(age_);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-A01.
    function test_givenUnauthorizedProposer_whenAgeQueued_reverts(address caller_) public {
        _outsider(caller_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-A03.
    function test_givenRiskOperatorDifferent_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(_recipient);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-A04.
    function test_givenRiskOperatorCleared_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(0));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-L01.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-L05.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-L09.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D04.
    function test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _setState(_risk, false, true);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D05.
    function test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _setState(_risk, true, false);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D06.
    function test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _setState(_risk, false, false);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D07.
    function test_givenForeignRiskKernel_whenAgeQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(_kernel),
                address(0x1234)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D08.
    function test_givenConfigUnavailable_whenAgeQueued_thenNoLifecycleGate(
        address caller_,
        uint8 role_,
        bool active_,
        bool enabled_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _config.setConfigOperator(_recipient);
        _setState(_config, active_, enabled_);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D09.
    function test_givenCoreUnavailable_whenAgeQueued_thenNoLifecycleGate(
        address caller_,
        uint8 role_,
        bool active_,
        bool enabled_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _setState(_core, active_, enabled_);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-P02.
    function test_givenRiskKeyPending_whenAgeQueuedAgain_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        bytes32 original = _queueDigest(id);
        a.payload = abi.encode(uint48(7200));
        _expectRejectedQueue(_pending(a, id));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(_queueDigest(id), original, "Original Risk action preserved");
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-P03.
    function test_givenMarketKeyPending_whenAgeQueued_thenIndependent(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _independentActions(_capAction(address(_asset), 200000e9), _ageAction(3600), caller_);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-A05.
    function test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPermittedProposer_whenAgeQueued_thenStored(address(0xabc1), 0);
        _restore(checkpoint);
        test_givenPermittedProposer_whenAgeQueued_thenStored(address(0xabc1), 1);
        _restore(checkpoint);
        test_givenPermittedProposer_whenAgeQueued_thenStored(address(0xabc1), 2);
        _restore(checkpoint);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-N01.
    function test_givenCacheAgeN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload(
            address(0xabc1),
            uint8(1),
            uint48(1)
        );
        _restore(checkpoint);
        test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload(
            address(0xabc1),
            uint8(1),
            type(uint48).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-P07.
    function test_givenUnchangedCacheAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenSameAge_whenQueued_thenStillCommitted(address(0xabc1), uint8(1), uint48(0));
        _restore(checkpoint);
        test_givenSameAge_whenQueued_thenStillCommitted(
            address(0xabc1),
            uint8(1),
            type(uint48).max
        );
        _restore(checkpoint);
    }

    function _queue(ITimelockBatchQueue.BatchAction memory a_) internal returns (uint64) {
        return _timelock.queueSetPriceCacheMaxAge(abi.decode(a_.payload, (uint48)));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-L10.
    function test_givenInactiveDisabled_givenBrokenFacility_whenPriceAgeQueued_reverts(
        address caller_
    ) public {
        _setState(_timelock, false, false);
        vm.mockCallRevert(
            address(_config),
            abi.encodeWithSignature("facility()"),
            abi.encodeWithSignature("Unavailable()")
        );
        uint64 next = _timelock.nextActionId();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _timelock.queueSetPriceCacheMaxAge(0);
        assertEq(_timelock.nextActionId(), next, "Rejected wrapper consumes no ID");
    }
}
