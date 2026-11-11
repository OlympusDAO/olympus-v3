// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansRiskConfigTimelockQueueSetReferralFeeBpsTest is
    BurnerLoansRiskConfigTimelockTest
{
    // Scenarios: BLRCT-QUEUE-BPS-A01.
    function test_whenUnauthorizedProposer_reverts(address caller_) public {
        _outsider(caller_);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-L01, BLRCT-QUEUE-BPS-L02.
    function test_givenInactive_whenQueued_reverts(bool enabled_) public {
        if (!enabled_) _timelock.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-L03.
    function test_givenDisabled_whenQueued_reverts() public {
        _timelock.disable("");
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D01, BLRCT-QUEUE-BPS-D02, BLRCT-QUEUE-BPS-D03.
    function test_givenRiskUnavailable_whenQueued_reverts(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        _setState(_risk, active_, enabled_);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D04.
    function test_givenOperatorChanged_whenQueued_reverts(address operator_) public {
        vm.assume(operator_ != address(_timelock));
        _risk.setConfigOperator(operator_);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_NotController.selector
            )
        );
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D05.
    function test_givenForeignKernel_whenQueued_reverts() public {
        _setState(_risk, false, false);
        vm.mockCall(address(_risk), abi.encodeWithSignature("kernel()"), abi.encode(address(0xF0)));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_risk),
                address(_kernel),
                address(0xF0)
            )
        );
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D06.
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
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D06.
    function test_givenMalformedEnablement_whenQueued_reverts() public {
        vm.mockCall(address(_risk), abi.encodeWithSignature("isEnabled()"), abi.encode(uint256(2)));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D07.
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
        _timelock.queueSetReferralFeeBps(2500);
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D09.
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
        _timelock.queueSetReferralFeeBps(2500);
        assertEq(_timelock.nextActionId(), next, "invalid metadata consumes no ID");
    }

    // Scenarios: BLRCT-QUEUE-BPS-D08.
    function test_givenUpstreamUnavailable_whenQueued(bool active_, bool enabled_) public {
        _setState(_config, active_, enabled_);
        _setState(_core, active_, enabled_);
        _expectQueue(_single(_bpsAction(2500)), address(this));
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _assertQueued(id, _single(_bpsAction(2500)), address(this));
    }

    // Scenarios: BLRCT-QUEUE-BPS-L04, BLRCT-QUEUE-BPS-N01.
    function test_whenPermittedProposer(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        _expectQueue(_single(_bpsAction(2500)), caller_);
        vm.prank(caller_);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        _assertQueued(id, _single(_bpsAction(2500)), caller_);
    }

    // Scenarios: BLRCT-QUEUE-BPS-L04.
    function test_givenReEnabled_whenQueued() public {
        _timelock.disable("");
        _timelock.reEnable();
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        assertEq(id, 1, "reenabled and reactivated queue accepts intent");
    }

    // Scenarios: BLRCT-QUEUE-BPS-I01.
    function test_whenInvalidPercentage_reverts(uint16 bps_) public {
        uint16 bps = uint16(bound(bps_, 10001, type(uint16).max));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidReferralFeeBps.selector,
                bps
            )
        );
        _timelock.queueSetReferralFeeBps(bps);
        _assertRejectedQueue(_single(_bpsAction(bps)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-N01, BLRCT-QUEUE-BPS-P01.
    function test_whenPercentageBoundaries() public {
        uint16[4] memory values = [uint16(0), 1, 9999, 10000];
        for (uint256 i; i < values.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            _expectQueue(_single(_bpsAction(values[i])), address(this));
            uint64 id = _timelock.queueSetReferralFeeBps(values[i]);
            _assertQueued(id, _single(_bpsAction(values[i])), address(this));
            _restore(checkpoint);
        }
    }

    // Scenarios: BLRCT-QUEUE-BPS-P02.
    function test_givenPendingPercentage_whenQueuedAgain_reverts() public {
        uint64 id = _timelock.queueSetReferralFeeBps(1);
        _expectRejectedQueue(_pending(_bpsAction(2), id));
        _timelock.queueSetReferralFeeBps(2);
        _assertRejectedQueue(_single(_bpsAction(2)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-P03.
    function test_givenOtherDomainsPending_whenQueued() public {
        _timelock.queueSetPriceCacheMaxAge(3600);
        _timelock.queueSetReferrerAllowed(_recipient, true);
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        assertEq(id, 3, "three independent intents");
        assertEq(_timelock.pendingActionId(_key(_ageAction(3600))), 1, "age key retained");
        assertEq(
            _timelock.pendingActionId(_key(_referrerAction(_recipient, true))),
            2,
            "membership key retained"
        );
    }

    // Scenarios: BLRCT-QUEUE-BPS-D06.
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
        _timelock.queueSetReferralFeeBps(2500);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLRCT-QUEUE-BPS-D07, BLRCT-QUEUE-BPS-D09.
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
        _timelock.queueSetReferralFeeBps(2500);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
        assertEq(
            _timelock.pendingActionId(_key(_bpsAction(2500))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLRCT-QUEUE-BPS-D08.
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
        _expectQueue(_single(_bpsAction(2500)), address(this));
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        uint64 id = _timelock.queueSetReferralFeeBps(2500);
        vm.clearMockedCalls();
        _assertQueued(id, _single(_bpsAction(2500)), address(this));
    }

    function _expectNoUpstreamDiscoveryCalls() private {
        vm.expectCall(address(_config), abi.encodeWithSignature("facility()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(0));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D08.
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

    // Scenarios: BLRCT-QUEUE-BPS-D06.
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
        _timelock.queueSetReferralFeeBps(2500);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D07, BLRCT-QUEUE-BPS-D09.
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
        _timelock.queueSetReferralFeeBps(2500);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_bpsAction(2500)));
    }

    // Scenarios: BLRCT-QUEUE-BPS-D06, BLRCT-QUEUE-BPS-D07, BLRCT-QUEUE-BPS-D09.
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

    // Scenarios: BLRCT-QUEUE-BPS-P01.
    function test_givenMaximumCurrentPercentage_whenSameValueQueued() public {
        _risk.setReferralFeeBps(10000);
        _expectQueue(_single(_bpsAction(10000)), address(this));
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setReferralFeeBps, (uint16(10000))),
            uint64(0)
        );
        uint64 id = _timelock.queueSetReferralFeeBps(10000);
        _assertQueued(id, _single(_bpsAction(10000)), address(this));
    }
}
