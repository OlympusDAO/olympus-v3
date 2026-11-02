// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueBatchTest is BurnerLoansConfigTimelockTest {
    using stdStorage for StdStorage;

    // Scenarios: BLQB-A01.
    function test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts(
        address caller_
    ) public {
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-A02.
    function test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts(
        address caller_
    ) public {
        _config.disable("");
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-A03.
    function test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-A04.
    function test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        _config.disable("");
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-A05.
    function test_givenPermittedProposer_whenQueued_thenValidatedAndStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQB-L01.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-L02.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-L03.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-L04.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-L05.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L06.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L07.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L08.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L09.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L10.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L11.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L12.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
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

    // Scenarios: BLQB-L13.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-L14.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-L15.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-D01.
    function test_givenDisabledAndUnauthorized_whenEmptyBatchQueued_reverts(
        address caller_
    ) public {
        _timelock.disable("");
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](0);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _timelock.queueBatch(batch);
        _assertRejectedQueue(batch);
    }

    // Scenarios: BLQB-N01.
    function test_givenAnyCaller_whenOversizedBatchQueued_reverts(
        address caller_,
        uint256 length_
    ) public {
        _admin(caller_);
        length_ = bound(length_, 16, 128);
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](
            length_
        );
        _expectRejectedQueue(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                length_,
                uint256(15)
            )
        );
        vm.prank(caller_);
        _timelock.queueBatch(batch);
        _assertRejectedQueue(batch);
    }

    // Scenarios: BLQB-I07.
    function test_givenWrongTarget_whenQueued_reverts(
        address caller_,
        uint8 role_,
        address target_
    ) public {
        _proposer(caller_, role_);
        vm.assume(target_ != address(_config) && target_ != address(_risk));
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.target = target_;
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I08.
    function test_givenEachSupportedShape_whenPayloadShortByOne_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction[] memory shapes = _supportedActions();
        for (uint256 i; i < shapes.length; ++i) {
            ITimelockBatchQueue.BatchAction memory a = shapes[i];
            a.payload = new bytes(a.payload.length - 1);
            _expectRejectedQueue(_invalid(a));
            vm.prank(caller_);
            _queue(a);
            _assertRejectedQueue(_single(a));
        }
    }

    // Scenarios: BLQB-I09.
    function test_givenEachSupportedShape_whenPayloadLongByOne_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction[] memory shapes = _supportedActions();
        for (uint256 i; i < shapes.length; ++i) {
            ITimelockBatchQueue.BatchAction memory a = shapes[i];
            a.payload = new bytes(a.payload.length + 1);
            _expectRejectedQueue(_invalid(a));
            vm.prank(caller_);
            _queue(a);
            _assertRejectedQueue(_single(a));
        }
    }

    // Scenarios: BLQB-I10.
    function test_givenEachSupportedShape_whenPayloadExtraWord_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction[] memory shapes = _supportedActions();
        for (uint256 i; i < shapes.length; ++i) {
            ITimelockBatchQueue.BatchAction memory a = shapes[i];
            a.payload = new bytes(a.payload.length + 32);
            _expectRejectedQueue(_invalid(a));
            vm.prank(caller_);
            _queue(a);
            _assertRejectedQueue(_single(a));
        }
    }

    // Scenarios: BLQB-I11.
    function test_givenLaterUnregisteredAsset_whenQueued_thenEarlierKeyRollsBack(
        address caller_,
        uint8 role_,
        address unknown_
    ) public {
        _proposer(caller_, role_);
        vm.assume(!_config.isAssetConfigured(unknown_));
        ITimelockBatchQueue.BatchAction[] memory batch = _pair(
            _capAction(address(_asset), 200000e9),
            _feeAction(unknown_, _fees())
        );
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                unknown_
            )
        );
        vm.prank(caller_);
        _timelock.queueBatch(batch);
        _assertRejectedQueue(batch);
        assertEq(_timelock.pendingActionId(_key(batch[0])), 0, "Earlier key rolled back");
    }

    // Scenarios: BLQB-N02.
    function test_givenUnsupportedSelector_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bytes4 selector_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction[] memory admitted = _supportedActions();
        for (uint256 i; i < admitted.length; ++i) vm.assume(selector_ != admitted[i].selector);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.selector = selector_;
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-N03.
    function test_givenAgeWordAboveUint48_whenQueued_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        value_ = bound(value_, uint256(type(uint48).max) + 1, type(uint256).max);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(1);
        a.payload = abi.encode(value_);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-N04.
    function test_givenNoncanonicalBool_whenOriginationsQueued_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        value_ = bound(value_, 2, type(uint256).max);
        ITimelockBatchQueue.BatchAction memory a = _originationsAction(address(_asset), false);
        a.payload = abi.encode(address(_asset), value_);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-P07.
    function test_givenNoncanonicalBool_whenWithdrawalQueued_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        value_ = bound(value_, 2, type(uint256).max);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        a.payload = abi.encode(address(_asset), value_);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-N05.
    function test_givenCounterOverflow_whenQueued_thenReadableError(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        uint64 existing = _timelock.queueBatch(_single(_feeAction(address(_asset), _fees())));
        bytes32 original = _queueDigest(existing);
        stdstore
            .target(address(_timelock))
            .sig("nextActionId()")
            .enable_packed_slots()
            .checked_write(uint256(type(uint64).max));
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(64),
                uint256(type(uint64).max) + 1
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(
            _queueDigest(existing),
            original,
            "Overflow preserves existing payloads and key owners"
        );
        assertEq(_timelock.pendingActionId(_key(a)), 0, "Overflow leaks no new key");
    }

    // Scenarios: BLQB-N06.
    function test_givenExecutableTimestampOverflow_whenQueued_thenReadableError(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        uint64 existing = _timelock.queueBatch(_single(_feeAction(address(_asset), _fees())));
        bytes32 original = _queueDigest(existing);
        vm.warp(uint256(type(uint48).max) - 1 days + 1);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + 1
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(
            _queueDigest(existing),
            original,
            "Overflow preserves existing payloads and key owners"
        );
        assertEq(_timelock.pendingActionId(_key(a)), 0, "Overflow leaks no new key");
    }

    // Scenarios: BLQB-N07.
    function test_givenExpiryTimestampOverflow_whenQueued_thenReadableError(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        uint64 existing = _timelock.queueBatch(_single(_feeAction(address(_asset), _fees())));
        bytes32 original = _queueDigest(existing);
        vm.warp(uint256(type(uint48).max) - 4 days + 1);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + 1
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(
            _queueDigest(existing),
            original,
            "Overflow preserves existing payloads and key owners"
        );
        assertEq(_timelock.pendingActionId(_key(a)), 0, "Overflow leaks no new key");
    }

    // Scenarios: BLQB-P01.
    function test_givenRegisteredAsset_whenOriginationsTrueQueued_thenStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _originationsAction(address(_asset), true);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQB-P02.
    function test_givenRegisteredAsset_whenOriginationsFalseQueued_thenStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _originationsAction(address(_asset), false);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQB-I01.
    function test_givenFormerFeeRoutingSelector_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.selector = bytes4(keccak256("setSendFeesToDistributor(bool)"));
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I02.
    function test_givenFormerYieldRoutingSelector_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.selector = bytes4(keccak256("setSendYieldToDistributor(bool)"));
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I03.
    function test_givenFormerPendingPayoutRescueSelector_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.selector = bytes4(keccak256("rescuePendingPayout(address,address,address)"));
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I04.
    function test_givenLegacyPartialFeePayload_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        a.payload = new bytes(288);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I05.
    function test_givenLegacyPartialRiskPayload_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        a.payload = new bytes(416);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I06.
    function test_givenPayoutTarget_whenMarketSetterQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.target = address(_payout);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I12.
    function test_givenConfigAgeForwarding_whenQueued_reverts(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        a.target = address(_config);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I13.
    function test_givenRiskMarketSetter_whenQueued_reverts(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.target = address(_risk);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I14.
    function test_givenNonselectedRisk_whenQueued_reverts(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        a.target = address(_recipient);
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-I15.
    function test_givenAdminOnlyRiskSelectors_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        bytes4[3] memory selectors = [
            IBurnerLoansRisk.setPriceCache.selector,
            IBurnerLoansRisk.setBackingOracle.selector,
            bytes4(keccak256("setConfigOperator(address)"))
        ];
        for (uint256 i; i < selectors.length; ++i) {
            ITimelockBatchQueue.BatchAction memory a = ITimelockBatchQueue.BatchAction(
                address(_risk),
                selectors[i],
                abi.encode(_recipient)
            );
            _expectRejectedQueue(_invalid(a));
            vm.prank(caller_);
            _queue(a);
            _assertRejectedQueue(_single(a));
        }
    }

    // Scenarios: BLQB-P03.
    function test_givenEachSetterRepeatedInSameBatch_whenQueued_thenAtomicConflict(
        address caller_,
        uint8 role_,
        bool same_
    ) public {
        _proposer(caller_, role_);
        _useVaultAsset();
        ITimelockBatchQueue.BatchAction[] memory shapes = _supportedActions();
        uint256 checkpoint = vm.snapshotState();
        for (uint256 i; i < 5; ++i) {
            ITimelockBatchQueue.BatchAction memory a = shapes[i];
            ITimelockBatchQueue.BatchAction memory b = ITimelockBatchQueue.BatchAction(
                shapes[i].target,
                shapes[i].selector,
                bytes.concat(shapes[i].payload)
            );
            if (!same_) b = _alternative(a);
            ITimelockBatchQueue.BatchAction[] memory batch = _pair(a, b);
            uint64 next = _timelock.nextActionId();
            _expectRejectedQueue(_pending(a, next));
            vm.prank(caller_);
            _timelock.queueBatch(batch);
            _assertRejectedQueue(batch);
            assertEq(_timelock.pendingActionId(_key(a)), 0, "First duplicate key rolled back");
            assertTrue(vm.revertToState(checkpoint), "Restore each setter");
        }
    }

    // Scenarios: BLQB-P04.
    function test_givenEachSetterAlreadyPending_whenQueued_thenOriginalPreserved(
        address caller_,
        uint8 role_,
        bool same_
    ) public {
        _proposer(caller_, role_);
        _useVaultAsset();
        ITimelockBatchQueue.BatchAction[] memory shapes = _supportedActions();
        uint256 checkpoint = vm.snapshotState();
        for (uint256 i; i < 5; ++i) {
            ITimelockBatchQueue.BatchAction memory a = shapes[i];
            uint64 owner = _queue(a);
            bytes32 original = _queueDigest(owner);
            if (!same_) a = _alternative(a);
            _expectRejectedQueue(_pending(a, owner));
            vm.prank(caller_);
            _queue(a);
            _assertRejectedQueue(_single(a));
            assertEq(_queueDigest(owner), original, "Original action unchanged");
            assertTrue(vm.revertToState(checkpoint), "Restore each setter");
        }
    }

    // Scenarios: BLQB-P05.
    function test_givenOneAction_whenQueued_thenExactCommitment(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQB-P06.
    function test_givenFifteenDistinctKeys_whenQueued_thenExactOrderedMetadata(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction[] memory batch = new ITimelockBatchQueue.BatchAction[](15);
        for (uint256 i; i < 3; ++i) {
            (address token, ) = _vaultAsset();
            batch[i * 5] = _capAction(token, 200000e9);
            batch[i * 5 + 1] = _originationsAction(token, false);
            batch[i * 5 + 2] = _riskAction(token, _riskInput());
            batch[i * 5 + 3] = _sharesAction(token, true);
            batch[i * 5 + 4] = _feeAction(token, _fees());
        }
        _expectQueue(batch, caller_);
        vm.prank(caller_);
        uint64 id = _timelock.queueBatch(batch);
        _assertQueued(id, batch, caller_);
    }

    // Scenarios: BLQB-P08.
    function test_givenDirtyAddressWord_whenQueued_reverts(
        address caller_,
        uint8 role_,
        uint256 upper_
    ) public {
        _proposer(caller_, role_);
        upper_ = bound(upper_, 1, type(uint96).max);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        a.payload = abi.encode((upper_ << 160) | uint160(address(_asset)), uint256(200000e9));
        _expectRejectedQueue(_invalid(a));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQB-P09.
    function test_givenEachNumericFieldAboveAbiWidth_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _rejectWideField(_capAction(address(_asset), 200000e9), 1, 128, caller_);
        _rejectWideField(_riskAction(address(_asset), _riskInput()), 1, 16, caller_);
        _rejectWideField(_riskAction(address(_asset), _riskInput()), 2, 16, caller_);
        _rejectWideField(_riskAction(address(_asset), _riskInput()), 3, 16, caller_);
        _rejectWideField(_riskAction(address(_asset), _riskInput()), 4, 48, caller_);
        _rejectWideField(_riskAction(address(_asset), _riskInput()), 5, 48, caller_);
        _rejectWideField(_riskAction(address(_asset), _riskInput()), 6, 128, caller_);
        _rejectWideField(_feeAction(address(_asset), _fees()), 1, 16, caller_);
        _rejectWideField(_feeAction(address(_asset), _fees()), 2, 16, caller_);
        _rejectWideField(_feeAction(address(_asset), _fees()), 3, 16, caller_);
        _rejectWideField(_feeAction(address(_asset), _fees()), 4, 16, caller_);
        _rejectWideField(_ageAction(3600), 0, 48, caller_);
    }

    // Scenarios: BLQB-P10.
    function test_givenRiskAndFeeForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _riskAction(address(_asset), _riskInput()),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQB-P20.
    function test_givenCapAndOriginationsForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _capAction(address(_asset), 200000e9),
            _originationsAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P21.
    function test_givenCapAndRiskForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _capAction(address(_asset), 200000e9),
            _riskAction(address(_asset), _riskInput()),
            caller_
        );
    }

    // Scenarios: BLQB-P22.
    function test_givenCapAndSharesForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _capAction(address(_asset), 200000e9),
            _sharesAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P23.
    function test_givenCapAndFeeForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _capAction(address(_asset), 200000e9),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQB-P24.
    function test_givenOriginationsAndRiskForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _originationsAction(address(_asset), false),
            _riskAction(address(_asset), _riskInput()),
            caller_
        );
    }

    // Scenarios: BLQB-P25.
    function test_givenOriginationsAndSharesForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _originationsAction(address(_asset), false),
            _sharesAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P26.
    function test_givenOriginationsAndFeeForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _originationsAction(address(_asset), false),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQB-P27.
    function test_givenRiskAndSharesForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _riskAction(address(_asset), _riskInput()),
            _sharesAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P28.
    function test_givenSharesAndFeeForSameAsset_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _batchPair(
            _sharesAction(address(_asset), false),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQB-P14.
    function test_givenOriginationsPending_whenSameAssetQueuedAgain_reverts(
        address caller_,
        uint8 role_,
        bool same_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _originationsAction(address(_asset), false);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        bytes32 original = _queueDigest(id);
        a.payload = abi.encode(address(_asset), same_ ? false : true);
        _expectRejectedQueue(_pending(a, id));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(_queueDigest(id), original, "Original originations proposal preserved");
    }

    // Scenarios: BLQB-P15.
    function test_givenOriginationsPending_whenOtherAssetQueued_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address other, ) = _vaultAsset();
        _independentActions(
            _originationsAction(address(_asset), false),
            _originationsAction(other, true),
            caller_
        );
    }

    // Scenarios: BLQB-P16.
    function test_givenCapPending_whenOriginationsQueued_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _capAction(address(_asset), 200000e9),
            _originationsAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P17.
    function test_givenRiskPending_whenOriginationsQueued_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _riskAction(address(_asset), _riskInput()),
            _originationsAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P18.
    function test_givenSharesPending_whenOriginationsQueued_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _sharesAction(address(_asset), false),
            _originationsAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P19.
    function test_givenFeePending_whenOriginationsQueued_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _feeAction(address(_asset), _fees()),
            _originationsAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLQB-P29.
    function test_givenEachSetterForDifferentAssets_whenBatched_thenIndependentBothOrders(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address other, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction[] memory shapes = _supportedActions();
        for (uint256 i; i < 5; ++i) {
            ITimelockBatchQueue.BatchAction memory a = shapes[i];
            ITimelockBatchQueue.BatchAction memory b = ITimelockBatchQueue.BatchAction(
                shapes[i].target,
                shapes[i].selector,
                bytes.concat(shapes[i].payload)
            );
            bytes memory payload = bytes.concat(b.payload);
            assembly ("memory-safe") {
                mstore(add(payload, 32), other)
            }
            b.payload = payload;
            _batchPair(a, b, caller_);
        }
    }

    // Scenarios: BLQB-P11.
    function test_givenConfigAndRiskActions_whenBatched_thenIndependentTargets(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _batchPair(_capAction(address(_asset), 200000e9), _ageAction(3600), caller_);
    }

    // Scenarios: BLQB-P12.
    function test_givenRiskOperatorDifferent_whenConfigOnlyBatchQueued_thenAccepted(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(zero_ ? address(0) : _recipient);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQB-P13.
    function test_givenConfigUnavailable_whenRiskOnlyBatchQueued_thenAccepted(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _config.setConfigOperator(_recipient);
        _setState(_config, false, false);
        ITimelockBatchQueue.BatchAction memory a = _ageAction(3600);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQB-D02.
    function test_givenRiskOperatorRevoked_whenMixedBatchQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _risk.setConfigOperator(zero_ ? address(0) : _recipient);
        ITimelockBatchQueue.BatchAction[] memory batch = _pair(
            _capAction(address(_asset), 200000e9),
            _ageAction(3600)
        );
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _timelock.queueBatch(batch);
        _assertRejectedQueue(batch);
        assertEq(_timelock.pendingActionId(_key(batch[0])), 0, "Mixed queue owns no partial key");
    }

    // Scenarios: BLQB-D03.
    function test_givenConfigOperatorRevoked_whenMixedBatchQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _risk.setConfigOperator(address(_timelock));
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        ITimelockBatchQueue.BatchAction[] memory batch = _pair(
            _capAction(address(_asset), 200000e9),
            _ageAction(3600)
        );
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _timelock.queueBatch(batch);
        _assertRejectedQueue(batch);
        assertEq(_timelock.pendingActionId(_key(batch[0])), 0, "Mixed queue owns no partial key");
    }

    // Scenarios: BLCT-QUEUED-ACTION-N02.
    function test_givenPendingBatch_whenEachValidSubactionRead_thenExactPayload(
        address caller_,
        uint256 index_
    ) public {
        ITimelockBatchQueue.BatchAction[] memory batch = _pair(
            _capAction(address(_asset), 200000e9),
            _feeAction(address(_asset), _fees())
        );
        uint64 id = _timelock.queueBatch(batch);
        index_ = bound(index_, 0, 1);
        bytes32 beforeState = _queueDigest(id);
        vm.prank(caller_);
        (address target, bytes4 selector, bytes memory payload) = _timelock.getQueuedSubAction(
            id,
            index_
        );
        assertEq(
            abi.encode(target, selector, payload),
            abi.encode(batch[index_].target, batch[index_].selector, batch[index_].payload),
            "Exact indexed payload"
        );
        assertEq(_queueDigest(id), beforeState, "Getter read-only");
    }

    // Scenarios: BLCT-QUEUED-STATE-P01.
    function test_givenPendingBatch_whenStateRead_thenIndependentCommitment(
        address caller_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectQueue(_single(a), address(this));
        vm.prank(address(this));
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), address(this));
        vm.prank(caller_);
        (bytes32 key, bytes32 hash) = _timelock.getQueuedConfigState(id, 0, 0);
        assertEq(key, _key(a), "Scoped key");
        assertEq(hash, _hash(a), "Full pre-state hash");
    }

    // Scenarios: BLCT-QUEUED-STATE-P02.
    function test_givenMissingId_whenStateGettersRead_thenDefaults(
        address caller_,
        uint64 id_,
        bytes32 key_
    ) public {
        for (uint256 i; i < 3; ++i) {
            uint64 id = i == 0 ? 0 : i == 1 ? type(uint64).max : id_;
            vm.prank(caller_);
            assertEq(_timelock.getQueuedConfigStateCount(id, 0), 0, "Missing count zero");
            assertEq(
                _timelock.getQueuedConfigDestination(id, 0),
                address(0),
                "Missing destination zero"
            );
            assertEq(_timelock.pendingActionId(key_), 0, "Free key owner zero");
        }
    }

    // Scenarios: BLCT-QUEUED-STATE-P03.
    function test_givenPendingAction_whenStateIndexOutOfBounds_reverts(
        address caller_,
        uint256 index_
    ) public {
        uint64 id = _queue(_capAction(address(_asset), 200000e9));
        index_ = bound(index_, 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                id,
                uint256(0),
                index_,
                uint256(1)
            )
        );
        vm.prank(caller_);
        _timelock.getQueuedConfigState(id, 0, index_);
    }

    // Scenarios: BLCT-QUEUED-ACTION-I01.
    function test_givenPendingAction_whenPayloadIndexOutOfBounds_reverts(
        address caller_,
        uint256 index_
    ) public {
        uint64 id = _queue(_capAction(address(_asset), 200000e9));
        index_ = bound(index_, 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                id,
                index_,
                uint256(1)
            )
        );
        vm.prank(caller_);
        _timelock.getQueuedSubAction(id, index_);
    }

    // Scenarios: BLCT-QUEUED-STATE-P03.
    function test_givenSTATEP03IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPendingAction_whenStateIndexOutOfBounds_reverts(address(0xabc1), uint256(1));
        _restore(checkpoint);
        test_givenPendingAction_whenStateIndexOutOfBounds_reverts(
            address(0xabc1),
            type(uint256).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLCT-QUEUED-ACTION-I01.
    function test_givenACTIONI01IndexEndpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPendingAction_whenPayloadIndexOutOfBounds_reverts(address(0xabc1), uint256(1));
        _restore(checkpoint);
        test_givenPendingAction_whenPayloadIndexOutOfBounds_reverts(
            address(0xabc1),
            type(uint256).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQB-N03.
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

    // Scenarios: BLQB-N04.
    function test_givenRawAbiN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNoncanonicalBool_whenOriginationsQueued_reverts(
            address(0xabc1),
            uint8(1),
            uint256(2)
        );
        _restore(checkpoint);
        test_givenNoncanonicalBool_whenOriginationsQueued_reverts(
            address(0xabc1),
            uint8(1),
            type(uint256).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQB-P07.
    function test_givenRawAbiP07Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNoncanonicalBool_whenWithdrawalQueued_reverts(
            address(0xabc1),
            uint8(1),
            uint256(2)
        );
        _restore(checkpoint);
        test_givenNoncanonicalBool_whenWithdrawalQueued_reverts(
            address(0xabc1),
            uint8(1),
            type(uint256).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQB-P08.
    function test_givenRawAbiP08Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenDirtyAddressWord_whenQueued_reverts(address(0xabc1), uint8(1), uint256(1));
        _restore(checkpoint);
        test_givenDirtyAddressWord_whenQueued_reverts(
            address(0xabc1),
            uint8(1),
            uint256(type(uint96).max)
        );
        _restore(checkpoint);
    }

    function _queue(ITimelockBatchQueue.BatchAction memory a_) internal returns (uint64) {
        return _timelock.queueBatch(_single(a_));
    }

    function _rejectWideField(
        ITimelockBatchQueue.BatchAction memory a_,
        uint256 word_,
        uint256 width_,
        address caller_
    ) internal {
        bytes memory payload = bytes.concat(a_.payload);
        uint256 value = uint256(1) << width_;
        assembly ("memory-safe") {
            mstore(add(add(payload, 32), mul(word_, 32)), value)
        }
        a_.payload = payload;
        _expectRejectedQueue(_invalid(a_));
        vm.prank(caller_);
        _queue(a_);
        _assertRejectedQueue(_single(a_));
    }

    // Scenarios: BLQB-L16.
    function test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_,
        bool enabled_
    ) public {
        _setState(_timelock, false, enabled_);
        vm.etch(address(_timelock.ROLES()), hex"fe");
        uint64 next = _timelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _timelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_timelock.nextActionId(), next, "Rejected local admission consumes no ID");
        assertEq(
            _timelock.getQueuedConfigStateCount(next, 0),
            0,
            "Rejected admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected local admission commits no logs");
    }

    // Scenarios: BLQB-L17.
    function test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts(
        address caller_
    ) public {
        _setState(_timelock, true, false);
        vm.etch(address(_timelock.ROLES()), hex"fe");
        uint64 next = _timelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _timelock.queueBatch(new ITimelockBatchQueue.BatchAction[](0));
        assertEq(_timelock.nextActionId(), next, "Disabled admission consumes no ID");
        assertEq(
            _timelock.getQueuedConfigStateCount(next, 0),
            0,
            "Disabled admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Disabled admission commits no logs");
    }

    // Scenarios: BLQB-A06.
    function test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts(
        address caller_
    ) public {
        _outsider(caller_);
        _setState(_config, false, true);
        uint64 next = _timelock.nextActionId();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        assertEq(_timelock.nextActionId(), next, "Unauthorized admission consumes no ID");
        assertEq(
            _timelock.getQueuedConfigStateCount(next, 0),
            0,
            "Unauthorized admission stores no payload"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Unauthorized admission commits no logs");
    }
}
