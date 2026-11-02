// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetAssetDebtCapTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-QUEUE-CAP-A01.
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

    // Scenarios: BLCT-QUEUE-CAP-A02.
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

    // Scenarios: BLCT-QUEUE-CAP-A03.
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

    // Scenarios: BLCT-QUEUE-CAP-A04.
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

    // Scenarios: BLCT-QUEUE-CAP-A05.
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

    // Scenarios: BLCT-QUEUE-CAP-L01.
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

    // Scenarios: BLCT-QUEUE-CAP-L02.
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

    // Scenarios: BLCT-QUEUE-CAP-L03.
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

    // Scenarios: BLCT-QUEUE-CAP-L04.
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

    // Scenarios: BLCT-QUEUE-CAP-L05.
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

    // Scenarios: BLCT-QUEUE-CAP-L06.
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

    // Scenarios: BLCT-QUEUE-CAP-L07.
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

    // Scenarios: BLCT-QUEUE-CAP-L08.
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

    // Scenarios: BLCT-QUEUE-CAP-L09.
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

    // Scenarios: BLCT-QUEUE-CAP-L10.
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

    // Scenarios: BLCT-QUEUE-CAP-L11.
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

    // Scenarios: BLCT-QUEUE-CAP-L12.
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

    // Scenarios: BLCT-QUEUE-CAP-L13.
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

    // Scenarios: BLCT-QUEUE-CAP-L14.
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

    // Scenarios: BLCT-QUEUE-CAP-L15.
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

    // Scenarios: BLCT-QUEUE-CAP-I01.
    function test_givenUnregisteredAsset_whenQueued_reverts(
        address caller_,
        uint8 role_,
        address unregistered_
    ) public {
        _proposer(caller_, role_);
        vm.assume(!_config.isAssetConfigured(unregistered_));
        ITimelockBatchQueue.BatchAction memory a = _capAction(unregistered_, 200000e9);
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

    // Scenarios: BLCT-QUEUE-CAP-P01.
    function test_givenFreeKey_whenQueued_thenExactMetadata(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CAP-P02.
    function test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts(
        address caller_,
        uint8 role_,
        bool same_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
        bytes32 original = _queueDigest(id);
        a.payload = abi.encode(address(_asset), same_ ? uint128(200000e9) : uint128(300000e9));
        _expectRejectedQueue(_pending(a, id));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
        assertEq(_queueDigest(id), original, "Duplicate preserves original payload and owner");
    }

    // Scenarios: BLCT-QUEUE-CAP-P03.
    function test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address other, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        ITimelockBatchQueue.BatchAction memory b = _capAction(other, 200000e9);
        _independentActions(a, b, caller_);
    }

    // Scenarios: BLCT-QUEUE-CAP-P04.
    function test_givenCommittedStateDrift_whenExecuted_reverts(address executor_) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _queue(a);
        bytes32 expected = _hash(a);
        _config.setAssetDebtCap(address(_asset), 90000e9);
        _makeReady(id);
        _executeReverts(id, executor_, _stateChanged(id, 0, a, expected));
    }

    // Scenarios: BLCT-QUEUE-CAP-P05.
    function test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 200000e9);
        uint64 id = _queue(a);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLCT-QUEUE-CAP-P07.
    function test_givenOriginationsPendingForSameAsset_whenCapQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _originationsAction(address(_asset), false),
            _capAction(address(_asset), 200000e9),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-CAP-P08.
    function test_givenRiskPendingForSameAsset_whenCapQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _riskAction(address(_asset), _riskInput()),
            _capAction(address(_asset), 200000e9),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-CAP-P09.
    function test_givenSharesPendingForSameAsset_whenCapQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _sharesAction(address(_asset), false),
            _capAction(address(_asset), 200000e9),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-CAP-P10.
    function test_givenFeePendingForSameAsset_whenCapQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _feeAction(address(_asset), _fees()),
            _capAction(address(_asset), 200000e9),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-CAP-N01.
    function test_givenLiveDebt_whenCapBelowDebt_reverts(
        address caller_,
        uint8 role_,
        uint128 cap_
    ) public {
        _proposer(caller_, role_);
        _openDebt();
        cap_ = uint128(bound(cap_, 0, 100e9 - 1));
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), cap_);
        _expectRejectedQueue(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-CAP-N02.
    function test_givenDebtBoundary_whenCapEqualsDebt_thenAccepted(
        address caller_,
        uint8 role_,
        uint128 debt_
    ) public {
        _proposer(caller_, role_);
        _mockDebt(debt_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), debt_);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CAP-N03.
    function test_givenLiveDebt_whenCapAboveDebt_thenAccepted(
        address caller_,
        uint8 role_,
        uint128 debt_,
        uint128 cap_
    ) public {
        _proposer(caller_, role_);
        debt_ = uint128(bound(debt_, 0, type(uint128).max - 1));
        cap_ = uint128(bound(cap_, uint256(debt_) + 1, type(uint128).max));
        _mockDebt(debt_);
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), cap_);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-CAP-P06.
    function test_givenDebtGrowsAfterQueue_whenExecuted_reverts(address executor_) public {
        ITimelockBatchQueue.BatchAction memory a = _capAction(address(_asset), 50e9);
        uint64 id = _queue(a);
        _openDebt();
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
    }

    // Scenarios: BLCT-QUEUE-CAP-A05.
    function test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 0);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 1);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 2);
        _restore(checkpoint);
    }

    // Scenarios: BLCT-QUEUE-CAP-N01.
    function test_givenCapN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenLiveDebt_whenCapBelowDebt_reverts(address(0xabc1), uint8(1), uint128(0));
        _restore(checkpoint);
        test_givenLiveDebt_whenCapBelowDebt_reverts(address(0xabc1), uint8(1), uint128(100e9 - 1));
        _restore(checkpoint);
    }

    // Scenarios: BLCT-QUEUE-CAP-N02.
    function test_givenCapN02Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenDebtBoundary_whenCapEqualsDebt_thenAccepted(
            address(0xabc1),
            uint8(1),
            uint128(0)
        );
        _restore(checkpoint);
        test_givenDebtBoundary_whenCapEqualsDebt_thenAccepted(
            address(0xabc1),
            uint8(1),
            uint128(1)
        );
        _restore(checkpoint);
        test_givenDebtBoundary_whenCapEqualsDebt_thenAccepted(
            address(0xabc1),
            uint8(1),
            type(uint128).max
        );
        _restore(checkpoint);
    }

    // Scenarios: BLCT-QUEUE-CAP-N03.
    function test_givenCapN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenLiveDebt_whenCapAboveDebt_thenAccepted(
            address(0xabc1),
            uint8(1),
            uint128(0),
            uint128(1)
        );
        _restore(checkpoint);
        test_givenLiveDebt_whenCapAboveDebt_thenAccepted(
            address(0xabc1),
            uint8(1),
            uint128(1),
            type(uint128).max
        );
        _restore(checkpoint);
        test_givenLiveDebt_whenCapAboveDebt_thenAccepted(
            address(0xabc1),
            uint8(1),
            type(uint128).max - 1,
            type(uint128).max
        );
        _restore(checkpoint);
    }

    function _queue(ITimelockBatchQueue.BatchAction memory a_) internal returns (uint64) {
        (address asset, uint128 cap) = abi.decode(a_.payload, (address, uint128));
        return _timelock.queueSetAssetDebtCap(asset, cap);
    }
}
