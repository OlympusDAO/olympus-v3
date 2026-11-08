// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {TimelockCallbackTarget} from "./fixtures/TimelockCallbackTarget.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";

contract BurnerLoansConfigTimelockExecuteQueuedActionTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-EXECUTE-L01.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, false);
        _setState(_timelock, true, true);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L02.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, true);
        _setState(_timelock, true, true);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L03.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, false);
        _setState(_timelock, true, true);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L04.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, true);
        _setState(_timelock, true, false);
        _executeReverts(id, caller_, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLCT-EXECUTE-L05.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, false);
        _setState(_timelock, true, false);
        _executeReverts(id, caller_, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLCT-EXECUTE-L06.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, true);
        _setState(_timelock, true, false);
        _executeReverts(id, caller_, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLCT-EXECUTE-L07.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, false);
        _setState(_timelock, true, false);
        _executeReverts(id, caller_, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLCT-EXECUTE-L08.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, true);
        _setState(_timelock, false, true);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L09.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, false);
        _setState(_timelock, false, true);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L10.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, true);
        _setState(_timelock, false, true);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L11.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, false);
        _setState(_timelock, false, true);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L12.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, true);
        _setState(_timelock, false, false);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L13.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, false);
        _setState(_timelock, false, false);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L14.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, true);
        _setState(_timelock, false, false);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-L15.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenExecute_reverts(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, false, false);
        _setState(_timelock, false, false);
        _executeReverts(
            id,
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-I01.
    function test_givenMissingZeroId_whenExecute_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(0)
            )
        );
        vm.prank(caller_);
        _timelock.executeQueuedAction(uint64(0));
    }

    // Scenarios: BLCT-EXECUTE-N01.
    function test_givenMissingNonzeroId_whenExecute_reverts(address caller_, uint64 id_) public {
        id_ = uint64(bound(id_, 1, type(uint64).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        vm.prank(caller_);
        _timelock.executeQueuedAction(id_);
    }

    // Scenarios: BLCT-EXECUTE-A01.
    function test_givenReadyAction_whenExecute_thenComplete(address caller_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _executeAndAssert(id, caller_);
    }

    // Scenarios: BLCT-EXECUTE-P01.
    function test_givenCancelled_whenExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _timelock.cancelQueuedAction(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-P04.
    function test_givenExecuted_whenExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _executeAndAssert(id, address(this));
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-P05.
    function test_givenOneSecondBeforeReady_whenExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        vm.warp(uint256(_timelock.getQueuedAction(id).executableAt) - 1);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                id,
                _timelock.getQueuedAction(id).executableAt
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-P08.
    function test_givenOneSecondAfterExpiry_whenExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        vm.warp(uint256(_timelock.getQueuedAction(id).expiresAt) + 1);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                _timelock.getQueuedAction(id).expiresAt
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-P06.
    function test_givenExactReadyTime_whenExecuted_thenInclusiveSuccess(address executor_) public {
        uint64 id = _timelock.queueBatch(
            _pair(_capAction(address(_asset), 200000e9), _feeAction(address(_asset), _fees()))
        );
        vm.warp(_timelock.getQueuedAction(id).executableAt);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLCT-EXECUTE-P07.
    function test_givenExactExpiryTime_whenExecuted_thenInclusiveSuccess(address executor_) public {
        uint64 id = _timelock.queueBatch(
            _pair(_capAction(address(_asset), 200000e9), _feeAction(address(_asset), _fees()))
        );
        vm.warp(_timelock.getQueuedAction(id).expiresAt);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLCT-EXECUTE-P02.
    function test_givenUnchangedProposedRiskFieldDrifts_whenExecuted_reverts(
        address executor_
    ) public {
        IBurnerLoansRisk.AssetRiskConfigInput memory proposal = _riskFields(
            _config.getAssetConfig(address(_asset))
        );
        proposal.maxLtvBps = 7500;
        ITimelockBatchQueue.BatchAction memory a = _riskAction(address(_asset), proposal);
        uint64 id = _timelock.queueBatch(_single(a));
        bytes32 expected = _hash(a);
        IBurnerLoansRisk.AssetRiskConfigInput memory live = _riskFields(
            _config.getAssetConfig(address(_asset))
        );
        live.maxKeeperReward += 1;
        _config.setAssetRiskConfig(address(_asset), live);
        _makeReady(id);
        _executeReverts(id, executor_, _stateChanged(id, 0, a, expected));
    }

    // Scenarios: BLCT-EXECUTE-P03.
    function test_givenUnchangedProposedFeeFieldDrifts_whenExecuted_reverts(
        address executor_
    ) public {
        IBurnerLoansRisk.AssetFeeConfig memory proposal = _config.getAssetFeeConfig(
            address(_asset)
        );
        proposal.baseFeeBps = 100;
        ITimelockBatchQueue.BatchAction memory a = _feeAction(address(_asset), proposal);
        uint64 id = _timelock.queueBatch(_single(a));
        bytes32 expected = _hash(a);
        IBurnerLoansRisk.AssetFeeConfig memory live = _config.getAssetFeeConfig(address(_asset));
        live.postKinkSlopeBps += 1;
        _config.setAssetFeeConfig(address(_asset), live);
        _makeReady(id);
        _executeReverts(id, executor_, _stateChanged(id, 0, a, expected));
    }

    // Scenarios: BLCT-EXECUTE-I02.
    function test_givenDebtGrowsAboveQueuedCap_whenExecuted_thenEarlierWriteRollsBack(
        address executor_
    ) public {
        uint64 id = _timelock.queueBatch(
            _pair(_feeAction(address(_asset), _fees()), _capAction(address(_asset), 50e9))
        );
        _openDebt();
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
    }

    // Scenarios: BLCT-EXECUTE-P09.
    function test_givenEmptyTargetRevert_whenExecuted_thenBoundedWrapper(address executor_) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _timelock.queueBatch(_pair(_feeAction(address(_asset), _fees()), a));
        _makeReady(id);
        bytes memory injected = new bytes(0);
        vm.mockCallRevert(address(_config), abi.encodePacked(a.selector, a.payload), injected);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_SubActionCallFailed.selector,
                a.target,
                a.selector
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-P10.
    function test_givenBoundedTargetRevert_whenExecuted_thenExactBubble(
        address executor_,
        uint256 length_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _timelock.queueBatch(_pair(_feeAction(address(_asset), _fees()), a));
        _makeReady(id);
        bytes memory injected = new bytes(bound(length_, 1, 255));
        vm.mockCallRevert(address(_config), abi.encodePacked(a.selector, a.payload), injected);
        _executeReverts(id, executor_, injected);
    }

    // Scenarios: BLCT-EXECUTE-P11.
    function test_givenExactlyLimitTargetRevert_whenExecuted_thenBoundedWrapper(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _timelock.queueBatch(_pair(_feeAction(address(_asset), _fees()), a));
        _makeReady(id);
        bytes memory injected = new bytes(256);
        vm.mockCallRevert(address(_config), abi.encodePacked(a.selector, a.payload), injected);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_SubActionCallFailed.selector,
                a.target,
                a.selector
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-P12.
    function test_givenOversizedTargetRevert_whenExecuted_thenBoundedWrapper(
        address executor_,
        uint256 length_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _timelock.queueBatch(_pair(_feeAction(address(_asset), _fees()), a));
        _makeReady(id);
        bytes memory injected = new bytes(bound(length_, 257, 65536));
        vm.mockCallRevert(address(_config), abi.encodePacked(a.selector, a.payload), injected);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_SubActionCallFailed.selector,
                a.target,
                a.selector
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-C01.
    function test_givenTargetCatchesSameActionCallback_whenExecuted_thenOneExecution(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _timelock.queueBatch(_single(a));
        _installCallback(id, true);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLCT-EXECUTE-C02.
    function test_givenTargetPropagatesSameActionCallback_whenExecuted_thenRollback(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _timelock.queueBatch(_pair(_feeAction(address(_asset), _fees()), a));
        _installCallback(id, false);
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-P14.
    function test_givenIndependentConfigDomains_whenExecuted_thenBothOrdersApply(
        address executor_
    ) public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 order; order < 2; ++order) {
            ITimelockBatchQueue.BatchAction[] memory batch = order == 0
                ? _pair(_feeAction(address(_asset), _fees()), _capAction(address(_asset), 200000e9))
                : _pair(
                    _capAction(address(_asset), 200000e9),
                    _feeAction(address(_asset), _fees())
                );
            uint64 id = _timelock.queueBatch(batch);
            _makeReady(id);
            _executeAndAssert(id, executor_);
            assertTrue(vm.revertToState(checkpoint), "Restore execution order");
        }
    }

    // Scenarios: BLCT-EXECUTE-T01.
    function test_givenLaterConfigSetterReverts_whenExecuted_thenAtomicRollback(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory configAction = _feeAction(address(_asset), _fees());
        ITimelockBatchQueue.BatchAction memory riskAction = _capAction(address(_asset), 200000e9);
        uint256 checkpoint = vm.snapshotState();
        for (uint256 order; order < 2; ++order) {
            ITimelockBatchQueue.BatchAction[] memory batch = order == 0
                ? _pair(configAction, riskAction)
                : _pair(riskAction, configAction);
            uint64 id = _timelock.queueBatch(batch);
            _makeReady(id);
            vm.mockCallRevert(
                batch[1].target,
                abi.encodePacked(batch[1].selector, batch[1].payload),
                hex"deadbeef"
            );
            _executeReverts(id, executor_, hex"deadbeef");
            assertTrue(vm.revertToState(checkpoint), "Restore independent failure order");
            vm.clearMockedCalls();
        }
    }

    // Scenarios: BLCT-EXECUTE-D08.
    function test_givenRiskOperatorIndependent_whenConfigExecuted_thenApplied(
        address executor_,
        bool zero_
    ) public {
        uint64 id = _timelock.queueBatch(
            _pair(_riskAction(address(_asset), _riskInput()), _feeAction(address(_asset), _fees()))
        );
        _risk.setConfigOperator(zero_ ? address(0) : _recipient);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLCT-EXECUTE-D09.
    function test_givenConfigOperatorRevoked_whenIndependentBatchExecuted_reverts(
        address executor_
    ) public {
        uint64 id = _timelock.queueBatch(
            _pair(_feeAction(address(_asset), _fees()), _capAction(address(_asset), 200000e9))
        );
        _config.setConfigOperator(_recipient);
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-D10.
    function test_givenConfigOperatorRestored_whenOriginalBatchExecuted_thenApplied(
        address executor_,
        uint48 elapsed_
    ) public {
        uint64 id = _timelock.queueBatch(
            _pair(_feeAction(address(_asset), _fees()), _capAction(address(_asset), 200000e9))
        );
        ITimelockBatchQueue.QueuedAction memory original = _timelock.getQueuedAction(id);
        bytes32 commitment = _queueDigest(id);
        _config.setConfigOperator(_recipient);
        vm.warp(bound(elapsed_, original.executableAt, original.expiresAt));
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(_timelock)
            )
        );
        assertEq(
            _queueDigest(id),
            commitment,
            "Lost authority preserves original intent and deadlines"
        );
        _config.setConfigOperator(address(_timelock));
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLCT-EXECUTE-D11.
    function test_givenConfigOperatorReadReverts_whenExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        vm.mockCallRevert(
            address(_config),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-D11.
    function test_givenMalformedConfigOperatorLength_whenExecuted_reverts(
        address executor_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 32);
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        vm.mockCall(address(_config), abi.encodeWithSignature("configOperator()"), data_);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-EXECUTE-D11.
    function test_givenNoncanonicalConfigOperator_whenExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(type(uint256).max)
        );
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock
                    .BurnerLoansConfigTimelock_InvalidBurnerLoansConfig
                    .selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-QUEUED-ACTION-N01.
    function test_givenMissingId_whenMetadataRead_reverts(address caller_, uint64 id_) public {
        for (uint256 i; i < 3; ++i) {
            uint64 id = i == 0 ? 0 : i == 1 ? type(uint64).max : id_;
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                    id
                )
            );
            vm.prank(caller_);
            _timelock.getQueuedAction(id);
        }
    }

    // Scenarios: BLCT-QUEUED-ACTION-P01.
    function test_givenEachEstablishedActionState_whenMetadataRead_thenFlagsAndPayloadsAgree(
        address caller_
    ) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        ITimelockBatchQueue.QueuedAction memory original = _timelock.getQueuedAction(id);
        uint256 checkpoint = vm.snapshotState();
        _makeReady(id);
        _executeAndAssert(id, caller_);
        _assertMetadata(id, original, true, false, caller_);
        assertTrue(vm.revertToState(checkpoint), "Restore pending metadata");
        _timelock.cancelQueuedAction(id);
        _assertMetadata(id, original, false, true, caller_);
        assertTrue(vm.revertToState(checkpoint), "Restore expired metadata");
        vm.warp(uint256(original.expiresAt) + 1);
        _assertMetadata(id, original, false, false, caller_);
        assertEq(
            _timelock.pendingActionId(_key(_capAction(address(_asset), 200000e9))),
            id,
            "Expiry keeps pending key"
        );
    }

    // Scenarios: BLCT-QUEUED-ACTION-P02.
    function test_givenExecutedAction_whenPayloadRead_reverts(address caller_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _executeAndAssert(id, caller_);
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
            id
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.getQueuedActionLength(id);
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.getQueuedSubAction(id, 0);
    }

    // Scenarios: BLCT-QUEUED-ACTION-I02.
    function test_givenCancelledAction_whenPayloadRead_reverts(address caller_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _timelock.cancelQueuedAction(id);
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
            id
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.getQueuedActionLength(id);
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.getQueuedSubAction(id, 0);
    }

    // Scenarios: BLCT-EXECUTE-P10.
    function test_givenRevertDataP10Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenBoundedTargetRevert_whenExecuted_thenExactBubble(address(0xabc1), uint256(1));
        _restore(checkpoint);
        test_givenBoundedTargetRevert_whenExecuted_thenExactBubble(address(0xabc1), uint256(255));
        _restore(checkpoint);
    }

    // Scenarios: BLCT-EXECUTE-P12.
    function test_givenRevertDataP12Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenOversizedTargetRevert_whenExecuted_thenBoundedWrapper(
            address(0xabc1),
            uint256(257)
        );
        _restore(checkpoint);
        test_givenOversizedTargetRevert_whenExecuted_thenBoundedWrapper(
            address(0xabc1),
            uint256(65536)
        );
        _restore(checkpoint);
    }

    function _installCallback(uint64 id_, bool catches_) internal {
        address original = makeAddr("originalConfigCode");
        vm.etch(original, address(_config).code);
        TimelockCallbackTarget target = new TimelockCallbackTarget(
            original,
            address(_timelock),
            id_,
            catches_
        );
        vm.etch(address(_config), address(target).code);
    }

    function _assertMetadata(
        uint64 id_,
        ITimelockBatchQueue.QueuedAction memory original_,
        bool executed_,
        bool cancelled_,
        address caller_
    ) internal {
        vm.prank(caller_);
        ITimelockBatchQueue.QueuedAction memory current = _timelock.getQueuedAction(id_);
        assertEq(current.proposer, original_.proposer, "Metadata proposer retained");
        assertEq(current.queuedAt, original_.queuedAt, "Queue timestamp retained");
        assertEq(current.executableAt, original_.executableAt, "Ready time retained");
        assertEq(current.expiresAt, original_.expiresAt, "Expiry retained");
        assertEq(current.executed, executed_, "Exact executed flag");
        assertEq(current.cancelled, cancelled_, "Exact cancelled flag");
        assertEq(
            current.actions.length,
            executed_ || cancelled_ ? 0 : original_.actions.length,
            "Only terminal resolution clears payload"
        );
    }

    // Scenarios: BLCT-EXECUTE-P15.
    function test_whenCompleteFeeConfigIsQueued_thenAllFieldsApplyAfterDelay() public {
        IBurnerLoansRisk.AssetFeeConfig memory proposed = IBurnerLoansRisk.AssetFeeConfig(
            10,
            7000,
            20,
            30
        );
        uint64 id = _timelock.queueSetAssetFeeConfig(address(_asset), proposed);
        assertEq(
            _config.getAssetFeeConfig(address(_asset)).baseFeeBps,
            25,
            "Queue cannot mutate current fees"
        );
        vm.warp(block.timestamp + 1 days);
        vm.prank(_recipient);
        _timelock.executeQueuedAction(id);
        IBurnerLoansRisk.AssetFeeConfig memory actual = _config.getAssetFeeConfig(address(_asset));
        assertEq(
            keccak256(abi.encode(actual)),
            keccak256(abi.encode(proposed)),
            "Complete queued struct applies exactly"
        );
    }

    // Scenarios: BLCT-EXECUTE-N02.
    function test_whenCompleteRiskConfigIsQueued_thenMaximumKeeperRewardIsPreserved() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory proposed = IBurnerLoansRisk
            .AssetRiskConfigInput(8000, 13000, 25, 20 days, 80 days, type(uint128).max);
        uint64 id = _timelock.queueSetAssetRiskConfig(address(_asset), proposed);
        vm.warp(block.timestamp + 1 days);
        _timelock.executeQueuedAction(id);
        assertEq(
            _config.getAssetConfig(address(_asset)).maxKeeperReward,
            type(uint128).max,
            "uint128 reward must not be truncated"
        );
    }

    // Scenarios: BLCT-EXECUTE-D12.
    function test_givenForeignKernelAndPausedConfig_whenExecuted_reverts(address executor_) public {
        uint64 id = _timelock.queueBatch(_single(_capAction(address(_asset), 200000e9)));
        _makeReady(id);
        _setState(_config, true, false);
        address foreignKernel = makeAddr("foreignKernel");
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("kernel()"),
            abi.encode(foreignKernel)
        );

        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_config),
                address(_kernel),
                foreignKernel
            )
        );
    }
}
