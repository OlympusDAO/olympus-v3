// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";

contract BurnerLoansConfigTimelockQueueSetAssetFeeConfigTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLQFC-A01.
    function test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts(
        address caller_
    ) public {
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-A02.
    function test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts(
        address caller_
    ) public {
        _config.disable("");
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-A03.
    function test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-A04.
    function test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        _config.disable("");
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-A05.
    function test_givenPermittedProposer_whenQueued_thenValidatedAndStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQFC-L01.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-L02.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-L03.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-L04.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-L05.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L06.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L07.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L08.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L09.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L10.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L11.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L12.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L13.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L14.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-L15.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
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

    // Scenarios: BLQFC-I01.
    function test_givenUnregisteredAsset_whenQueued_reverts(
        address caller_,
        uint8 role_,
        address unregistered_
    ) public {
        _proposer(caller_, role_);
        vm.assume(!_config.isAssetConfigured(unregistered_));
        ITimelockBatchQueue.BatchAction memory a = _feeAction(unregistered_, _fees());
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                unregistered_
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-P03.
    function test_givenFreeKey_whenQueued_thenExactMetadata(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQFC-P04.
    function test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts(
        address caller_,
        uint8 role_,
        bool same_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        bytes32 original = _queueDigest(id);
        a.payload = abi.encode(
            address(_asset),
            same_ ? _fees() : _config.getAssetFeeConfig(address(_asset))
        );
        _expectRejectedQueue(_pending(a, id));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(_queueDigest(id), original, "Duplicate preserves original payload and owner");
    }

    // Scenarios: BLQFC-P05.
    function test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address other, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        ITimelockBatchQueue.BatchAction memory b = _feeAction(other, _fees());
        _independentActions(a, b, caller_);
    }

    // Scenarios: BLQFC-P06.
    function test_givenCommittedStateDrift_whenExecuted_reverts(address executor_) public {
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        uint64 id = _queue(a);
        bytes32 expected = _hash(a);
        IBurnerLoansRisk.AssetFeeConfig memory c = _config.getAssetFeeConfig(address(_asset));
        c.postKinkSlopeBps = 901;
        _config.setAssetFeeConfig(address(_asset), c);
        _makeReady(id);
        _executeReverts(id, executor_, _stateChanged(id, 0, a, expected));
    }

    // Scenarios: BLQFC-P07.
    function test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        uint64 id = _queue(a);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLQFC-P09.
    function test_givenCapPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _capAction(address(_asset), 200000e9),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQFC-P10.
    function test_givenOriginationsPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _originationsAction(address(_asset), false),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQFC-P11.
    function test_givenRiskPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _riskAction(address(_asset), _riskInput()),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQFC-P12.
    function test_givenSharesPendingForSameAsset_whenFeeQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _sharesAction(address(_asset), false),
            _feeAction(address(_asset), _fees()),
            caller_
        );
    }

    // Scenarios: BLQFC-I02.
    function test_givenValidOtherFields_whenZeroKinkWithPreSlope_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c.kinkBps = 0;
        c.preKinkSlopeBps = 1;
        c.postKinkSlopeBps = 0;
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-I03.
    function test_givenValidOtherFields_whenZeroKinkWithPostSlope_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c.kinkBps = 0;
        c.preKinkSlopeBps = 0;
        c.postKinkSlopeBps = 1;
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-I04.
    function test_givenValidOtherFields_whenFeeSumAboveBps_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c.baseFeeBps = 10000;
        c.preKinkSlopeBps = 1;
        c.postKinkSlopeBps = 0;
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-N03.
    function test_givenValidOtherFields_whenBaseFeeAboveBps_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c.baseFeeBps = uint16(bound(value_, 10001, type(uint16).max));
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(c.baseFeeBps)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-N04.
    function test_givenValidOtherFields_whenPreSlopeAboveBps_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c.preKinkSlopeBps = uint16(bound(value_, 10001, type(uint16).max));
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(c.preKinkSlopeBps)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-N05.
    function test_givenValidOtherFields_whenPostSlopeAboveBps_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c.postKinkSlopeBps = uint16(bound(value_, 10001, type(uint16).max));
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(c.postKinkSlopeBps)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-N06.
    function test_givenValidOtherFields_whenKinkAtOrAboveBps_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c.kinkBps = uint16(bound(value_, 10000, type(uint16).max));
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQFC-P02.
    function test_givenCompleteStruct_whenQueued_thenExactValues(
        address caller_,
        uint8 role_,
        IBurnerLoansRisk.AssetFeeConfig memory c
    ) public {
        _proposer(caller_, role_);
        c.baseFeeBps = uint16(bound(c.baseFeeBps, 0, 10000));
        c.preKinkSlopeBps = uint16(bound(c.preKinkSlopeBps, 0, 10000 - c.baseFeeBps));
        c.postKinkSlopeBps = uint16(
            bound(c.postKinkSlopeBps, 0, 10000 - c.baseFeeBps - c.preKinkSlopeBps)
        );
        c.kinkBps = uint16(bound(c.kinkBps, 1, 9999));
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQFC-N02.
    function test_givenCompleteStruct_whenExecuted_thenExactValues(
        address caller_,
        uint8 role_,
        IBurnerLoansRisk.AssetFeeConfig memory c
    ) public {
        _proposer(caller_, role_);
        c.baseFeeBps = uint16(bound(c.baseFeeBps, 0, 10000));
        c.preKinkSlopeBps = uint16(bound(c.preKinkSlopeBps, 0, 10000 - c.baseFeeBps));
        c.postKinkSlopeBps = uint16(
            bound(c.postKinkSlopeBps, 0, 10000 - c.baseFeeBps - c.preKinkSlopeBps)
        );
        c.kinkBps = uint16(bound(c.kinkBps, 1, 9999));
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        _makeReady(id);
        _executeAndAssert(id, caller_);
    }

    // Scenarios: BLQFC-N01.
    function test_givenZeroFeeCurve_whenExecuted_thenAllFieldsZero(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetFeeConfig memory c = _fees();
        c = IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0);
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), c);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        _makeReady(id);
        _executeAndAssert(id, caller_);
    }

    // Scenarios: BLQFC-P01.
    function test_givenUnchangedCompleteStruct_whenExecuted_thenNoTargetEvent(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _feeAction(
            address(_asset),
            _config.getAssetFeeConfig(address(_asset))
        );
        uint64 id = _queue(a);
        _makeReady(id);
        vm.recordLogs();
        vm.record();
        _executeAndAssert(id, executor_);
        _assertNoTargetLogs(vm.getRecordedLogs(), address(_config));
        _assertNoTargetWrites(address(_config));
        _assertNoTargetWrites(address(_floan));
        _assertNoTargetWrites(address(_core));
    }

    // Scenarios: BLQFC-P08.
    function test_givenReplacementRiskRejectsProposal_whenExecuted_reverts(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), _fees());
        uint64 id = _queue(a);
        BurnerLoansRisk replacement = _replaceRisk(0);
        vm.mockCallRevert(
            address(replacement),
            abi.encodeCall(IBurnerLoansRisk.validateFeeConfig, (_fees())),
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLQFC-A05.
    function test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 0);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 1);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 2);
        _restore(checkpoint);
    }

    // Scenarios: BLQFC-N03.
    function test_givenFeeConfigN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenBaseFeeAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(10001)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenBaseFeeAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(65535)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQFC-N04.
    function test_givenFeeConfigN04Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenPreSlopeAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(10001)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenPreSlopeAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(65535)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQFC-N05.
    function test_givenFeeConfigN05Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenPostSlopeAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(10001)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenPostSlopeAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(65535)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQFC-N06.
    function test_givenFeeConfigN06Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenKinkAtOrAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(10000)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenKinkAtOrAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(65535)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQFC-P02.
    function test_givenFeeConfigP02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 0, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(1, 9999, 0, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 1, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 0, 1)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 9999, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 9999, 0, 10000)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(10000, 1, 0, 0)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQFC-N02.
    function test_givenFeeConfigN02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 0, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(1, 9999, 0, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 1, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 0, 1)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 9999, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(0, 9999, 0, 10000)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetFeeConfig(10000, 1, 0, 0)
        );
        _restore(checkpoint);
    }

    function _queue(ITimelockBatchQueue.BatchAction memory a_) internal returns (uint64) {
        (address asset, IBurnerLoansRisk.AssetFeeConfig memory c) = abi.decode(
            a_.payload,
            (address, IBurnerLoansRisk.AssetFeeConfig)
        );
        return _timelock.queueSetAssetFeeConfig(asset, c);
    }
}
