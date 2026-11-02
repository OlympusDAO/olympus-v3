// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
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
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";

contract BurnerLoansConfigTimelockQueueSetAssetWithdrawAsSharesTest is
    BurnerLoansConfigTimelockTest
{
    // Scenarios: BLCT-QUEUE-SHARES-A01.
    function test_givenUnauthorizedProposer_givenConfigEnabled_whenQueued_reverts(
        address caller_
    ) public {
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-A02.
    function test_givenUnauthorizedProposer_givenConfigDisabled_whenQueued_reverts(
        address caller_
    ) public {
        _config.disable("");
        _outsider(caller_);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectRejectedQueue(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-A03.
    function test_givenWrongOperator_givenConfigEnabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-A04.
    function test_givenWrongOperator_givenConfigDisabled_whenQueued_reverts(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _config.setConfigOperator(zero_ ? address(0) : _recipient);
        _config.disable("");
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-A05.
    function test_givenPermittedProposer_whenQueued_thenValidatedAndStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-SHARES-L01.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-L02.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-L03.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-L04.
    function test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectRejectedQueue(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-L05.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L06.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L07.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L08.
    function test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, false);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L09.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L10.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L11.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L12.
    function test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, false, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L13.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, true);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L14.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, false, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-L15.
    function test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _setState(_config, true, false);
        _setState(_timelock, true, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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

    // Scenarios: BLCT-QUEUE-SHARES-I01.
    function test_givenUnregisteredAsset_whenQueued_reverts(
        address caller_,
        uint8 role_,
        address unregistered_
    ) public {
        _proposer(caller_, role_);
        vm.assume(!_config.isAssetConfigured(unregistered_));
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(unregistered_, false);
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

    // Scenarios: BLCT-QUEUE-SHARES-P01.
    function test_givenFreeKey_whenQueued_thenExactMetadata(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-SHARES-P02.
    function test_givenSameSetterSameAssetPending_whenQueuedAgain_reverts(
        address caller_,
        uint8 role_,
        bool same_
    ) public {
        _proposer(caller_, role_);
        _useVaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
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
        assertEq(_queueDigest(id), original, "Duplicate preserves original payload and owner");
    }

    // Scenarios: BLCT-QUEUE-SHARES-P03.
    function test_givenSameSetterOtherAssetPending_whenQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address other, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), false);
        ITimelockBatchQueue.BatchAction memory b = _sharesAction(other, false);
        _independentActions(a, b, caller_);
    }

    // Scenarios: BLCT-QUEUE-SHARES-P04.
    function test_givenCommittedStateDrift_whenExecuted_reverts(address executor_) public {
        (address token, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(token, false);
        uint64 id = _queue(a);
        bytes32 expected = _hash(a);
        _config.setAssetWithdrawAsShares(token, true);
        _makeReady(id);
        _executeReverts(id, executor_, _stateChanged(id, 0, a, expected));
    }

    // Scenarios: BLCT-QUEUE-SHARES-P05.
    function test_givenReadyUnchangedState_whenExecuted_thenExactSetterAndCleanup(
        address executor_
    ) public {
        (address token, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(token, true);
        uint64 id = _queue(a);
        _makeReady(id);
        _executeAndAssert(id, executor_);
    }

    // Scenarios: BLCT-QUEUE-SHARES-P12.
    function test_givenCapPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _capAction(address(_asset), 200000e9),
            _sharesAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-SHARES-P13.
    function test_givenOriginationsPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _originationsAction(address(_asset), false),
            _sharesAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-SHARES-P14.
    function test_givenRiskPendingForSameAsset_whenSharesQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _riskAction(address(_asset), _riskInput()),
            _sharesAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-SHARES-P15.
    function test_givenFeePendingForSameAsset_whenSharesQueued_thenBothOrdersExecute(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _independentActions(
            _feeAction(address(_asset), _fees()),
            _sharesAction(address(_asset), false),
            caller_
        );
    }

    // Scenarios: BLCT-QUEUE-SHARES-P06.
    function test_givenDirectCustody_whenSharesRequested_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(address(_asset), true);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(_asset)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-P08.
    function test_givenSynchronousVault_whenUnderlyingQueued_thenStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address token, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(token, false);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-SHARES-P09.
    function test_givenSynchronousVault_whenSharesQueued_thenStored(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address token, ) = _vaultAsset();
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(token, true);
        _expectQueue(_single(a), caller_);
        vm.prank(caller_);
        uint64 id = _queue(a);
        _assertQueued(id, _single(a), caller_);
    }

    // Scenarios: BLCT-QUEUE-SHARES-P07, BLCT-QUEUE-SHARES-P10.
    function test_givenAsynchronousVault_whenUnderlyingQueued_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        (address token, MockERC7540ExternalShareVault vault) = _mutableVaultAsset();
        vault.setCapabilities(false, true, true, true);
        ITimelockBatchQueue.BatchAction memory a = _sharesAction(token, false);
        _expectRejectedQueue(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                token,
                address(vault)
            )
        );
        vm.prank(caller_);
        _queue(a);
        _assertRejectedQueue(_single(a));
    }

    // Scenarios: BLCT-QUEUE-SHARES-P11.
    function test_givenSupportDriftAfterQueue_whenExecuted_thenEarlierWritesRollBack(
        address executor_
    ) public {
        (address token, address vault) = _vaultAsset();
        _config.setAssetWithdrawAsShares(token, true);
        ITimelockBatchQueue.BatchAction[] memory actions = _pair(
            _capAction(address(_asset), 200000e9),
            _sharesAction(token, false)
        );
        uint64 id = _timelock.queueBatch(actions);
        _depositManager.setAssetShareWithdrawalRequired(IERC20(token), true);
        _makeReady(id);
        _executeReverts(
            id,
            executor_,
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                token,
                vault
            )
        );
    }

    // Scenarios: BLCT-QUEUE-SHARES-A05.
    function test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 0);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 1);
        _restore(checkpoint);
        test_givenPermittedProposer_whenQueued_thenValidatedAndStored(address(0xabc1), 2);
        _restore(checkpoint);
    }

    function _queue(ITimelockBatchQueue.BatchAction memory a_) internal returns (uint64) {
        (address asset, bool shares) = abi.decode(a_.payload, (address, bool));
        return _timelock.queueSetAssetWithdrawAsShares(asset, shares);
    }
}
