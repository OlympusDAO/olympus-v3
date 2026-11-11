// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Policy} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansPayoutConfigTimelock} from "src/policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

abstract contract BurnerLoansPayoutConfigTimelockTest is BurnerLoansModularTest {
    using stdStorage for StdStorage;
    BurnerLoansPayoutConfigTimelock internal _payoutTimelock;
    uint64 internal _pendingId;

    modifier givenPendingRecovery() {
        _pendingId = _payoutTimelock.queueRescue(address(_asset), _borrower);
        _;
    }

    function setUp() public virtual override {
        super.setUp();
        _payoutTimelock = new BurnerLoansPayoutConfigTimelock(_kernel, _payout);
        _kernel.executeAction(Actions.ActivatePolicy, address(_payoutTimelock));
        _payout.setConfigOperator(address(_payoutTimelock));
        _payoutTimelock.enable("");
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, _recipient);
    }

    function _grantProposer(address caller_, bool blOnly_, bool overlap_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this) && caller_ != _recipient);
        _rolesAdmin.grantRole(blOnly_ ? BURNER_LOANS_ADMIN_ROLE : ADMIN_ROLE, caller_);
        if (overlap_)
            _rolesAdmin.grantRole(blOnly_ ? ADMIN_ROLE : BURNER_LOANS_ADMIN_ROLE, caller_);
    }

    function _excludeProposers(address caller_) internal view {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE));
    }

    function _setState(Policy policy_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(policy_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(policy_));
    }

    function _restore(uint256 snapshot_) internal {
        assertTrue(vm.revertToState(snapshot_), "Restore independent boundary fixture");
        vm.clearMockedCalls();
    }

    function _distributor() internal returns (RevenueDistributor next) {
        next = new RevenueDistributor(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(next));
        next.enable("");
        _payout.setRevenueDistributor(address(next));
    }

    function _fundPending(uint256 amount_) internal {
        _asset.mint(address(_payout), amount_);
        // Retain a real keeper obligation by rejecting its optional initial payout.
        vm.mockCall(
            address(_asset),
            abi.encodePacked(_asset.transfer.selector, abi.encode(_recipient)),
            abi.encode(false)
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_asset), _recipient, amount_, 0);
        vm.clearMockedCalls();
    }

    function _fundPendingReferral(uint256 amount_) internal {
        _asset.mint(address(_payout), amount_);
        vm.mockCall(
            address(_asset),
            abi.encodePacked(_asset.transfer.selector, abi.encode(_recipient)),
            abi.encode(false)
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_asset), 0, _recipient, amount_);
        vm.clearMockedCalls();
    }

    function _payoutDigest() internal view returns (bytes32) {
        (uint256 fees, , uint256 seized, , uint256 pending) = _payout.pendingAmounts(
            address(_asset)
        );
        return
            keccak256(
                abi.encode(
                    _payout.configOperator(),
                    _payout.revenueDistributor(),
                    _payout.sendFeesToDistributor(),
                    _payout.sendYieldToDistributor(),
                    fees,
                    seized,
                    pending,
                    _payout.pendingRecipientAmount(address(_asset), _recipient),
                    _asset.balanceOf(address(_payout)),
                    _asset.balanceOf(_borrower),
                    _asset.balanceOf(_recipient),
                    _asset.balanceOf(_payout.treasury())
                )
            );
    }

    function _action(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return ITimelockBatchQueue.BatchAction(address(_payout), selector_, payload_);
    }

    function _single(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = action_;
    }

    function _rescueAction() internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return _action(IBurnerLoansPayout.rescue.selector, abi.encode(address(_asset), _borrower));
    }

    function _localKey(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure returns (bytes32) {
        if (action_.selector == IBurnerLoansPayout.rescue.selector) {
            (address token, ) = abi.decode(action_.payload, (address, address));
            return keccak256(abi.encode(action_.selector, token));
        }
        if (action_.selector == IBurnerLoansPayout.rescuePendingPayout.selector) {
            (address token, address recipient, , ) = abi.decode(
                action_.payload,
                (address, address, address, uint256)
            );
            return keccak256(abi.encode(action_.selector, token, recipient));
        }
        return keccak256(abi.encode(action_.selector));
    }

    function _scopedKey(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(address(_payout), _localKey(action_)));
    }

    function _stateHash(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view returns (bytes32) {
        if (action_.selector == IBurnerLoansPayout.setSendFeesToDistributor.selector)
            return
                keccak256(
                    abi.encode(
                        address(_payoutTimelock),
                        _payout.sendFeesToDistributor(),
                        _payout.revenueDistributor()
                    )
                );
        if (action_.selector == IBurnerLoansPayout.setSendYieldToDistributor.selector)
            return
                keccak256(
                    abi.encode(
                        address(_payoutTimelock),
                        _payout.sendYieldToDistributor(),
                        _payout.revenueDistributor()
                    )
                );
        if (action_.selector == IBurnerLoansPayout.rescuePendingPayout.selector)
            return
                keccak256(
                    abi.encode(
                        address(_payoutTimelock),
                        _payout.sendFeesToDistributor(),
                        _payout.revenueDistributor(),
                        _payout.treasury()
                    )
                );
        return keccak256(abi.encode(address(_payoutTimelock)));
    }

    function _assertQueued(
        uint64 id_,
        ITimelockBatchQueue.BatchAction[] memory actions_,
        address proposer_,
        address reader_
    ) internal {
        vm.prank(reader_);
        ITimelockBatchQueue.QueuedAction memory q = _payoutTimelock.getQueuedAction(id_);
        assertEq(q.proposer, proposer_, "Exact proposer");
        assertEq(q.queuedAt, vm.getBlockTimestamp(), "Exact queue timestamp");
        assertEq(q.executableAt, vm.getBlockTimestamp() + 1 days, "One-day notice");
        assertEq(q.expiresAt, vm.getBlockTimestamp() + 4 days, "Three-day window");
        assertFalse(q.executed, "Pending execution");
        assertFalse(q.cancelled, "Not cancelled");
        assertEq(
            keccak256(abi.encode(q.actions)),
            keccak256(abi.encode(actions_)),
            "Exact ordered stored payloads"
        );
        vm.prank(reader_);
        assertEq(_payoutTimelock.getQueuedActionLength(id_), actions_.length, "Exact batch length");
        for (uint256 i; i < actions_.length; ++i) {
            vm.prank(reader_);
            (address target, bytes4 selector, bytes memory payload) = _payoutTimelock
                .getQueuedSubAction(id_, i);
            assertEq(target, address(_payout), "Immutable target");
            assertEq(selector, actions_[i].selector, "Exact selector");
            assertEq(payload, actions_[i].payload, "Exact bytes");
            assertEq(
                _payoutTimelock.getQueuedConfigDestination(id_, i),
                address(_payout),
                "Guard destination"
            );
            assertEq(_payoutTimelock.getQueuedConfigStateCount(id_, i), 1, "One guard");
            (bytes32 key, bytes32 expected) = _payoutTimelock.getQueuedConfigState(id_, i, 0);
            assertEq(key, _scopedKey(actions_[i]), "Independent destination-scoped key");
            assertEq(expected, _stateHash(actions_[i]), "Independent documented state tuple");
            assertEq(_payoutTimelock.pendingActionId(key), id_, "Key owner");
        }
        assertEq(_payoutTimelock.nextActionId(), uint256(id_) + 1, "One ID consumed");
    }

    function _expectQueueEvents(
        ITimelockBatchQueue.BatchAction[] memory actions_,
        address proposer_
    ) internal {
        uint64 id = _payoutTimelock.nextActionId();
        for (uint256 i; i < actions_.length; ++i) {
            vm.expectEmit(address(_payoutTimelock));
            emit IConfigTimelockBatchQueue.ConfigStateQueued(
                id,
                i,
                _scopedKey(actions_[i]),
                0,
                address(_payout),
                _stateHash(actions_[i])
            );
        }
        for (uint256 i; i < actions_.length; ++i) {
            vm.expectEmit(address(_payoutTimelock));
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                id,
                address(_payout),
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }
        vm.expectEmit(address(_payoutTimelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            id,
            proposer_,
            keccak256(abi.encode(actions_)),
            uint48(vm.getBlockTimestamp() + 1 days),
            uint48(vm.getBlockTimestamp() + 4 days)
        );
    }

    function _queueDigest(uint64 id_) internal view returns (bytes32 result) {
        ITimelockBatchQueue.QueuedAction memory q = _payoutTimelock.getQueuedAction(id_);
        result = keccak256(abi.encode(q, _payoutTimelock.nextActionId()));
        for (uint256 i; i < q.actions.length; ++i) {
            (bytes32 key, bytes32 hash) = _payoutTimelock.getQueuedConfigState(id_, i, 0);
            result = keccak256(
                abi.encode(
                    result,
                    key,
                    hash,
                    _payoutTimelock.pendingActionId(key),
                    _payoutTimelock.getQueuedConfigDestination(id_, i)
                )
            );
        }
    }

    function _expectQueueRejected(
        bytes memory call_,
        bytes memory reason_,
        address caller_
    ) internal {
        uint64 next = _payoutTimelock.nextActionId();
        bytes32 funds = _payoutDigest();
        vm.prank(caller_);
        (bool ok, bytes memory data) = address(_payoutTimelock).call(call_);
        assertFalse(ok, "Queue must reject");
        assertEq(data, reason_, "Exact queue rejection");
        assertEq(_payoutTimelock.nextActionId(), next, "No ID consumed");
        assertEq(_payoutTimelock.getQueuedConfigStateCount(next, 0), 0, "No partial guard");
        assertEq(
            _payoutTimelock.getQueuedConfigDestination(next, 0),
            address(0),
            "No partial destination"
        );
        assertEq(_payoutDigest(), funds, "No target or funds mutation");
    }

    function _assertCleared(
        uint64 id_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal view {
        assertEq(_payoutTimelock.getQueuedAction(id_).actions.length, 0, "Payload cleared");
        for (uint256 i; i < actions_.length; ++i) {
            assertEq(_payoutTimelock.pendingActionId(_scopedKey(actions_[i])), 0, "Key released");
            assertEq(_payoutTimelock.getQueuedConfigStateCount(id_, i), 0, "Guard cleared");
            assertEq(
                _payoutTimelock.getQueuedConfigDestination(id_, i),
                address(0),
                "Destination cleared"
            );
        }
    }

    function _makeReady(uint64 id_) internal {
        vm.warp(_payoutTimelock.getQueuedAction(id_).executableAt);
    }

    function _mockPayoutKernel(address kernel_) internal {
        vm.mockCall(address(_payout), abi.encodeWithSignature("kernel()"), abi.encode(kernel_));
    }

    function _rejectTargetReads() internal {
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
    }

    function _setNextId(uint64 id_) internal {
        stdstore
            .target(address(_payoutTimelock))
            .sig("nextActionId()")
            .enable_packed_slots()
            .checked_write(uint256(id_));
    }

    function _expectLocalRejected(
        bytes memory call_,
        bytes memory reason_,
        address caller_
    ) internal {
        bytes32 queue = _queueDigest(_pendingId);
        uint48 last = _payoutTimelock.lastTransitionAt();
        uint32 grace = _payoutTimelock.gracePeriod();
        bool enabled = _payoutTimelock.isEnabled();
        vm.prank(caller_);
        (bool ok, bytes memory data) = address(_payoutTimelock).call(call_);
        assertFalse(ok, "Local operation rejects");
        assertEq(data, reason_, "Exact local rejection");
        assertEq(_payoutTimelock.lastTransitionAt(), last, "History unchanged");
        assertEq(_payoutTimelock.gracePeriod(), grace, "Grace unchanged");
        assertEq(_payoutTimelock.isEnabled(), enabled, "Enablement unchanged");
        assertEq(_queueDigest(_pendingId), queue, "Pending work unchanged");
    }

    function _timelockLogCount() internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i)
            if (logs[i].emitter == address(_payoutTimelock)) ++count;
    }

    function _removedGetters(
        uint64 id_,
        bytes memory reason_,
        address reader_,
        uint256 sub_,
        uint256 state_
    ) internal {
        vm.expectRevert(reason_);
        vm.prank(reader_);
        _payoutTimelock.getQueuedActionLength(id_);
        vm.expectRevert(reason_);
        vm.prank(reader_);
        _payoutTimelock.getQueuedSubAction(id_, sub_);
        assertEq(
            _payoutTimelock.getQueuedConfigDestination(id_, sub_),
            address(0),
            "No destination"
        );
        assertEq(_payoutTimelock.getQueuedConfigStateCount(id_, sub_), 0, "No guard");
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                id_,
                sub_,
                state_,
                uint256(0)
            )
        );
        vm.prank(reader_);
        _payoutTimelock.getQueuedConfigState(id_, sub_, state_);
    }
}
