// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Time movement and model updates intentionally surround production calls.
// forge-lint: disable-start(block-timestamp, reentrancy-no-eth)

// Interfaces
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {Test} from "forge-std/Test.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {BurnerLoansInventoryConfigTimelock} from "src/policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @dev Models admitted operations; unit tests cover authorization, drift and exact failures.
contract InventoryTimelockHandler is Test {
    BurnerLoansInventoryConfigTimelock internal immutable _TIMELOCK;
    BurnerLoansInventory internal immutable _INVENTORY;
    MockERC20 internal immutable _OHM;
    bool internal _pendingBurn;

    uint64 public pendingId;
    uint64 public nextId = 1;
    uint64 public lastTerminalId;
    uint256 public expectedSupply;
    uint256 public expectedTreasuryBalance;

    constructor(
        BurnerLoansInventoryConfigTimelock timelock_,
        BurnerLoansInventory inventory_,
        MockERC20 ohm_
    ) {
        _TIMELOCK = timelock_;
        _INVENTORY = inventory_;
        _OHM = ohm_;
        expectedSupply = ohm_.totalSupply();
    }

    function queueBurn() external {
        if (pendingId != 0 || !_TIMELOCK.isEnabled() || !_INVENTORY.isEnabled()) return;
        pendingId = _TIMELOCK.queueBurnSurplus();
        _pendingBurn = true;
        assertEq(pendingId, nextId++, "Burn consumes the next model ID");
    }

    function queueRescue() external {
        if (pendingId != 0 || !_TIMELOCK.isEnabled()) return;
        pendingId = _TIMELOCK.queueRescueSurplus();
        _pendingBurn = false;
        assertEq(pendingId, nextId++, "Rescue consumes the next model ID");
    }

    function cancel() external {
        if (pendingId == 0 || !_TIMELOCK.isEnabled()) return;
        _TIMELOCK.cancelQueuedAction(pendingId);
        lastTerminalId = pendingId;
        pendingId = 0;
    }

    function execute(uint32 offset_) external {
        if (pendingId == 0 || !_TIMELOCK.isEnabled()) return;
        if (_pendingBurn && !_INVENTORY.isEnabled()) return;
        ITimelockBatchQueue.QueuedAction memory action = _TIMELOCK.getQueuedAction(pendingId);
        if (block.timestamp > action.expiresAt) return;
        uint256 ready = uint256(action.executableAt) + bound(offset_, 0, 3 days);
        vm.warp(ready > block.timestamp ? ready : block.timestamp);

        // Provider backing is fixed at 50 OHM (9 decimals); all excess is recoverable.
        uint256 surplus = _OHM.balanceOf(address(_INVENTORY)) - 50e9;
        if (_pendingBurn) expectedSupply -= surplus;
        else expectedTreasuryBalance += surplus;
        _TIMELOCK.executeQueuedAction(pendingId);
        lastTerminalId = pendingId;
        pendingId = 0;
    }

    function fundSurplus(uint128 amount_) external {
        // Bound the handler's workload, rather than a production input, to 1,000 OHM per step.
        uint256 amount = bound(amount_, 0, 1_000e9);
        _OHM.mint(address(_INVENTORY), amount);
        expectedSupply += amount;
    }

    function advanceTime(uint32 elapsed_) external {
        vm.warp(block.timestamp + bound(elapsed_, 0, 8 days));
    }

    function setTimelockEnabled(bool enabled_) external {
        if (enabled_ == _TIMELOCK.isEnabled()) return;
        if (enabled_) _TIMELOCK.enable("");
        else _TIMELOCK.disable("");
    }

    function setInventoryEnabled(bool enabled_) external {
        if (enabled_ == _INVENTORY.isEnabled()) return;
        if (enabled_) _INVENTORY.enable("");
        else _INVENTORY.disable("");
    }

    function pendingSelector() external view returns (bytes4) {
        return
            _pendingBurn
                ? IBurnerLoansInventory.burnSurplus.selector
                : IBurnerLoansInventory.rescueSurplus.selector;
    }
}

// forge-lint: disable-end(block-timestamp, reentrancy-no-eth)
