// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {BackingOracleConfigTimelockTest, ITimelockBatchQueue} from "./fixtures/BackingOracleConfigTimelockTest.sol";
import {BackingOracleHandler} from "./fixtures/BackingOracleHandler.sol";

// Constants
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleExecuteQueuedActionInvariantTest is BackingOracleConfigTimelockTest {
    BackingOracleHandler internal _handler;

    function setUp() public override {
        super.setUp();
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(100e18));
        _handler = new BackingOracleHandler(_oracle, _timelock);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_handler));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(_handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = _handler.setBacking.selector;
        selectors[1] = _handler.queue.selector;
        selectors[2] = _handler.execute.selector;
        selectors[3] = _handler.cancel.selector;
        selectors[4] = _handler.toggleEnabled.selector;
        targetSelector(FuzzSelector(address(_handler), selectors));
        targetContract(address(_handler));
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-MODEL.
    function invariant_backingAndLifecycleMatchModel() public view {
        assertEq(
            _oracle.backing(),
            _handler.expectedBacking(),
            "backing matches independent model"
        );
        assertEq(_oracle.isEnabled(), _handler.expectedEnabled(), "lifecycle matches model");
        uint64 pending = _handler.pendingId();
        assertEq(_timelock.pendingActionId(_backingKey()), pending, "pending key matches model");
        if (pending != 0) {
            ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(pending);
            assertFalse(a.cancelled || a.executed, "unresolved intent remains pending");
            assertEq(
                a.actions[0].payload,
                abi.encode(_handler.pendingValue()),
                "pending payload preserved"
            );
        }
    }
}
