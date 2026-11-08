// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {RiskTimelockCallbackTarget} from "./fixtures/RiskTimelockCallbackTarget.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansRiskConfigTimelockExecuteQueuedActionTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-EXECUTE-P03.
    function test_whenIndependentQueueAndExecutionOrders(
        uint8 queueOrder_,
        uint8 executeOrder_,
        address caller_
    ) public {
        uint256[3] memory q = _permutation(uint8(bound(queueOrder_, 0, 5)));
        uint256[3] memory e = _permutation(uint8(bound(executeOrder_, 0, 5)));
        ITimelockBatchQueue.BatchAction[] memory a = _threeActions();
        uint64[3] memory ids;
        bytes32[3] memory commitments;
        for (uint256 i; i < 3; ++i) {
            ids[q[i]] = _timelock.queueBatch(_single(a[q[i]]));
            commitments[q[i]] = _hash(a[q[i]]);
        }
        _makeReady(ids[0]);
        for (uint256 i; i < 3; ++i) {
            uint256 index = e[i];
            vm.expectEmit(address(_timelock));
            emit ITimelockBatchQueue.TimelockSubActionExecuted(
                ids[index],
                address(_risk),
                a[index].selector,
                0
            );
            vm.expectEmit(address(_timelock));
            emit ITimelockBatchQueue.TimelockActionExecuted(ids[index], caller_);
            _executeAndAssert(ids[index], caller_);
            for (uint256 j = i + 1; j < 3; ++j) {
                uint256 other = e[j];
                assertEq(
                    _timelock.pendingActionId(_key(a[other])),
                    ids[other],
                    "other key retained"
                );
                (, bytes32 committed) = _timelock.getQueuedConfigState(ids[other], 0, 0);
                assertEq(committed, commitments[other], "other commitment unchanged");
                assertEq(_hash(a[other]), committed, "unexecuted domain remains fresh");
            }
        }
        assertEq(_risk.priceCacheMaxAge(), 3600, "final age");
        assertEq(_risk.referralFeeBps(), 2500, "final percentage");
        assertTrue(_risk.isReferrerAllowed(_recipient), "final membership");
    }

    // Scenarios: BLRCT-EXECUTE-P03.
    function test_whenAllThirtySixIndependentOrderings() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 q; q < 6; ++q)
            for (uint8 e; e < 6; ++e) {
                test_whenIndependentQueueAndExecutionOrders(q, e, address(0));
                _restore(checkpoint);
            }
    }

    // Scenarios: BLRCT-EXECUTE-I01.
    function test_whenUnknownID_reverts(uint64 id_, address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        vm.prank(caller_);
        _timelock.executeQueuedAction(id_);
    }

    // Scenarios: BLRCT-EXECUTE-N01.
    function test_givenPending_whenBeforeNotice_reverts(uint48 elapsed_, address caller_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        vm.warp(uint256(a.queuedAt) + bound(elapsed_, 0, 1 days - 1));
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                id,
                a.executableAt
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-N02.
    function test_givenPending_whenWithinWindow(uint48 elapsed_, address caller_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        vm.warp(uint256(a.executableAt) + bound(elapsed_, 0, 3 days));
        _executeAndAssert(id, caller_);
    }

    // Scenarios: BLRCT-EXECUTE-N03.
    function test_givenPending_whenExpired_reverts(uint48 now_, address caller_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        vm.warp(bound(now_, uint256(a.expiresAt) + 1, type(uint48).max));
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                a.expiresAt
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-I02.
    function test_givenExecuted_whenRepeated_reverts(address caller_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        _executeAndAssert(id, caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
        vm.prank(caller_);
        _timelock.executeQueuedAction(id);
    }

    // Scenarios: BLRCT-EXECUTE-I03.
    function test_givenCancelled_whenExecuted_reverts(address caller_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _timelock.cancelQueuedAction(id);
        _makeReady(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
        vm.prank(caller_);
        _timelock.executeQueuedAction(id);
    }

    // Scenarios: BLRCT-EXECUTE-L01.
    function test_givenQueueInactive_whenExecuted_reverts(bool enabled_, address caller_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        _setState(_timelock, false, enabled_);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-L02.
    function test_givenQueueDisabled_whenExecuted_reverts(address caller_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        _timelock.disable("");
        _executeReverts(id, caller_, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLRCT-EXECUTE-D01, BLRCT-EXECUTE-D02, BLRCT-EXECUTE-D03.
    function test_givenRiskUnavailable_whenExecuted_reverts(
        bool active_,
        bool enabled_,
        address caller_
    ) public {
        vm.assume(!active_ || !enabled_);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        _setState(_risk, active_, enabled_);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D04.
    function test_givenOperatorChanged_whenExecuted_reverts(
        address operator_,
        address caller_
    ) public {
        vm.assume(operator_ != address(_timelock));
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        _risk.setConfigOperator(operator_);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-P02.
    function test_givenRelevantStateChanged_whenExecuted_reverts(
        uint8 domain_,
        address caller_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _threeActions()[bound(domain_, 0, 2)];
        uint64 id = _timelock.queueBatch(_single(a));
        bytes32 original = _hash(a);
        if (a.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector)
            _risk.setPriceCacheMaxAge(42);
        else if (a.selector == IBurnerLoansRisk.setReferralFeeBps.selector)
            _risk.setReferralFeeBps(1);
        else _risk.setReferrerAllowed(_recipient, true);
        _makeReady(id);
        _executeReverts(id, caller_, _stateChanged(id, 0, a, original));
    }

    // Scenarios: BLRCT-EXECUTE-P05.
    function test_givenSameValueIntent_whenExecuted() public {
        uint64 id = _timelock.queueSetReferralFeeBps(0);
        _makeReady(id);
        vm.recordLogs();
        _executeAndAssert(id, address(0));
        assertEq(
            vm.getRecordedLogs().length,
            2,
            "only subaction/final queue events, no target event"
        );
    }

    // Scenarios: BLRCT-EXECUTE-P06.
    function test_givenStateAndOperatorRestored_whenExecuted() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _risk.setReferralFeeBps(1);
        _risk.setReferralFeeBps(0);
        _risk.setConfigOperator(_recipient);
        _risk.setConfigOperator(address(_timelock));
        _timelock.disable("");
        _timelock.reEnable();
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        _makeReady(id);
        _executeAndAssert(id, _recipient);
    }

    // Scenarios: BLRCT-EXECUTE-P07.
    function test_givenBatchLateDrift_whenExecuted_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory a = _threeActions();
        uint64 id = _timelock.queueBatch(a);
        bytes32 original = _hash(a[2]);
        _risk.setReferrerAllowed(_recipient, true);
        _makeReady(id);
        _executeReverts(id, _recipient, _stateChanged(id, 2, a[2], original));
        assertEq(_risk.priceCacheMaxAge(), 0, "earlier age setter rolled back");
        assertEq(_risk.referralFeeBps(), 0, "earlier percentage setter rolled back");
    }

    // Scenarios: BLRCT-EXECUTE-T01.
    function test_givenTargetTypedFailure_whenExecuted_reverts() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansRisk.BurnerLoansRisk_InvalidReferralFeeBps.selector,
            uint16(2500)
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setReferralFeeBps, (uint16(2500))),
            reason
        );
        _executeReverts(id, _recipient, reason);
    }

    // Scenarios: BLRCT-EXECUTE-T02.
    function test_givenTargetEmptyFailure_whenExecuted_reverts() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setReferralFeeBps, (uint16(2500))),
            bytes("")
        );
        _executeReverts(
            id,
            _recipient,
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_SubActionCallFailed.selector,
                IBurnerLoansRisk.setReferralFeeBps.selector
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-T02.
    function test_givenTargetOversizedFailure_whenExecuted_reverts() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setReferralFeeBps, (uint16(2500))),
            new bytes(4096)
        );
        _executeReverts(
            id,
            _recipient,
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_SubActionCallFailed.selector,
                IBurnerLoansRisk.setReferralFeeBps.selector
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-P08.
    function test_givenExecutedDomains_whenRequeued() public {
        uint64 first = _timelock.queueBatch(_threeActions());
        _makeReady(first);
        _executeAndAssert(first, _recipient);
        uint64 next = _timelock.queueBatch(_threeActions());
        assertEq(next, 2, "fresh action ID");
        assertEq(
            _timelock.getQueuedAction(next).executableAt,
            vm.getBlockTimestamp() + 1 days,
            "fresh full notice"
        );
    }

    // Scenarios: BLRCT-EXECUTE-P10.
    function test_givenUpstreamUnavailable_whenExecuted(bool active_, bool enabled_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _setState(_config, active_, enabled_);
        _setState(_core, active_, enabled_);
        _makeReady(id);
        _executeAndAssert(id, _recipient);
    }

    // Scenarios: BLRCT-EXECUTE-D05.
    function test_givenForeignRiskKernel_whenExecuted_reverts() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        vm.mockCall(address(_risk), abi.encodeWithSignature("kernel()"), abi.encode(address(0xF0)));
        _executeReverts(
            id,
            _recipient,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(_kernel),
                address(0xF0)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D06.
    function test_givenFailedRiskStatus_whenExecuted_reverts(bool kernel_) public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        vm.mockCallRevert(
            address(_risk),
            kernel_ ? abi.encodeWithSignature("kernel()") : abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );
        _executeReverts(
            id,
            _recipient,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D07.
    function test_givenDirtyRiskOperator_whenExecuted_reverts() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(type(uint256).max)
        );
        _executeReverts(
            id,
            _recipient,
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D08.
    function test_givenSettingReadFails_whenExecuted_reverts(uint8 domain_) public {
        uint256 domain = bound(domain_, 0, 2);
        ITimelockBatchQueue.BatchAction memory action = _threeActions()[domain];
        uint64 id = _timelock.queueBatch(_single(action));
        _makeReady(id);
        bytes32 queued = _queueDigest(id);
        bytes4[3] memory getters = [
            IBurnerLoansRisk.priceCacheMaxAge.selector,
            IBurnerLoansRisk.referralFeeBps.selector,
            IBurnerLoansRisk.isReferrerAllowed.selector
        ];
        vm.mockCallRevert(address(_risk), abi.encodePacked(getters[domain]), hex"deadbeef");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.executeQueuedAction(id);
        assertEq(_queueDigest(id), queued, "failed setting getter retains intent and keys");
    }

    // Scenarios: BLRCT-EXECUTE-P04, BLCT-QUEUE-CACHE-AGE-P08.
    function test_givenCoreSelectsAnotherRisk_whenOldIntentExecuted() public {
        uint64 id = _timelock.queueSetPriceCacheMaxAge(3600);
        address replacement = address(_anotherRisk());
        _core.setRisk(replacement);
        assertEq(_core.risk(), replacement, "Core replacement selected");
        assertEq(address(_timelock.risk()), address(_risk), "queue target stays original");
        _makeReady(id);
        _executeAndAssert(id, _recipient);
        assertEq(
            IBurnerLoansRisk(replacement).priceCacheMaxAge(),
            0,
            "replacement not reconfigured"
        );
        assertEq(_risk.priceCacheMaxAge(), 3600, "original immutable destination updated");
    }

    function _installTargetCallback(bytes memory callback_, bytes memory expected_) private {
        address original = makeAddr("Original Risk code");
        vm.etch(original, address(_risk).code);
        RiskTimelockCallbackTarget callback = new RiskTimelockCallbackTarget(
            original,
            address(_timelock),
            callback_,
            keccak256(expected_)
        );
        vm.etch(address(_risk), address(callback).code);
    }

    // Scenarios: BLRCT-EXECUTE-C01.
    function test_givenInFlightTarget_whenSameIDExecutedAgain() public {
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _installTargetCallback(
            abi.encodeCall(ITimelockBatchQueue.executeQueuedAction, (id)),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
        _makeReady(id);
        _executeAndAssert(id, _recipient);
        assertEq(_risk.referralFeeBps(), 2500, "outer setter applies once");
    }

    // Scenarios: BLRCT-EXECUTE-C02.
    function test_givenInFlightReservation_whenNewIntentQueued() public {
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, address(_risk));
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _installTargetCallback(
            abi.encodeCall(IBurnerLoansRiskConfigTimelock.queueSetReferralFeeBps, (uint16(1))),
            _pending(_bpsAction(1), id)
        );
        _makeReady(id);
        _executeAndAssert(id, _recipient);
        assertEq(_risk.referralFeeBps(), 2500, "outer setter applies once");
        assertEq(_timelock.nextActionId(), 2, "nested rejected intent consumes no ID");
    }

    // Scenarios: BLRCT-EXECUTE-P10.
    function test_givenIndependentUpstreamStates_whenExecuted(
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
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _setState(_config, configActive_, configEnabled_);
        _setState(_core, coreActive_, coreEnabled_);
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        _makeReady(id);
        _executeAndAssert(id, _recipient);
    }

    function _expectNoUpstreamDiscoveryCalls() private {
        vm.expectCall(address(_config), abi.encodeWithSignature("facility()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(0));
    }

    // Scenarios: BLRCT-EXECUTE-P10.
    function test_givenEveryIndependentUpstreamState_whenExecuted() public {
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

    // Scenarios: BLRCT-EXECUTE-D06.
    function test_givenInvalidStatusMetadata_whenExecuted_reverts(
        bool kernel_,
        bool reverts_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _makeReady(id);
        if (reverts_)
            vm.mockCallRevert(
                address(_risk),
                kernel_
                    ? abi.encodeWithSignature("kernel()")
                    : abi.encodeWithSignature("isEnabled()"),
                data_
            );
        else
            vm.mockCall(
                address(_risk),
                kernel_
                    ? abi.encodeWithSignature("kernel()")
                    : abi.encodeWithSignature("isEnabled()"),
                data_
            );
        _executeReverts(
            id,
            _recipient,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
    }

    // Scenarios: BLRCT-EXECUTE-D07, BLRCT-EXECUTE-D08.
    function test_givenInvalidConfigMetadata_whenExecuted_reverts(
        uint8 domain_,
        bool operator_,
        bool reverts_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        uint256 domain = bound(domain_, 0, 2);
        ITimelockBatchQueue.BatchAction memory action = _threeActions()[domain];
        uint64 id = _timelock.queueBatch(_single(action));
        _makeReady(id);
        bytes32 queued = _queueDigest(id);
        bytes32 economic = _economicDigest();
        bytes4[3] memory getters = [
            IBurnerLoansRisk.priceCacheMaxAge.selector,
            IBurnerLoansRisk.referralFeeBps.selector,
            IBurnerLoansRisk.isReferrerAllowed.selector
        ];
        bytes memory callData = operator_
            ? abi.encodeWithSignature("configOperator()")
            : abi.encodePacked(getters[domain]);
        if (reverts_) vm.mockCallRevert(address(_risk), callData, data_);
        else vm.mockCall(address(_risk), callData, data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        _timelock.executeQueuedAction(id);
        vm.clearMockedCalls();
        assertEq(_queueDigest(id), queued, "metadata failure retains complete pending intent");
        assertEq(_economicDigest(), economic, "metadata failure changes no settings or balances");
    }
}
