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

contract BurnerLoansConfigTimelockQueueSetAssetRiskConfigTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLQRC-A01.
    function test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts(
        address caller_
    ) public {
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-A02.
    function test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts(
        address caller_
    ) public {
        _config.disable("");
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-A03.
    function test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-A04.
    function test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        _config.disable("");
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-A05.
    function test_givenPermittedProposer_whenQueued_thenValidatedAndStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQRC-L01.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-L02.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-L03.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-L04.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-L05.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L06.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L07.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L08.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L09.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L10.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L11.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L12.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L13.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L14.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-L15.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
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

    // Scenarios: BLQRC-I01.
    function test_givenUnregisteredAsset_whenQueued_reverts(
        address caller_,
        uint8 role_,
        address unregistered_
    ) public {
        _proposer(caller_, role_);
        vm.assume(!_config.isAssetConfigured(unregistered_));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(unregistered_, _riskInput());
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

    // Scenarios: BLQRC-P03.
    function test_givenFreeKey_whenQueued_thenExactMetadata(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQRC-P04.
    function test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts(
        address caller_,
        uint8 role_,
        bool same_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        bytes32 original = _queueDigest(id);
        a.payload = abi.encode(
            address(_asset),
            same_ ? _riskInput() : _riskFields(_config.getAssetConfig(address(_asset)))
        );
        _expectRejectedQueue(_pending(a, id));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(_queueDigest(id), original, "Duplicate preserves original payload and owner");
    }

    // Scenarios: BLQRC-P05.
    function test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address other, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        ITimelockBatchQueue.BatchAction memory b = _riskAction(other, _riskInput());
        _independentActions(a, b, caller_);
    }

    // Scenarios: BLQRC-P06.
    function test_givenCommittedStateDrift_whenExecuted_reverts(address executor_) public {
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        uint64 id = _queue(a);
        bytes32 expected = _hash(a);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskFields(
            _config.getAssetConfig(address(_asset))
        );
        c.keeperRewardBps = 101;
        _config.setAssetRiskConfig(address(_asset), c);
        _makeReady(id);
        _executeReverts(id, executor_, _stateChanged(id, 0, a, expected));
    }

    // Scenarios: BLQRC-P07.
    function test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        uint64 id = _queue(a);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLQRC-P09.
    function test_givenCapPendingForSameAsset_whenRiskQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _capAction(address(_asset), 200000e9),
            _riskAction(address(_asset), _riskInput()),
            caller_
        );
    }

    // Scenarios: BLQRC-P10.
    function test_givenOriginationsPendingForSameAsset_whenRiskQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _originationsAction(address(_asset), false),
            _riskAction(address(_asset), _riskInput()),
            caller_
        );
    }

    // Scenarios: BLQRC-P11.
    function test_givenSharesPendingForSameAsset_whenRiskQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _sharesAction(address(_asset), false),
            _riskAction(address(_asset), _riskInput()),
            caller_
        );
    }

    // Scenarios: BLQRC-P12.
    function test_givenFeePendingForSameAsset_whenRiskQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _feeAction(address(_asset), _fees()),
            _riskAction(address(_asset), _riskInput()),
            caller_
        );
    }

    // Scenarios: BLQRC-N04.
    function test_givenValidOtherFields_whenZeroLtv_reverts(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.maxLtvBps = 0;
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(0))
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N05.
    function test_givenValidOtherFields_whenLtvAboveBps_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.maxLtvBps = uint16(bound(value_, 10001, type(uint16).max));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(c.maxLtvBps)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N06.
    function test_givenValidOtherFields_whenMultiplierBelowMinimum_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.backingMultiplierBps = uint16(bound(value_, 0, 9999));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N07.
    function test_givenValidOtherFields_whenMultiplierAboveMaximum_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.backingMultiplierBps = uint16(bound(value_, 50001, type(uint16).max));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N08.
    function test_givenValidOtherFields_whenKeeperBpsAboveMaximum_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.keeperRewardBps = uint16(bound(value_, 10001, type(uint16).max));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(c.keeperRewardBps)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N09.
    function test_givenValidOtherFields_whenZeroTerm_reverts(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.termLength = 0;
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N10.
    function test_givenValidOtherFields_whenTermAboveMaximum_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.termLength = uint48(bound(value_, 365 days + 1, type(uint48).max));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N11.
    function test_givenValidOtherFields_whenHorizonNotAfterTerm_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.maxMaturityHorizon = uint48(bound(value_, 0, c.termLength));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-N12.
    function test_givenValidOtherFields_whenHorizonAboveMaximum_reverts(
        address caller_,
        uint8 role_,
        uint256 value_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.maxMaturityHorizon = uint48(bound(value_, 366 days + 1, type(uint48).max));
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLQRC-P02.
    function test_givenCompleteStruct_whenQueued_thenExactValues(
        address caller_,
        uint8 role_,
        IBurnerLoansRisk.AssetRiskConfigInput memory c
    ) public {
        _proposer(caller_, role_);
        c.maxLtvBps = uint16(bound(c.maxLtvBps, 1, 10000));
        c.backingMultiplierBps = uint16(bound(c.backingMultiplierBps, 10000, 50000));
        c.keeperRewardBps = uint16(bound(c.keeperRewardBps, 0, 10000));
        c.termLength = uint48(bound(c.termLength, 1, 365 days));
        c.maxMaturityHorizon = uint48(
            bound(c.maxMaturityHorizon, uint256(c.termLength) + 1, 366 days)
        );
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLQRC-N01.
    function test_givenCompleteStruct_whenExecuted_thenExactValues(
        address caller_,
        uint8 role_,
        IBurnerLoansRisk.AssetRiskConfigInput memory c
    ) public {
        _proposer(caller_, role_);
        c.maxLtvBps = uint16(bound(c.maxLtvBps, 1, 10000));
        c.backingMultiplierBps = uint16(bound(c.backingMultiplierBps, 10000, 50000));
        c.keeperRewardBps = uint16(bound(c.keeperRewardBps, 0, 10000));
        c.termLength = uint48(bound(c.termLength, 1, 365 days));
        c.maxMaturityHorizon = uint48(
            bound(c.maxMaturityHorizon, uint256(c.termLength) + 1, 366 days)
        );
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        _makeReady(id);
        _executeAndAssert(id, caller_);
    }

    // Scenarios: BLQRC-N02.
    function test_givenValidOtherFields_whenZeroReward_thenApplied(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.maxKeeperReward = 0;
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        _makeReady(id);
        _executeAndAssert(id, caller_);
    }

    // Scenarios: BLQRC-N03.
    function test_givenValidOtherFields_whenMaximumReward_thenApplied(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        IBurnerLoansRisk.AssetRiskConfigInput memory c = _riskInput();
        c.maxKeeperReward = type(uint128).max;
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), c);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        _makeReady(id);
        _executeAndAssert(id, caller_);
    }

    // Scenarios: BLQRC-P01.
    function test_givenUnchangedCompleteStruct_whenExecuted_thenNoTargetEvent(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _riskAction(
            address(_asset),
            _riskFields(_config.getAssetConfig(address(_asset)))
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

    // Scenarios: BLQRC-P08.
    function test_givenReplacementRiskRejectsProposal_whenExecuted_reverts(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), _riskInput());
        uint64 id = _queue(a);
        BurnerLoansRisk replacement = _replaceRisk(0);
        vm.mockCallRevert(
            address(replacement),
            abi.encodeCall(IBurnerLoansRisk.validateRiskConfig, (_riskInput())),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLQRC-A05.
    function test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 0);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 1);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 2);
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N05.
    function test_givenRiskConfigN05Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenLtvAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(10001)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenLtvAboveBps_reverts(
            address(0xabc1),
            uint8(1),
            uint256(65535)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N06.
    function test_givenRiskConfigN06Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenMultiplierBelowMinimum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(0)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenMultiplierBelowMinimum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(9999)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N07.
    function test_givenRiskConfigN07Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenMultiplierAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(50001)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenMultiplierAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(65535)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N08.
    function test_givenRiskConfigN08Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenKeeperBpsAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(10001)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenKeeperBpsAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(65535)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N10.
    function test_givenRiskConfigN10Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenTermAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(31536001)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenTermAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(281474976710655)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N11.
    function test_givenRiskConfigN11Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenHorizonNotAfterTerm_reverts(
            address(0xabc1),
            uint8(1),
            uint256(0)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenHorizonNotAfterTerm_reverts(
            address(0xabc1),
            uint8(1),
            uint256(1209600)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N12.
    function test_givenRiskConfigN12Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidOtherFields_whenHorizonAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(31622401)
        );
        _restore(checkpoint);
        test_givenValidOtherFields_whenHorizonAboveMaximum_reverts(
            address(0xabc1),
            uint8(1),
            uint256(281474976710655)
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-P02.
    function test_givenRiskConfigP02CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetRiskConfigInput(1, 10000, 0, 1, 2, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetRiskConfigInput(1, 10000, 1, 1, 2, 1)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenQueued_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetRiskConfigInput(
                10000,
                50000,
                10000,
                365 days,
                366 days,
                type(uint128).max
            )
        );
        _restore(checkpoint);
    }

    // Scenarios: BLQRC-N01.
    function test_givenRiskConfigN01CompleteStructs_whenBoundarySeedsRun_thenScenarioHolds()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetRiskConfigInput(1, 10000, 0, 1, 2, 0)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetRiskConfigInput(1, 10000, 1, 1, 2, 1)
        );
        _restore(checkpoint);
        test_givenCompleteStruct_whenExecuted_thenExactValues(
            address(0xabc1),
            uint8(1),
            IBurnerLoansRisk.AssetRiskConfigInput(
                10000,
                50000,
                10000,
                365 days,
                366 days,
                type(uint128).max
            )
        );
        _restore(checkpoint);
    }

    function _queue(ITimelockBatchQueue.BatchAction memory a_) internal returns (uint64) {
        (address asset, IBurnerLoansRisk.AssetRiskConfigInput memory c) = abi.decode(
            a_.payload,
            (address, IBurnerLoansRisk.AssetRiskConfigInput)
        );
        return _timelock.queueSetAssetRiskConfig(asset, c);
    }
}
