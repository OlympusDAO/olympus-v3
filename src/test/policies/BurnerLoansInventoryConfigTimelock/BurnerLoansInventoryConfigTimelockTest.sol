// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// Expected-revert calls and repeated configuration probes discard their return values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansInventoryConfigTimelock} from "src/policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

abstract contract BurnerLoansInventoryConfigTimelockTest is BurnerLoansModularTest {
    using stdStorage for StdStorage;
    BurnerLoansInventoryConfigTimelock internal _timelock;
    uint64 internal _pendingId;

    modifier givenPendingRecovery() {
        _pendingId = _timelock.queueRescueSurplus();
        _;
    }

    modifier givenProviderSurplus() {
        _supplyInventory(_borrower, 50e9);
        _ohm.mint(address(_inventory), 1e9);
        _;
    }

    function setUp() public virtual override {
        super.setUp();
        _timelock = new BurnerLoansInventoryConfigTimelock(_kernel, _inventory);
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        _inventory.setConfigOperator(address(_timelock));
        _timelock.enable("");
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, _recipient);
    }

    function _makeReady(uint64 id_) internal {
        vm.warp(_timelock.getQueuedAction(id_).executableAt);
    }

    function _key() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    address(_inventory),
                    keccak256(abi.encode(IBurnerLoansInventory.burnSurplus.selector))
                )
            );
    }

    function _treasury() internal view returns (address) {
        return address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
    }

    function _setState(Policy target_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(target_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(target_));
    }

    function _grantRecoveryAdmin(address caller_, bool blAdmin_, bool overlap_) internal {
        vm.assume(caller_ != address(0) && caller_ != address(this) && caller_ != _recipient);
        _rolesAdmin.grantRole(blAdmin_ ? BURNER_LOANS_ADMIN_ROLE : ADMIN_ROLE, caller_);
        if (overlap_)
            _rolesAdmin.grantRole(blAdmin_ ? ADMIN_ROLE : BURNER_LOANS_ADMIN_ROLE, caller_);
    }

    function _inventoryDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _inventory.activePrincipalOhm(),
                    _inventory.suppliedOhm(),
                    _inventory.suppliedIdleOhm(),
                    _inventory.providerClaimOhm(_borrower),
                    _inventory.globalDebtCapOhm(),
                    _ohm.balanceOf(address(_inventory)),
                    _ohm.balanceOf(_borrower),
                    _ohm.balanceOf(_treasury()),
                    _ohm.totalSupply(),
                    MINTRv1(address(_kernel.getModuleForKeycode(toKeycode("MINTR")))).mintApproval(
                        address(_inventory)
                    )
                )
            );
    }

    function _queueDigest(uint64 id_) internal view returns (bytes32) {
        bytes32 commitment;
        if (_timelock.getQueuedConfigStateCount(id_, 0) != 0) {
            (bytes32 key, bytes32 expected) = _timelock.getQueuedConfigState(id_, 0, 0);
            commitment = keccak256(abi.encode(key, expected));
        }
        return
            keccak256(
                abi.encode(
                    _timelock.getQueuedAction(id_),
                    _timelock.getQueuedConfigDestination(id_, 0),
                    _timelock.getQueuedConfigStateCount(id_, 0),
                    commitment,
                    _timelock.pendingActionId(_key()),
                    _timelock.nextActionId(),
                    _inventoryDigest()
                )
            );
    }

    function _expectQueueEvents(bytes4 selector_, address caller_) internal {
        uint64 id = _timelock.nextActionId();
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction(address(_inventory), selector_, "");
        vm.expectEmit(address(_timelock));
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            id,
            0,
            _key(),
            0,
            address(_inventory),
            keccak256(abi.encode(address(_timelock)))
        );
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            id,
            address(_inventory),
            selector_,
            0,
            keccak256("")
        );
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            id,
            caller_,
            keccak256(abi.encode(actions)),
            SafeCast.toUint48(vm.getBlockTimestamp() + 1 days),
            SafeCast.toUint48(vm.getBlockTimestamp() + 4 days)
        );
    }

    function _assertQueued(uint64 id_, bytes4 selector_, address caller_) internal view {
        ITimelockBatchQueue.QueuedAction memory action = _timelock.getQueuedAction(id_);
        assertEq(action.proposer, caller_, "Exact proposer");
        assertEq(action.queuedAt, vm.getBlockTimestamp(), "Exact queue time");
        assertEq(action.executableAt, vm.getBlockTimestamp() + 1 days, "One-day notice");
        assertEq(action.expiresAt, vm.getBlockTimestamp() + 4 days, "Three-day execution window");
        assertFalse(action.executed, "New action unexecuted");
        assertFalse(action.cancelled, "New action uncancelled");
        assertEq(action.actions.length, 1, "One typed sub-action");
        (address target, bytes4 selector, bytes memory payload) = _timelock.getQueuedSubAction(
            id_,
            0
        );
        assertEq(target, address(_inventory), "Immutable Inventory target");
        assertEq(selector, selector_, "Exact selector");
        assertEq(payload, bytes(""), "Argument-free payload");
        assertEq(_timelock.getQueuedActionLength(id_), 1, "Public length");
        assertEq(
            _timelock.getQueuedConfigDestination(id_, 0),
            address(_inventory),
            "Immutable guarded destination"
        );
        assertEq(_timelock.getQueuedConfigStateCount(id_, 0), 1, "One shared configuration state");
        (bytes32 key, bytes32 hash) = _timelock.getQueuedConfigState(id_, 0, 0);
        assertEq(key, _key(), "Destination-scoped shared recovery key");
        assertEq(hash, keccak256(abi.encode(address(_timelock))), "Only controller committed");
        assertEq(_timelock.pendingActionId(key), id_, "Action owns shared key");
        assertEq(_timelock.nextActionId(), uint256(id_) + 1, "Consume exactly one ID");
    }

    function _assertRecoveryQueued(
        function() external returns (uint64) queue_,
        bytes4 selector_,
        address caller_
    ) internal {
        assertFalse(
            _roles.hasRole(address(_timelock), ADMIN_ROLE),
            "Forwarding timelock has no ADMIN grant"
        );
        bytes32 beforeFunds = _inventoryDigest();
        uint64 next = _timelock.nextActionId();
        _expectQueueEvents(selector_, caller_);
        vm.prank(caller_);
        uint64 id = queue_();
        assertEq(id, next, "Return reserved ID");
        _assertQueued(id, selector_, caller_);
        assertEq(
            _inventoryDigest(),
            beforeFunds,
            "Queueing does not move funds or change Inventory accounting"
        );
    }

    function _expectSubActionIndexRejected(uint64 id_, uint256 index_, address caller_) internal {
        bytes32 state = _queueDigest(id_);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                id_,
                index_,
                uint256(1)
            )
        );
        vm.prank(caller_);
        _timelock.getQueuedSubAction(id_, index_);

        assertEq(_queueDigest(id_), state, "Rejected getter is read-only");
    }

    function _expectConfigStateIndexRejected(uint64 id_, uint256 index_, address caller_) internal {
        bytes32 state = _queueDigest(id_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                id_,
                uint256(0),
                index_,
                uint256(1)
            )
        );
        vm.prank(caller_);
        _timelock.getQueuedConfigState(id_, 0, index_);

        assertEq(_queueDigest(id_), state, "Rejected getter is read-only");
    }

    function _expectSubActionStateIndexRejected(
        uint64 id_,
        uint256 index_,
        address caller_
    ) internal {
        bytes32 state = _queueDigest(id_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                id_,
                index_,
                uint256(0),
                uint256(0)
            )
        );
        vm.prank(caller_);
        _timelock.getQueuedConfigState(id_, index_, 0);
        assertEq(
            _timelock.getQueuedConfigStateCount(id_, index_),
            0,
            "Absent index has zero states"
        );
        assertEq(
            _timelock.getQueuedConfigDestination(id_, index_),
            address(0),
            "Absent index has zero destination"
        );
        assertEq(_queueDigest(id_), state, "Rejected getter is read-only");
    }

    function _assertCleared(uint64 id_) internal view {
        assertEq(_timelock.pendingActionId(_key()), 0, "Terminal action releases shared key");
        assertEq(_timelock.getQueuedAction(id_).actions.length, 0, "Stored payload removed");
        assertEq(_timelock.getQueuedConfigDestination(id_, 0), address(0), "Destination removed");
        assertEq(_timelock.getQueuedConfigStateCount(id_, 0), 0, "State commitments removed");
    }

    function _assertTerminalGetters(uint64 id_, bytes memory reason_, address caller_) internal {
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.getQueuedActionLength(id_);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.getQueuedSubAction(id_, 0);
        assertEq(
            _timelock.getQueuedConfigStateCount(id_, 0),
            0,
            "Terminal or absent state count is zero"
        );
        assertEq(
            _timelock.getQueuedConfigDestination(id_, 0),
            address(0),
            "Terminal or absent destination is zero"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                id_,
                uint256(0),
                uint256(0),
                uint256(0)
            )
        );
        vm.prank(caller_);
        _timelock.getQueuedConfigState(id_, 0, 0);
    }

    function _assertBacking(uint128 idle_) internal view {
        assertEq(_inventory.suppliedIdleOhm(), idle_, "Provider idle unchanged");
        assertEq(_inventory.suppliedOhm(), idle_, "Aggregate claims unchanged");
        assertEq(_inventory.providerClaimOhm(_borrower), idle_, "Individual claim unchanged");
        assertEq(_inventory.activePrincipalOhm(), 0, "No funding principal created");
        assertEq(_ohm.balanceOf(address(_inventory)), idle_, "All claims retain OHM backing");
    }

    function _setNextId(uint64 id_) internal {
        stdstore
            .target(address(_timelock))
            .sig("nextActionId()")
            .enable_packed_slots()
            .checked_write(uint256(id_));
    }

    function _rejectInventoryReadinessReads() internal {
        vm.mockCallRevert(address(_inventory), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
    }

    function _mockInventoryKernel(address kernel_) internal {
        vm.mockCall(address(_inventory), abi.encodeWithSignature("kernel()"), abi.encode(kernel_));
    }

    function _restore(uint256 snapshot_) internal {
        assertTrue(vm.revertToState(snapshot_), "Restore fixture for independent boundary");
        vm.clearMockedCalls();
    }

    function _expectRejectedRecoveryQueue(
        function() external returns (uint64) queue_,
        bytes memory reason_,
        address caller_
    ) internal {
        uint64 next = _timelock.nextActionId();
        uint64 owner = _timelock.pendingActionId(_key());
        bytes32 beforeFunds = _inventoryDigest();
        bytes32 beforeOwner = owner == 0 ? bytes32(0) : _queueDigest(owner);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        queue_();
        assertEq(_timelock.nextActionId(), next, "Rejected queue consumes no ID");
        assertEq(_timelock.pendingActionId(_key()), owner, "Rejected queue preserves key owner");
        assertEq(_timelock.getQueuedConfigStateCount(next, 0), 0, "No partial state commitment");
        assertEq(
            _timelock.getQueuedConfigDestination(next, 0),
            address(0),
            "No partial destination"
        );
        assertEq(
            _inventoryDigest(),
            beforeFunds,
            "Rejected queue preserves funds, claims, principal and approval"
        );
        if (owner != 0)
            assertEq(
                _queueDigest(owner),
                beforeOwner,
                "Rejected duplicate preserves original action"
            );
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)
