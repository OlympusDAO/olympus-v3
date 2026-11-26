// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

/// @notice Delayed surplus recovery for one immutable Inventory target.
/// @dev Proposals accept ADMIN or Burner Loans admin. Cap updates and mint-approval sync are not queued.
interface IBurnerLoansInventoryConfigTimelock {
    /// @notice The Inventory target lacks a required interface or reports another Kernel.
    /// @param inventory Invalid target.
    error BurnerLoansInventoryTimelock_InvalidInventory(address inventory);

    /// @notice Target reverted without safely propagatable bounded revert data.
    /// @param selector Failed Inventory operation.
    error BurnerLoansInventoryTimelock_SubActionCallFailed(bytes4 selector);

    /// @notice Returns the immutable target, independent of Core's Inventory selection.
    /// @return target Inventory receiving delayed calls.
    function inventory() external view returns (IBurnerLoansInventory target);

    /// @notice Queues burning all live OHM surplus; supplied idle remains protected.
    /// @return actionId Queued operation identifier.
    function queueBurnSurplus() external returns (uint64 actionId);

    /// @notice Queues transfer of all live OHM surplus to Inventory's Treasury.
    /// @dev Inventory may be locally disabled; no balance is reserved at queue time.
    /// @return actionId Queued operation identifier.
    function queueRescueSurplus() external returns (uint64 actionId);
}
