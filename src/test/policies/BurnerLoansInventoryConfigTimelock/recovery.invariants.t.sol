// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts, delays and timestamps are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {InventoryTimelockHandler} from "./fixtures/InventoryTimelockHandler.sol";

contract BurnerLoansInventoryConfigTimelockRecoveryInvariantsTest is
    BurnerLoansInventoryConfigTimelockTest
{
    InventoryTimelockHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _supplyInventory(_borrower, 50e9);
        _ohm.mint(address(_inventory), 1e9);
        _handler = new InventoryTimelockHandler(_timelock, _inventory, _ohm);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_handler));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(_handler));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = _handler.queueBurn.selector;
        selectors[1] = _handler.queueRescue.selector;
        selectors[2] = _handler.cancel.selector;
        selectors[3] = _handler.execute.selector;
        selectors[4] = _handler.fundSurplus.selector;
        selectors[5] = _handler.advanceTime.selector;
        selectors[6] = _handler.setTimelockEnabled.selector;
        selectors[7] = _handler.setInventoryEnabled.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetContract(address(_handler));
    }

    function invariant_queueOwnershipAndProviderBacking() public view {
        assertEq(_timelock.nextActionId(), _handler.nextId(), "Only successful queues consume IDs");
        uint64 pending = _handler.pendingId();
        assertEq(
            _timelock.pendingActionId(_key()),
            pending,
            "Shared key has exactly the pending owner"
        );
        if (pending != 0) {
            ITimelockBatchQueue.QueuedAction memory action = _timelock.getQueuedAction(pending);
            assertFalse(action.executed, "Pending owner is unexecuted");
            assertFalse(action.cancelled, "Pending owner is uncancelled");
            assertEq(action.actions.length, 1, "Pending payload retained");
            assertEq(action.actions[0].target, address(_inventory), "Immutable target retained");
            assertEq(
                action.actions[0].selector,
                _handler.pendingSelector(),
                "Typed action retained"
            );
            assertEq(action.actions[0].payload, bytes(""), "Recovery payload stays empty");
            (bytes32 key, bytes32 hash) = _timelock.getQueuedConfigState(pending, 0, 0);
            assertEq(key, _key(), "Pending shared key retained");
            assertEq(
                hash,
                keccak256(abi.encode(address(_timelock))),
                "Controller commitment retained"
            );
        }
        uint64 terminal = _handler.lastTerminalId();
        if (terminal != 0) {
            ITimelockBatchQueue.QueuedAction memory action = _timelock.getQueuedAction(terminal);
            assertTrue(action.executed != action.cancelled, "Exactly one terminal outcome");
            assertEq(action.actions.length, 0, "Terminal payload removed");
            assertEq(
                _timelock.getQueuedConfigStateCount(terminal, 0),
                0,
                "Terminal commitment removed"
            );
            assertEq(
                _timelock.getQueuedConfigDestination(terminal, 0),
                address(0),
                "Terminal destination removed"
            );
        }
        assertEq(_inventory.suppliedOhm(), 50e9, "Aggregate claims never recovered as surplus");
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Provider idle never recovered as surplus");
        assertEq(_inventory.providerClaimOhm(_borrower), 50e9, "Individual claim preserved");
        assertEq(_inventory.activePrincipalOhm(), 0, "Recovery creates no borrowing principal");
        assertEq(
            _inventory.globalDebtCapOhm(),
            100_000e9,
            "Recovery cannot reconfigure the debt cap"
        );
        assertGe(_ohm.balanceOf(address(_inventory)), 50e9, "All provider claims remain backed");
        assertEq(
            _ohm.totalSupply(),
            _handler.expectedSupply(),
            "Only burns reduce independently modelled supply"
        );
        assertEq(
            _ohm.balanceOf(_treasury()),
            _handler.expectedTreasuryBalance(),
            "Only rescues credit Treasury"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
