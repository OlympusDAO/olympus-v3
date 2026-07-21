// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title IYRFManagerTimelock
/// @notice The interface of the timelock policy that owns the operational (manager) parameters
///         of a YRF on behalf of the `yrf_manager` role.
interface IYRFManagerTimelock is ITimelockBatchQueue {
    // ========== ERRORS ========== //

    /// @notice Thrown when a constructor argument or a proposed facility slot is the zero
    ///         address.
    /// @param parameter The name of the invalid parameter.
    error IYRFManagerTimelock_InvalidAddress(string parameter);

    /// @notice Thrown when an action is queued before the facility slot has been set.
    error IYRFManagerTimelock_FacilityNotSet();

    /// @notice Thrown at execution when the facility slot no longer holds the address the
    ///         action was queued against (the slot was rotated between queue and execution).
    ///         The action can be cleared through emergency cancellation and re-queued against
    ///         the new facility.
    /// @param actionId The queued action ID.
    /// @param index The sub-action position within the batch.
    /// @param queuedFacility The facility the action was validated against at queue time.
    /// @param currentFacility The facility the slot currently holds.
    error IYRFManagerTimelock_FacilityStale(
        uint64 actionId,
        uint256 index,
        address queuedFacility,
        address currentFacility
    );

    // ========== EVENTS ========== //

    /// @notice Emitted when the facility slot is set, either in the constructor or by the
    ///         admin.
    /// @param facility The new facility address.
    event FacilitySet(address indexed facility);

    // ========== VIEW ========== //

    /// @notice Returns the address of the YRF this policy manages.
    function facility() external view returns (address);

    /// @notice Returns the minimum accepted timelock delay, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function MIN_TIMELOCK_DELAY() external view returns (uint48);

    /// @notice Returns the maximum accepted timelock delay, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_TIMELOCK_DELAY() external view returns (uint48);

    /// @notice Returns the length of the window after `executableAt` during which a queued
    ///         action may be executed before it expires, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function EXECUTION_WINDOW() external view returns (uint48);

    // ========== QUEUE ========== //

    /// @notice Queues a timelocked call to the facility's setter of the yield buyback share.
    /// @param vault_ The vault whose yield buyback share is set.
    /// @param newShare_ The new yield buyback share (`1e18` = 100%).
    /// @return actionId The queued action ID.
    function queueSetYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external returns (uint64 actionId);

    /// @notice Queues a timelocked call to the facility's setter of the initial discount.
    /// @param initialDiscount_ The new initial bond discount (`1e18` = 100%).
    /// @return actionId The queued action ID.
    function queueSetInitialDiscount(uint256 initialDiscount_) external returns (uint64 actionId);

    /// @notice Queues a timelocked call to the facility's function to enable the asset.
    /// @param vault_ The vault to re-enable.
    /// @return actionId The queued action ID.
    function queueEnableAsset(address vault_) external returns (uint64 actionId);

    // ========== CONFIGURATION ========== //

    /// @notice Sets the facility slot this policy manages.
    /// @param facility_ The facility address.
    function setFacility(address facility_) external;

    /// @notice Sets the timelock delay applied to future queued actions.
    /// @param delay_ The new timelock delay, in seconds.
    function setTimelockDelay(uint48 delay_) external;
}
