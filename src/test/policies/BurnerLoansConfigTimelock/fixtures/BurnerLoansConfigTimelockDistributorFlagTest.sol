// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Reverting getter probes intentionally ignore their return value; state selectors remain inline
// so each scenario branch is easy to audit.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansConfigTimelockTest} from "src/test/policies/BurnerLoansConfigTimelock/BurnerLoansConfigTimelockTest.sol";

abstract contract BurnerLoansConfigTimelockDistributorFlagTest is BurnerLoansConfigTimelockTest {
    function _flagSelector(bool fee_) internal pure returns (bytes4) {
        return
            fee_
                ? IBurnerLoansConfig.setSendFeesToDistributor.selector
                : IBurnerLoansConfig.setSendYieldToDistributor.selector;
    }

    function _flag(bool fee_) internal view returns (bool) {
        return fee_ ? burnerLoans.sendFeesToDistributor() : burnerLoans.sendYieldToDistributor();
    }

    function _setFlag(bool fee_, bool enabled_) internal {
        vm.prank(address(burnerLoansConfig));
        if (fee_) burnerLoans.setSendFeesToDistributor(enabled_);
        else burnerLoans.setSendYieldToDistributor(enabled_);
    }

    function _queueFlag(
        bool fee_,
        bool enabled_,
        address proposer_
    ) internal returns (uint64 actionId) {
        vm.prank(proposer_);
        return
            fee_
                ? configTimelock.queueSetSendFeesToDistributor(enabled_)
                : configTimelock.queueSetSendYieldToDistributor(enabled_);
    }

    function _permittedProposer(bool useAdmin_) internal view returns (address) {
        return useAdmin_ ? admin : burnerLoansAdmin;
    }

    function _installValidDistributor(
        bool listAsset_
    ) internal returns (RevenueDistributor distributor) {
        distributor = _deployRevenueDistributor(true, listAsset_);
        _selectRevenueDistributor(distributor);
    }

    function _assertFlagActionQueued(
        uint64 actionId_,
        bool fee_,
        bool enabled_,
        address proposer_,
        bool expectedCurrentFlag_,
        address expectedDistributor_
    ) internal view returns (bytes32 key) {
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId_);
        assertEq(action.proposer, proposer_, "queued proposer");
        assertFalse(action.executed, "queued action not executed");
        assertFalse(action.cancelled, "queued action not cancelled");
        assertEq(action.actions.length, 1, "queued sub-action count");
        assertEq(action.actions[0].target, address(burnerLoansConfig), "queued target");
        assertEq(action.actions[0].selector, _flagSelector(fee_), "queued selector");
        assertEq(action.actions[0].payload, abi.encode(enabled_), "queued payload");
        assertEq(_flag(fee_), expectedCurrentFlag_, "queue does not change flag");
        assertEq(configTimelock.getQueuedConfigStateCount(actionId_, 0), 1, "one state guard");
        bytes32 expectedHash;
        (key, expectedHash) = configTimelock.getQueuedConfigState(actionId_, 0, 0);
        assertEq(
            expectedHash,
            keccak256(abi.encode(address(burnerLoans), expectedCurrentFlag_, expectedDistributor_)),
            "queued state hash"
        );
        assertEq(configTimelock.pendingActionId(key), actionId_, "queued key owner");
    }

    function _assertFlagActionPending(uint64 actionId_, bytes32 key_) internal view {
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId_);
        assertFalse(action.executed, "failed action remains pending");
        assertFalse(action.cancelled, "failed action remains uncancelled");
        assertEq(action.actions.length, 1, "failed action retained");
        assertEq(configTimelock.pendingActionId(key_), actionId_, "failed key retained");
    }

    function _assertFlagActionExecuted(uint64 actionId_, bytes32 key_) internal view {
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId_);
        assertTrue(action.executed, "action executed");
        assertFalse(action.cancelled, "action not cancelled");
        assertEq(action.actions.length, 0, "executed actions cleared");
        assertEq(configTimelock.pendingActionId(key_), 0, "executed key released");
        assertEq(
            configTimelock.getQueuedConfigStateCount(actionId_, 0),
            0,
            "executed state guard cleared"
        );
    }

    function _warpReady(uint64 actionId_) internal {
        vm.warp(configTimelock.getQueuedAction(actionId_).executableAt);
    }

    function _assertQueueRejected(
        uint64 nextActionId_,
        bool fee_,
        bool expectedFlag_
    ) internal view {
        assertEq(configTimelock.nextActionId(), nextActionId_, "failed queue consumes no id");
        assertEq(_flag(fee_), expectedFlag_, "failed queue preserves flag");
    }

    function _disableDistributor(RevenueDistributor distributor_) internal {
        vm.prank(admin);
        distributor_.disable("");
    }

    function _disableConfig() internal {
        vm.prank(admin);
        burnerLoansConfig.disable("");
    }

    function _disableTimelock() internal {
        vm.prank(admin);
        configTimelock.disable("");
    }

    function _disableFacility() internal {
        vm.prank(admin);
        burnerLoans.disable("");
    }

    function _expectInvalidDistributor(address distributor_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidRevenueDistributor.selector,
                distributor_
            )
        );
    }

    function _assertNoQueueState(uint64 actionId_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId_
            )
        );
        configTimelock.getQueuedAction(actionId_);
    }

    function _assertConfigConflict(
        uint64 actionId_,
        bytes32 key_,
        bytes32 oldHash_,
        bool currentFlag_,
        address currentDistributor_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId_,
                uint256(0),
                key_,
                oldHash_,
                keccak256(abi.encode(address(burnerLoans), currentFlag_, currentDistributor_))
            )
        );
        configTimelock.executeQueuedAction(actionId_);
        _assertFlagActionPending(actionId_, key_);
    }

    function _checkInvalidDistributorQueue(bool fee_, bool useAdmin_, uint8 state_) internal {
        RevenueDistributor distributor = _installValidDistributor(false);
        if (state_ == 0) _deactivatePolicy(address(distributor));
        if (state_ == 1) _disableDistributor(distributor);
        if (state_ == 2) _mockKernelRevert(address(distributor));
        if (state_ == 3) _mockKernelMalformed(address(distributor));
        if (state_ == 4) _mockEnabledRevert(address(distributor));
        if (state_ == 5) _mockEnabledMalformed(address(distributor));
        uint64 next = configTimelock.nextActionId();

        _expectInvalidDistributor(address(distributor));
        _queueFlag(fee_, true, _permittedProposer(useAdmin_));
        _assertQueueRejected(next, fee_, false);
        _assertNoQueueState(next);
        vm.clearMockedCalls();
    }

    function _checkInvalidReadyExecution(bool fee_, uint8 state_) internal {
        RevenueDistributor distributor = _installValidDistributor(false);
        uint64 actionId = _queueFlag(fee_, true, admin);
        (bytes32 key, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        if (state_ == 0) _deactivatePolicy(address(burnerLoans));
        if (state_ == 1) _deactivatePolicy(address(distributor));
        if (state_ == 2) _disableDistributor(distributor);
        if (state_ == 3) _disableFacility();
        if (state_ == 4) _mockKernelRevert(address(distributor));
        if (state_ == 5) _mockKernelMalformed(address(distributor));
        if (state_ == 6) _mockEnabledRevert(address(distributor));
        if (state_ == 7) _mockEnabledMalformed(address(distributor));
        _warpReady(actionId);

        if (state_ == 0) vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        else if (state_ == 3) vm.expectRevert(IEnabler.NotEnabled.selector);
        else _expectInvalidDistributor(address(distributor));
        configTimelock.executeQueuedAction(actionId);
        assertFalse(_flag(fee_), "failed execution preserves flag");
        _assertFlagActionPending(actionId, key);
        vm.clearMockedCalls();
    }
}
