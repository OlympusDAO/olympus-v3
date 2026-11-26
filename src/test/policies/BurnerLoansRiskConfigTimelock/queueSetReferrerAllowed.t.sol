// SPDX-License-Identifier: Unlicense
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

contract BurnerLoansRiskConfigTimelockQueueSetReferrerAllowedTest is
    BurnerLoansRiskConfigTimelockTest
{
    // Scenarios: BLRCT-QUEUE-REFERRER-A01.
    function test_whenUnauthorizedProposer_reverts(address caller_) public {
        _outsider(caller_);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-L01, BLRCT-QUEUE-REFERRER-L02.
    function test_givenInactive_whenQueued_reverts(bool enabled_) public {
        _setPolicyLifecycle(_timelock, false, enabled_);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-L03.
    function test_givenDisabled_whenQueued_reverts() public {
        vm.prank(_fixtureAdmin);
        _timelock.disable("");
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D01, BLRCT-QUEUE-REFERRER-D02, BLRCT-QUEUE-REFERRER-D03.
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D04.
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D05.
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D06.
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D06.
    function test_givenMalformedEnablement_whenQueued_reverts() public {
        vm.mockCall(address(_risk), abi.encodeWithSignature("isEnabled()"), abi.encode(uint256(2)));
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D07.
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D09.
    function test_givenMalformedSetting_whenQueued_reverts() public {
        vm.mockCall(
            address(_risk),
            abi.encodePacked(IBurnerLoansRisk.isReferrerAllowed.selector),
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        assertEq(_timelock.nextActionId(), next, "invalid metadata consumes no ID");
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D08.
    function test_givenUpstreamUnavailable_whenQueued(bool active_, bool enabled_) public {
        _setPolicyLifecycle(_config, active_, enabled_);
        _setPolicyLifecycle(_core, active_, enabled_);
        _expectQueue(_single(_referrerAction(_recipient, true)), _fixtureAdmin);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertQueued(id, _single(_referrerAction(_recipient, true)), _fixtureAdmin);
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-L04, BLRCT-QUEUE-REFERRER-N01.
    function test_whenPermittedProposer(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        _expectQueue(_single(_referrerAction(_recipient, true)), caller_);
        vm.prank(caller_);
        uint64 id = _timelock.queueSetReferrerAllowed(_recipient, true);
        _assertQueued(id, _single(_referrerAction(_recipient, true)), caller_);
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-L04.
    function test_givenReEnabled_whenQueued() public {
        vm.prank(_fixtureAdmin);
        _timelock.disable("");
        vm.prank(_fixtureAdmin);
        _timelock.reEnable();
        _executeFixtureKernelAction(Actions.DeactivatePolicy, address(_timelock));
        _executeFixtureKernelAction(Actions.ActivatePolicy, address(_timelock));
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferrerAllowed(_recipient, true);
        assertEq(id, 1, "reenabled and reactivated queue accepts intent");
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-I01.
    function test_whenZeroReferrer_reverts(bool allowed_) public {
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector)
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferrerAllowed(address(0), allowed_);
        _assertRejectedQueue(_single(_referrerAction(address(0), allowed_)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-N01, BLRCT-QUEUE-REFERRER-P01.
    function test_whenMembershipIntent(address referrer_, bool allowed_, bool old_) public {
        vm.assume(referrer_ != address(0));
        vm.prank(_fixtureAdmin);
        _risk.setReferrerAllowed(referrer_, old_);
        _expectQueue(_single(_referrerAction(referrer_, allowed_)), _fixtureAdmin);
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferrerAllowed(referrer_, allowed_);
        _assertQueued(id, _single(_referrerAction(referrer_, allowed_)), _fixtureAdmin);
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-P02, BLRCT-QUEUE-REFERRER-P05.
    function test_givenPendingMembership_whenOppositeQueued_reverts(bool first_) public {
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferrerAllowed(_recipient, first_);
        _expectRejectedQueue(_pending(_referrerAction(_recipient, !first_), id));
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferrerAllowed(_recipient, !first_);
        _assertRejectedQueue(_single(_referrerAction(_recipient, !first_)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-P03, BLRCT-QUEUE-REFERRER-P06.
    function test_givenOtherDomainsPending_whenQueued() public {
        vm.prank(_fixtureAdmin);
        _timelock.queueSetPriceCacheMaxAge(3600);
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferralFeeBps(2500);
        vm.prank(_fixtureAdmin);
        uint64 first = _timelock.queueSetReferrerAllowed(_recipient, true);
        vm.prank(_fixtureAdmin);
        uint64 second = _timelock.queueSetReferrerAllowed(_borrower, false);
        assertEq(first, 3, "three independent domains");
        assertEq(second, 4, "per-address membership independent");
        assertEq(_timelock.pendingActionId(_key(_ageAction(3600))), 1, "age retained");
        assertEq(_timelock.pendingActionId(_key(_bpsAction(2500))), 2, "percentage retained");
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D06.
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
        assertEq(
            _timelock.pendingActionId(_key(_referrerAction(_recipient, true))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D07, BLRCT-QUEUE-REFERRER-D09.
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
            : abi.encodePacked(IBurnerLoansRisk.isReferrerAllowed.selector);
        if (reverts_) vm.mockCallRevert(address(_risk), callData, data_);
        else vm.mockCall(address(_risk), callData, data_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferrerAllowed(_recipient, true);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
        assertEq(
            _timelock.pendingActionId(_key(_referrerAction(_recipient, true))),
            0,
            "metadata rejection leaves no key"
        );
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D08.
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
        _expectQueue(_single(_referrerAction(_recipient, true)), _fixtureAdmin);
        vm.mockCallRevert(address(_config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("risk()"), hex"deadbeef");
        vm.prank(_fixtureAdmin);
        uint64 id = _timelock.queueSetReferrerAllowed(_recipient, true);
        vm.clearMockedCalls();
        _assertQueued(id, _single(_referrerAction(_recipient, true)), _fixtureAdmin);
    }

    function _expectNoUpstreamDiscoveryCalls() private {
        vm.expectCall(address(_config), abi.encodeWithSignature("facility()"), uint64(0));
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(0));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D08.
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

    // Scenarios: BLRCT-QUEUE-REFERRER-D06.
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
        _timelock.queueSetReferrerAllowed(_recipient, true);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D07, BLRCT-QUEUE-REFERRER-D09.
    function test_givenDirtySettingWords_whenQueueRejected(bool operator_) public {
        _beforeQueue = _economicDigest();
        _next = _timelock.nextActionId();
        vm.mockCall(
            address(_risk),
            operator_
                ? abi.encodeWithSignature("configOperator()")
                : abi.encodePacked(IBurnerLoansRisk.isReferrerAllowed.selector),
            abi.encode(type(uint256).max)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRiskConfigTimelock.BurnerLoansRiskTimelock_InvalidRisk.selector,
                address(_risk)
            )
        );
        vm.prank(_fixtureAdmin);
        _timelock.queueSetReferrerAllowed(_recipient, true);
        vm.clearMockedCalls();
        _assertRejectedQueue(_single(_referrerAction(_recipient, true)));
    }

    // Scenarios: BLRCT-QUEUE-REFERRER-D06, BLRCT-QUEUE-REFERRER-D07, BLRCT-QUEUE-REFERRER-D09.
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
