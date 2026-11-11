// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {Actions, Policy} from "src/Kernel.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {BurnerLoansRiskConfigTimelock} from "src/policies/burnerloans/BurnerLoansRiskConfigTimelock.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

abstract contract BurnerLoansRiskConfigTimelockTest is BurnerLoansModularTest {
    BurnerLoansRiskConfigTimelock internal _timelock;
    bytes32 internal _beforeQueue;
    uint64 internal _next;

    function setUp() public virtual override {
        super.setUp();
        _timelock = new BurnerLoansRiskConfigTimelock(_kernel, _risk);
        _risk.setConfigOperator(address(_timelock));
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        _timelock.enable("");
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(this));
    }

    function _ageAction(
        uint48 age_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_risk),
                IBurnerLoansRisk.setPriceCacheMaxAge.selector,
                abi.encode(age_)
            );
    }

    function _bpsAction(
        uint16 bps_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_risk),
                IBurnerLoansRisk.setReferralFeeBps.selector,
                abi.encode(bps_)
            );
    }

    function _referrerAction(
        address referrer_,
        bool allowed_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            ITimelockBatchQueue.BatchAction(
                address(_risk),
                IBurnerLoansRisk.setReferrerAllowed.selector,
                abi.encode(referrer_, allowed_)
            );
    }

    function _key(ITimelockBatchQueue.BatchAction memory a_) internal pure returns (bytes32) {
        bytes32 local = a_.selector == IBurnerLoansRisk.setReferrerAllowed.selector
            ? keccak256(abi.encode(a_.selector, abi.decode(a_.payload, (address))))
            : keccak256(abi.encode(a_.selector));
        return keccak256(abi.encode(a_.target, local));
    }

    function _hash(ITimelockBatchQueue.BatchAction memory a_) internal view returns (bytes32) {
        address controller = _risk.configOperator();
        if (a_.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector)
            return keccak256(abi.encode(controller, _risk.priceCacheMaxAge()));
        if (a_.selector == IBurnerLoansRisk.setReferralFeeBps.selector)
            return keccak256(abi.encode(controller, _risk.referralFeeBps()));
        return
            keccak256(
                abi.encode(controller, _risk.isReferrerAllowed(abi.decode(a_.payload, (address))))
            );
    }

    function _executeAndAssert(uint64 id_, address caller_) internal {
        ITimelockBatchQueue.BatchAction[] memory actions = _timelock.getQueuedAction(id_).actions;
        vm.prank(caller_);
        _timelock.executeQueuedAction(id_);
        assertTrue(_timelock.getQueuedAction(id_).executed, "executed marker");
        _assertCleared(id_, actions);
        for (uint256 i; i < actions.length; ++i) {
            ITimelockBatchQueue.BatchAction memory a = actions[i];
            if (a.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector)
                assertEq(
                    _risk.priceCacheMaxAge(),
                    abi.decode(a.payload, (uint48)),
                    "age dispatched"
                );
            else if (a.selector == IBurnerLoansRisk.setReferralFeeBps.selector)
                assertEq(
                    _risk.referralFeeBps(),
                    abi.decode(a.payload, (uint16)),
                    "percentage dispatched"
                );
            else {
                (address referrer, bool allowed) = abi.decode(a.payload, (address, bool));
                assertEq(_risk.isReferrerAllowed(referrer), allowed, "membership dispatched");
            }
        }
    }

    function _setState(Policy policy_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(policy_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(policy_));
    }

    function _proposer(address caller_, uint8 role_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        role_ = uint8(bound(role_, 0, 2));
        if (role_ != 1) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (role_ != 0) _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller_);
    }

    function _outsider(address caller_) internal view {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE));
    }

    function _single(
        ITimelockBatchQueue.BatchAction memory a_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = a_;
    }

    function _pair(
        ITimelockBatchQueue.BatchAction memory a_,
        ITimelockBatchQueue.BatchAction memory b_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = a_;
        actions[1] = b_;
    }

    function _economicDigest() internal view returns (bytes32) {
        uint32 market = _core.marketId(address(_asset));
        bytes32 accounting = keccak256(
            abi.encode(
                _floan.getMarket(market),
                _floan.getMarketConfigData(market),
                _inventory.activePrincipalOhm(),
                _inventory.suppliedOhm()
            )
        );
        bytes32 wallets = keccak256(
            abi.encode(
                _ohm.totalSupply(),
                _ohm.balanceOf(address(_inventory)),
                _asset.balanceOf(address(_core)),
                _asset.balanceOf(address(_payout)),
                _asset.balanceOf(_borrower),
                _asset.balanceOf(_recipient)
            )
        );
        return
            keccak256(
                abi.encode(
                    accounting,
                    wallets,
                    _risk.priceCacheMaxAge(),
                    _risk.referralFeeBps(),
                    _risk.isReferrerAllowed(_borrower),
                    _risk.isReferrerAllowed(_recipient)
                )
            );
    }

    function _queueDigest(uint64 id_) internal view returns (bytes32 digest) {
        ITimelockBatchQueue.QueuedAction memory q = _timelock.getQueuedAction(id_);
        digest = keccak256(abi.encode(q));
        for (uint256 i; i < q.actions.length; ++i) {
            (bytes32 key, bytes32 h) = _timelock.getQueuedConfigState(id_, i, 0);
            digest = keccak256(
                abi.encode(
                    digest,
                    _timelock.getQueuedConfigDestination(id_, i),
                    key,
                    h,
                    _timelock.pendingActionId(key)
                )
            );
        }
    }

    function _expectQueue(
        ITimelockBatchQueue.BatchAction[] memory actions_,
        address caller_
    ) internal {
        _next = _timelock.nextActionId();
        _beforeQueue = _economicDigest();
        for (uint256 i; i < actions_.length; ++i) {
            vm.expectEmit(address(_timelock));
            emit IConfigTimelockBatchQueue.ConfigStateQueued(
                _next,
                i,
                _key(actions_[i]),
                0,
                actions_[i].target,
                _hash(actions_[i])
            );
        }
        for (uint256 i; i < actions_.length; ++i) {
            vm.expectEmit(address(_timelock));
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                _next,
                actions_[i].target,
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            _next,
            caller_,
            keccak256(abi.encode(actions_)),
            uint48(vm.getBlockTimestamp() + 1 days),
            uint48(vm.getBlockTimestamp() + 4 days)
        );
    }

    function _assertQueued(
        uint64 id_,
        ITimelockBatchQueue.BatchAction[] memory actions_,
        address caller_
    ) internal view {
        assertEq(id_, _next, "Return reserved ID");
        ITimelockBatchQueue.QueuedAction memory q = _timelock.getQueuedAction(id_);
        assertEq(q.proposer, caller_, "Exact proposer");
        assertEq(q.queuedAt, vm.getBlockTimestamp(), "Queue timestamp");
        assertEq(q.executableAt, vm.getBlockTimestamp() + 1 days, "One-day delay");
        assertEq(q.expiresAt, vm.getBlockTimestamp() + 4 days, "Three-day window");
        assertFalse(q.executed || q.cancelled, "New action pending");
        assertEq(abi.encode(q.actions), abi.encode(actions_), "Exact ordered payloads");
        assertEq(_timelock.getQueuedActionLength(id_), actions_.length, "Length getter");
        for (uint256 i; i < actions_.length; ++i) {
            (address target, bytes4 selector, bytes memory payload) = _timelock.getQueuedSubAction(
                id_,
                i
            );
            assertEq(
                abi.encode(target, selector, payload),
                abi.encode(actions_[i].target, actions_[i].selector, actions_[i].payload),
                "Subaction getter agrees"
            );
            assertEq(
                _timelock.getQueuedConfigDestination(id_, i),
                actions_[i].target,
                "Concrete destination"
            );
            assertEq(_timelock.getQueuedConfigStateCount(id_, i), 1, "One commitment");
            (bytes32 key, bytes32 h) = _timelock.getQueuedConfigState(id_, i, 0);
            assertEq(key, _key(actions_[i]), "Independent selector/asset key");
            assertEq(h, _hash(actions_[i]), "Complete pre-state commitment");
            assertEq(_timelock.pendingActionId(key), id_, "Action owns key");
        }
        assertEq(_timelock.nextActionId(), uint256(id_) + 1, "One ID consumed");
        assertEq(_economicDigest(), _beforeQueue, "Queue changes no target or accounting");
    }

    function _expectRejectedQueue(bytes memory reason_) internal {
        _next = _timelock.nextActionId();
        _beforeQueue = _economicDigest();
        vm.expectRevert(reason_);
    }

    function _assertRejectedQueue(ITimelockBatchQueue.BatchAction[] memory actions_) internal view {
        assertEq(_timelock.nextActionId(), _next, "Rejected queue consumes no ID");
        assertEq(_economicDigest(), _beforeQueue, "Rejected queue preserves accounting");
        for (uint256 i; i < actions_.length; ++i) {
            assertEq(_timelock.getQueuedConfigStateCount(_next, i), 0, "No partial commitment");
            assertEq(
                _timelock.getQueuedConfigDestination(_next, i),
                address(0),
                "No partial destination"
            );
        }
    }

    function _makeReady(uint64 id_) internal {
        vm.warp(_timelock.getQueuedAction(id_).executableAt);
    }

    function _assertCleared(
        uint64 id_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal view {
        assertEq(_timelock.getQueuedAction(id_).actions.length, 0, "Terminal payloads cleared");
        for (uint256 i; i < actions_.length; ++i) {
            assertEq(_timelock.pendingActionId(_key(actions_[i])), 0, "Key released");
            assertEq(_timelock.getQueuedConfigStateCount(id_, i), 0, "Commitment cleared");
            assertEq(
                _timelock.getQueuedConfigDestination(id_, i),
                address(0),
                "Destination cleared"
            );
        }
    }

    function _executeReverts(uint64 id_, address caller_, bytes memory reason_) internal {
        bytes32 queue = _queueDigest(id_);
        bytes32 funds = _economicDigest();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.executeQueuedAction(id_);
        assertEq(
            _queueDigest(id_),
            queue,
            "Failed execution preserves guards, owners and payloads"
        );
        assertEq(_economicDigest(), funds, "Failed batch rolls back all writes and transfers");
    }

    function _stateChanged(
        uint64 id_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory a_,
        bytes32 expected_
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id_,
                index_,
                _key(a_),
                expected_,
                _hash(a_)
            );
    }

    function _pending(
        ITimelockBatchQueue.BatchAction memory a_,
        uint64 owner_
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _key(a_),
                owner_
            );
    }

    function _invalid(
        ITimelockBatchQueue.BatchAction memory a_
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                a_.target,
                a_.selector
            );
    }

    function _restore(uint256 checkpoint_) internal {
        assertTrue(vm.revertToState(checkpoint_), "Restore independent scenario seed");
        vm.clearMockedCalls();
    }

    function _threeActions() internal view returns (ITimelockBatchQueue.BatchAction[] memory a) {
        a = new ITimelockBatchQueue.BatchAction[](3);
        a[0] = _ageAction(3600);
        a[1] = _bpsAction(2500);
        a[2] = _referrerAction(_recipient, true);
    }

    function _permutation(uint8 index_) internal pure returns (uint256[3] memory order) {
        uint256[3][6] memory orders = [
            [uint256(0), 1, 2],
            [uint256(0), 2, 1],
            [uint256(1), 0, 2],
            [uint256(1), 2, 0],
            [uint256(2), 0, 1],
            [uint256(2), 1, 0]
        ];
        return orders[index_];
    }

    function _assertNoTargetLogs(Vm.Log[] memory logs_, address target_) internal pure {
        for (uint256 i; i < logs_.length; ++i)
            assertTrue(logs_[i].emitter != target_, "No event from unchanged target");
    }

    function _assertNoTargetWrites(address target_) internal {
        (, bytes32[] memory writes) = vm.accesses(target_);
        assertEq(writes.length, 0, "No storage write for unchanged target configuration");
    }

    function _anotherRisk() internal returns (BurnerLoansRisk candidate) {
        candidate = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            _risk.backingOracle(),
            address(0),
            0,
            address(_core)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(candidate));
        candidate.enable("");
    }
}
