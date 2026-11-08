// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";

contract BurnerLoansRiskConfigTimelockQueueSetPriceCacheMaxAgeTest is
    BurnerLoansRiskConfigTimelockTest
{
    // Scenarios: BLCT-QUEUE-CACHE-AGE-A05.
    function test_givenPermittedProposer_whenAgeQueued_thenStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
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
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
            )
        );
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
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
            )
        );
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
        vm.startPrank(caller_);
        uint64 bps = _timelock.queueSetReferralFeeBps(2500);
        uint64 referrer = _timelock.queueSetReferrerAllowed(_recipient, true);
        uint64 age = _timelock.queueSetPriceCacheMaxAge(3600);
        vm.stopPrank();
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            bps,
            "percentage keeps independent key"
        );
        assertEq(
            _timelock.pendingActionId(_key(_referrerAction(_recipient, true))),
            referrer,
            "membership keeps independent key"
        );
        assertEq(
            _timelock.pendingActionId(_key(_ageAction(3600))),
            age,
            "age owns only selector key"
        );
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

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D10.
    function test_givenFailedRiskStatus_whenAgeQueued_reverts(bool kernel_) public {
        vm.mockCallRevert(
            address(_risk),
            kernel_ ? abi.encodeWithSignature("kernel()") : abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _timelock.queueSetPriceCacheMaxAge(3600);
        assertEq(_timelock.nextActionId(), 1, "status failure consumes no ID");
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D11.
    function test_givenFailedSettingMetadata_whenAgeQueued_reverts(bool operator_) public {
        vm.mockCallRevert(
            address(_risk),
            operator_
                ? abi.encodeWithSignature("configOperator()")
                : abi.encodeWithSignature("priceCacheMaxAge()"),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.queueSetPriceCacheMaxAge(3600);
        assertEq(_timelock.nextActionId(), 1, "setting failure consumes no ID");
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D10.
    function test_givenInvalidStatusMetadata_whenQueueRejected(
        bool kernel_,
        bool reverts_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        _beforeQueue = _economicDigest();
        _next = _timelock.nextActionId();
        bytes memory callData = kernel_
            ? abi.encodeWithSignature("kernel()")
            : abi.encodeWithSignature("isEnabled()");
        if (reverts_) vm.mockCallRevert(address(_risk), callData, data_);
        else vm.mockCall(address(_risk), callData, data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _timelock.queueSetPriceCacheMaxAge(3600);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_ageAction(3600)));
        assertEq(
            _timelock.pendingActionId(_key(_ageAction(3600))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D11.
    function test_givenInvalidSettingMetadata_whenQueueRejected(
        bool operator_,
        bool reverts_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        _beforeQueue = _economicDigest();
        _next = _timelock.nextActionId();
        bytes memory callData = operator_
            ? abi.encodeWithSignature("configOperator()")
            : abi.encodePacked(IBurnerLoansRisk.priceCacheMaxAge.selector);
        if (reverts_) vm.mockCallRevert(address(_risk), callData, data_);
        else vm.mockCall(address(_risk), callData, data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.queueSetPriceCacheMaxAge(3600);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_ageAction(3600)));
        assertEq(
            _timelock.pendingActionId(_key(_ageAction(3600))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D08, BLCT-QUEUE-CACHE-AGE-D09.
    function test_givenIndependentUpstreamStates_whenQueued(
        bool configActive_,
        bool configEnabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _expectNoUpstreamDiscoveryCalls();
        _exerciseIndependentUpstreamState(configActive_, configEnabled_, coreActive_, coreEnabled_);
    }

    function _exerciseIndependentUpstreamState(
        bool configActive_,
        bool configEnabled_,
        bool coreActive_,
        bool coreEnabled_
    ) private {
        _setState(_config, configActive_, configEnabled_);
        _setState(_core, coreActive_, coreEnabled_);
        _expectQueue(_single(_ageAction(3600)), address(this));
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        uint64 id = _timelock.queueSetPriceCacheMaxAge(3600);
        vm.clearMockedCalls();
        _assertQueued(id, _single(_ageAction(3600)), address(this));
    }

    function _expectNoUpstreamDiscoveryCalls() private {
        vm.expectCall(address(_config), abi.encodeWithSignature("facility()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(0));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D08, BLCT-QUEUE-CACHE-AGE-D09.
    function test_givenEveryIndependentUpstreamState_whenQueued() public {
        _expectNoUpstreamDiscoveryCalls();
        uint256 checkpoint = vm.snapshotState();
        for (uint256 bits; bits < 16; ++bits) {
            _exerciseIndependentUpstreamState(
                (bits & 1) != 0,
                (bits & 2) != 0,
                (bits & 4) != 0,
                (bits & 8) != 0
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D10.
    function test_givenDirtyStatusWords_whenQueueRejected(bool kernel_) public {
        _beforeQueue = _economicDigest();
        _next = _timelock.nextActionId();
        vm.mockCall(
            address(_risk),
            kernel_ ? abi.encodeWithSignature("kernel()") : abi.encodeWithSignature("isEnabled()"),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _timelock.queueSetPriceCacheMaxAge(3600);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_ageAction(3600)));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D11.
    function test_givenDirtySettingWords_whenQueueRejected(bool operator_) public {
        _beforeQueue = _economicDigest();
        _next = _timelock.nextActionId();
        vm.mockCall(
            address(_risk),
            operator_
                ? abi.encodeWithSignature("configOperator()")
                : abi.encodePacked(IBurnerLoansRisk.priceCacheMaxAge.selector),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.queueSetPriceCacheMaxAge(3600);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_ageAction(3600)));
    }

    // Scenarios: BLCT-QUEUE-CACHE-AGE-D10, BLCT-QUEUE-CACHE-AGE-D11.
    function test_givenMetadataShapeSeeds_whenQueueRejected() public {
        uint256 checkpoint = vm.snapshotState();
        bytes[3] memory shapes = [
            bytes(""),
            new bytes(31),
            bytes.concat(abi.encode(true), hex"00")
        ];
        for (uint256 i; i < 2; ++i) {
            bool first = i == 0;
            for (uint256 j; j < shapes.length; ++j) {
                test_givenInvalidStatusMetadata_whenQueueRejected(first, false, shapes[j]);
                _restore(checkpoint);
                test_givenInvalidSettingMetadata_whenQueueRejected(first, false, shapes[j]);
                _restore(checkpoint);
            }
            test_givenInvalidStatusMetadata_whenQueueRejected(first, true, hex"deadbeef");
            _restore(checkpoint);
            test_givenInvalidSettingMetadata_whenQueueRejected(first, true, hex"deadbeef");
            _restore(checkpoint);
            test_givenDirtyStatusWords_whenQueueRejected(first);
            _restore(checkpoint);
            test_givenDirtySettingWords_whenQueueRejected(first);
            _restore(checkpoint);
        }
    }
}
