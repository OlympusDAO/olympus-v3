// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansRiskConfigTimelockQueueBatchTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-BATCH-I01.
    function test_whenEmpty_reverts() public {
        _expectRejectedQueue(
            abi.encodeWithSelector(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector)
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_timelock.nextActionId(), 1, "empty consumes no ID");
    }

    // Scenarios: BLRCT-BATCH-I02.
    function test_whenTooManyActions_reverts(uint8 length_) public {
        uint256 length = bound(length_, 16, 255);
        ITimelockBatchQueue.BatchAction[] memory a = new ITimelockBatchQueue.BatchAction[](length);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                length,
                15
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(a);
        assertEq(_timelock.nextActionId(), 1, "oversized consumes no ID");
    }

    // Scenarios: BLRCT-BATCH-N01.
    function test_whenValidSize(uint8 length_, address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        uint256 length = bound(length_, 1, 15);
        ITimelockBatchQueue.BatchAction[] memory a = new ITimelockBatchQueue.BatchAction[](length);
        for (uint256 i; i < length; ++i) a[i] = _referrerAction(address(uint160(i + 1)), true);
        _expectQueue(a, caller_);
        vm.prank(caller_);
        uint64 id = _timelock.queueBatch(a);
        _assertQueued(id, a, caller_);
    }

    // Scenarios: BLRCT-BATCH-I03.
    function test_whenWrongTarget_reverts(address target_) public {
        vm.assume(target_ != address(_risk));
        ITimelockBatchQueue.BatchAction memory a = _bpsAction(2500);
        a.target = target_;
        _expectRejectedQueue(_invalid(a));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(a));
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLRCT-BATCH-I04.
    function test_whenUnknownSelector_reverts(bytes4 selector_) public {
        vm.assume(selector_ != IBurnerLoansRisk.setPriceCacheMaxAge.selector);
        vm.assume(selector_ != IBurnerLoansRisk.setReferralFeeBps.selector);
        vm.assume(selector_ != IBurnerLoansRisk.setReferrerAllowed.selector);
        ITimelockBatchQueue.BatchAction memory a = _bpsAction(2500);
        a.selector = selector_;
        _expectRejectedQueue(_invalid(a));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(a));
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLRCT-BATCH-I05.
    function test_whenWrongPayloadLength_reverts(uint8 length_, uint8 selector_) public {
        ITimelockBatchQueue.BatchAction memory a = _threeActions()[bound(selector_, 0, 2)];
        uint256 length = bound(length_, 0, 255);
        vm.assume(length != a.payload.length);
        a.payload = new bytes(length);
        _expectRejectedQueue(_invalid(a));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(a));
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLRCT-BATCH-I07.
    function test_whenDirtyBps_reverts(uint256 word_) public {
        _rejectWord(_bpsAction(2500), abi.encode(bound(word_, 65536, type(uint256).max)));
    }

    // Scenarios: BLRCT-BATCH-I08.
    function test_whenDirtyAge_reverts(uint256 word_) public {
        _rejectWord(
            _ageAction(3600),
            abi.encode(bound(word_, uint256(type(uint48).max) + 1, type(uint256).max))
        );
    }

    // Scenarios: BLRCT-BATCH-I09.
    function test_whenDirtyReferrer_reverts(uint256 word_) public {
        _rejectWord(
            _referrerAction(_recipient, true),
            abi.encode(bound(word_, uint256(type(uint160).max) + 1, type(uint256).max), true)
        );
    }

    // Scenarios: BLRCT-BATCH-I10.
    function test_whenDirtyBoolean_reverts(uint256 word_) public {
        _rejectWord(
            _referrerAction(_recipient, true),
            abi.encode(_recipient, bound(word_, 2, type(uint256).max))
        );
    }

    // Scenarios: BLRCT-BATCH-I06.
    function test_whenOutOfRangeBps_reverts(uint16 bps_) public {
        uint16 bps = uint16(bound(bps_, 10001, type(uint16).max));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidReferralFeeBps.selector,
                bps
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(bps)));
        _assertRejectedQueue(_single(_bpsAction(bps)));
    }

    // Scenarios: BLRCT-BATCH-I11.
    function test_whenZeroReferrer_reverts(bool allowed_) public {
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector)
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_referrerAction(address(0), allowed_)));
        _assertRejectedQueue(_single(_referrerAction(address(0), allowed_)));
    }

    // Scenarios: BLRCT-BATCH-P01.
    function test_whenDuplicateDomain_reverts() public {
        ITimelockBatchQueue.BatchAction memory a = _bpsAction(1);
        _expectRejectedQueue(_pending(a, 1));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_pair(a, _bpsAction(2)));
        _assertRejectedQueue(_pair(a, _bpsAction(2)));
    }

    // Scenarios: BLRCT-BATCH-P01.
    function test_whenOppositeMembership_reverts() public {
        ITimelockBatchQueue.BatchAction memory a = _referrerAction(_recipient, true);
        _expectRejectedQueue(_pending(a, 1));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_pair(a, _referrerAction(_recipient, false)));
        _assertRejectedQueue(_pair(a, _referrerAction(_recipient, false)));
    }

    // Scenarios: BLRCT-BATCH-P02.
    function test_givenOlderPending_whenLastConflicts_reverts() public {
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetPriceCacheMaxAge(3600);
        bytes32 previous = _queueDigest(id);
        _expectRejectedQueue(_pending(_ageAction(0), id));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_pair(_bpsAction(2500), _ageAction(0)));
        _assertRejectedQueue(_pair(_bpsAction(2500), _ageAction(0)));
        assertEq(_queueDigest(id), previous, "older intent untouched");
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            0,
            "earlier partial reservation rolled back"
        );
    }

    // Scenarios: BLRCT-BATCH-P03.
    function test_whenThreeDomainsInAnyBatchOrder(uint8 order_) public {
        ITimelockBatchQueue.BatchAction[] memory a = _threeActions();
        uint256[3] memory order = _permutation(uint8(bound(order_, 0, 5)));
        ITimelockBatchQueue.BatchAction[] memory sorted = new ITimelockBatchQueue.BatchAction[](3);
        for (uint256 i; i < 3; ++i) sorted[i] = a[order[i]];
        _expectQueue(sorted, _fixtureAdmin);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(sorted);
        _assertQueued(id, sorted, _fixtureAdmin);
        _makeReady(id);
        _executeAndAssert(id, _recipient);
    }

    // Scenarios: BLRCT-BATCH-N02.
    function test_whenTimestampLastRepresentable() public {
        vm.warp(uint256(type(uint48).max) - 4 days);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_bpsAction(2500)));
        assertEq(
            _timelock.getQueuedAction(id).expiresAt,
            type(uint48).max,
            "inclusive endpoint fits"
        );
    }

    // Scenarios: BLRCT-BATCH-N03.
    function test_whenTimestampOverflow_reverts(uint48 now_) public {
        vm.warp(bound(now_, uint256(type(uint48).max) - 4 days + 1, type(uint48).max));
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        assertEq(_timelock.nextActionId(), 1, "timestamp failure rolls ID back");
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            0,
            "timestamp failure releases partial key"
        );
    }

    function _rejectWord(ITimelockBatchQueue.BatchAction memory a_, bytes memory payload_) private {
        a_.payload = payload_;
        _expectRejectedQueue(_invalid(a_));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(a_));
        _assertRejectedQueue(_single(a_));
    }

    // Scenarios: BLRCT-BATCH-I08.
    function test_givenAgeWordAboveUint48_whenQueued_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        value_ = bound(value_, uint256(type(uint48).max) + 1, type(uint256).max);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(1);
        a.payload = abi.encode(value_);
        _expectRejectedQueue(_invalid(a));
        _queue(caller_, a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLRCT-BATCH-D08.
    function test_givenConfigUnavailable_whenRiskOnlyBatchQueued_thenAccepted(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        vm.prank(_fixtureAdmin);
        _config.setConfigOperator(_recipient);
        _setPolicyLifecycle(_config, false, false);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        uint64 id = _queue(caller_, a);
        _assertQueued(id, _single(a), caller_);
    }

    function _queue(
        address caller_,
        ITimelockBatchQueue.BatchAction memory a_
    ) private returns (uint64) {
        vm.prank(caller_);
        return _timelock.queueBatch(_single(a_));
    }

    // Scenarios: BLRCT-BATCH-I08.
    function test_givenRawAbiN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAgeWordAboveUint48_whenQueued_reverts(
            address(0xabc1),
            uint8(1),
            uint256(type(uint48).max) + 1
        );
        _restore(checkpoint);
        test_givenAgeWordAboveUint48_whenQueued_reverts(
            address(0xabc1),
            uint8(1),
            type(uint256).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLRCT-BATCH-A01.
    function test_whenUnauthorizedProposer_reverts(address caller_) public {
        _outsider(caller_);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-L01, BLRCT-BATCH-L02.
    function test_givenInactive_whenQueued_reverts(bool enabled_) public {
        _setPolicyLifecycle(_timelock, false, enabled_);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-L03.
    function test_givenDisabled_whenQueued_reverts() public {
        vm.prank(_fixtureAdmin);
        _timelock.disable("");
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D01, BLRCT-BATCH-D02, BLRCT-BATCH-D03.
    function test_givenRiskUnavailable_whenQueued_reverts(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyLifecycle(_risk, active_, enabled_);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D04.
    function test_givenOperatorChanged_whenQueued_reverts(address operator_) public {
        vm.assume(operator_ != address(_timelock));
        vm.prank(_fixtureAdmin);
        _risk.setConfigOperator(operator_);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D05.
    function test_givenForeignKernel_whenQueued_reverts() public {
        _setPolicyLifecycle(_risk, false, false);
        vm.mockCall(address(_risk), abi.encodeWithSignature("kernel()"), abi.encode(address(0xF0)));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(_kernel),
                address(0xF0)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D06.
    function test_givenMalformedKernel_whenQueued_reverts() public {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D06.
    function test_givenMalformedEnablement_whenQueued_reverts() public {
        vm.mockCall(address(_risk), abi.encodeWithSignature("isEnabled()"), abi.encode(uint256(2)));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D07.
    function test_givenMalformedOperator_whenQueued_reverts() public {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(type(uint256).max)
        );
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D09.
    function test_givenMalformedSetting_whenQueued_reverts() public {
        vm.mockCall(
            address(_risk),
            abi.encodePacked(IBurnerLoansRisk.referralFeeBps.selector),
            abi.encode(type(uint256).max)
        );
        uint64 next = _timelock.nextActionId();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        assertEq(_timelock.nextActionId(), next, "invalid metadata consumes no ID");
    }

    // Scenarios: BLRCT-BATCH-D08.
    function test_givenUpstreamUnavailable_whenQueued(bool active_, bool enabled_) public {
        _setPolicyLifecycle(_config, active_, enabled_);
        _setPolicyLifecycle(_core, active_, enabled_);
        _expectQueue(_single(_bpsAction(2500)), _fixtureAdmin);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertQueued(id, _single(_bpsAction(2500)), _fixtureAdmin);
    }

    // Scenarios: BLRCT-BATCH-L04, BLRCT-BATCH-N01.
    function test_whenPermittedProposer(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        _expectQueue(_single(_bpsAction(2500)), caller_);
        vm.prank(caller_);
        uint64 id = _timelock.queueBatch(_single(_bpsAction(2500)));
        _assertQueued(id, _single(_bpsAction(2500)), caller_);
    }

    // Scenarios: BLRCT-BATCH-L04.
    function test_givenReEnabled_whenQueued() public {
        vm.prank(_fixtureAdmin);
        _timelock.disable("");
        vm.prank(_fixtureAdmin);
        _timelock.reEnable();
        _executeFixtureKernelAction(Actions.DeactivatePolicy, address(_timelock));
        _executeFixtureKernelAction(Actions.ActivatePolicy, address(_timelock));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_bpsAction(2500)));
        assertEq(id, 1, "reenabled and reactivated queue accepts intent");
    }

    // Scenarios: BLRCT-BATCH-D06.
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
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLRCT-BATCH-D07, BLRCT-BATCH-D09.
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
            : abi.encodePacked(IBurnerLoansRisk.referralFeeBps.selector);
        if (reverts_) vm.mockCallRevert(address(_risk), callData, data_);
        else vm.mockCall(address(_risk), callData, data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLRCT-BATCH-D08.
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
        _setPolicyLifecycle(_config, configActive_, configEnabled_);
        _setPolicyLifecycle(_core, coreActive_, coreEnabled_);
        _expectQueue(_single(_bpsAction(2500)), _fixtureAdmin);
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueBatch(_single(_bpsAction(2500)));
        vm.clearMockedCalls();
        _assertQueued(id, _single(_bpsAction(2500)), _fixtureAdmin);
    }

    function _expectNoUpstreamDiscoveryCalls() private {
        vm.expectCall(address(_config), abi.encodeWithSignature("facility()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(0));
    }

    // Scenarios: BLRCT-BATCH-D08.
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

    // Scenarios: BLRCT-BATCH-D06.
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
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D07, BLRCT-BATCH-D09.
    function test_givenDirtySettingWords_whenQueueRejected(bool operator_) public {
        _beforeQueue = _economicDigest();
        _next = _timelock.nextActionId();
        vm.mockCall(
            address(_risk),
            operator_
                ? abi.encodeWithSignature("configOperator()")
                : abi.encodePacked(IBurnerLoansRisk.referralFeeBps.selector),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueBatch(_single(_bpsAction(2500)));
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-BATCH-D06, BLRCT-BATCH-D07, BLRCT-BATCH-D09.
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
