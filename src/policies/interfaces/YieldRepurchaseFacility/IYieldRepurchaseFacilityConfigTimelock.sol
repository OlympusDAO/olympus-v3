// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title IYieldRepurchaseFacilityConfigTimelock
/// @notice The interface of the timelock policy that owns the operational parameters of a YRF
///         on behalf of the `yrf_admin` role.
/// @dev Execution is permissionless once the timelock delay elapses and requires only this
///      policy to be enabled.
interface IYieldRepurchaseFacilityConfigTimelock is ITimelockBatchQueue {
    // ========== ERRORS ========== //

    /// @notice Thrown when a constructor argument or a proposed facility slot is the zero
    ///         address.
    /// @param parameter The name of the invalid parameter.
    error IYieldRepurchaseFacilityConfigTimelock_InvalidAddress(string parameter);

    /// @notice Thrown when an action is queued before the facility slot has been set.
    error IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet();

    /// @notice Thrown when a proposed facility is not an active policy of this policy's
    ///         kernel, does not advertise `IYieldRepurchaseFacilityV2` support through
    ///         ERC165, or does not pin this policy as its timelock.
    /// @param facility The rejected facility address.
    error IYieldRepurchaseFacilityConfigTimelock_InvalidFacility(address facility);

    /// @notice Thrown at execution when the facility slot no longer holds the address the
    ///         action was queued against (the slot was rotated between queue and execution).
    ///         The action can be cleared through emergency cancellation and re-queued against
    ///         the new facility.
    /// @param actionId The queued action ID.
    /// @param index The sub-action position within the batch.
    /// @param queuedFacility The facility the action was validated against at queue time.
    /// @param currentFacility The facility the slot currently holds.
    error IYieldRepurchaseFacilityConfigTimelock_FacilityStale(
        uint64 actionId,
        uint256 index,
        address queuedFacility,
        address currentFacility
    );

    /// @notice Thrown at execution when the facility parameter targeted by a sub-action no
    ///         longer matches the value the sub-action was validated against at queue time.
    ///         The action can be cleared through emergency cancellation and re-queued against
    ///         the current value.
    /// @param actionId The queued action ID.
    /// @param index The sub-action position within the batch.
    /// @param expectedHash Hash of the parameter state captured at queue time.
    /// @param currentHash Hash of the live parameter state.
    error IYieldRepurchaseFacilityConfigTimelock_PreStateChanged(
        uint64 actionId,
        uint256 index,
        bytes32 expectedHash,
        bytes32 currentHash
    );

    /// @notice Thrown at queue time when an update of the same facility parameter is already
    ///         pending. The pending slot is released by execution or cancellation, so an
    ///         expired holder must be cancelled by the emergency role to release it.
    /// @param selector The facility function selector of the rejected sub-action.
    /// @param pendingActionId The queued action holding the parameter's pending slot.
    error IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending(
        bytes4 selector,
        uint64 pendingActionId
    );

    /// @notice Thrown when the re-enable grace window is configured with a length at or
    ///         above `MAX_GRACE_PERIOD`.
    error IYieldRepurchaseFacilityConfigTimelock_GracePeriodTooLong();

    // ========== EVENTS ========== //

    /// @notice Emitted when the facility slot is set by the admin.
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

    /// @notice Returns the exclusive upper bound of the re-enable grace window, in seconds:
    ///         the window must be strictly shorter than one weekly cycle of the facility.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_GRACE_PERIOD() external view returns (uint32);

    /// @notice Returns the ID of the queued action holding the pending slot of the vault's
    ///         yield buyback share, or zero if none is pending.
    /// @dev The slot is released only by execution or cancellation, so an expired holder
    ///      keeps blocking new updates of the same parameter until the emergency role
    ///      cancels it.
    /// @param vault_ The vault whose pending slot is queried.
    /// @return actionId The queued action ID, or zero.
    function pendingYieldBuybackShareActionId(
        address vault_
    ) external view returns (uint64 actionId);

    /// @notice Returns the ID of the queued action holding the pending slot of the initial
    ///         discount, or zero if none is pending.
    /// @dev The slot is released only by execution or cancellation, so an expired holder
    ///      keeps blocking new updates of the same parameter until the emergency role
    ///      cancels it.
    /// @return actionId The queued action ID, or zero.
    function pendingInitialDiscountActionId() external view returns (uint64 actionId);

    /// @notice Returns the ID of the queued action holding the pending slot of the max
    ///         price premium, or zero if none is pending.
    /// @dev The slot is released only by execution or cancellation, so an expired holder
    ///      keeps blocking new updates of the same parameter until the emergency role
    ///      cancels it.
    /// @return actionId The queued action ID, or zero.
    function pendingMaxPricePremiumActionId() external view returns (uint64 actionId);

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

    /// @notice Queues a timelocked call to the facility's setter of the max price premium.
    /// @param maxPricePremium_ The new max price premium (`1e18` = 100%); must not
    ///        exceed `10e18`.
    /// @return actionId The queued action ID.
    function queueSetMaxPricePremium(uint256 maxPricePremium_) external returns (uint64 actionId);

    /// @notice Queues a timelocked call to the facility's function to enable the asset.
    /// @param vault_ The vault to re-enable.
    /// @return actionId The queued action ID.
    function queueEnableAsset(address vault_) external returns (uint64 actionId);

    /// @notice Queues a timelocked call to the facility's function to disable the asset.
    /// @param vault_ The vault to disable.
    /// @return actionId The queued action ID.
    function queueDisableAsset(address vault_) external returns (uint64 actionId);

    /// @notice Queues a timelocked call to the facility's function to exclude the
    ///         Clearinghouse from the backing yield.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return actionId The queued action ID.
    function queueExcludeClearinghouse(address clearinghouse_) external returns (uint64 actionId);

    /// @notice Queues a timelocked call to the facility's function to increase the
    ///         receivables offset of the Clearinghouse.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param additionalOffset_ The amount to add to the existing offset.
    /// @return actionId The queued action ID.
    function queueIncreaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external returns (uint64 actionId);

    /// @notice Queues a timelocked call to the facility's function to decrease the
    ///         stored next yield of the vault.
    /// @param vault_ The vault whose next yield is corrected.
    /// @param expectedNextYield_ The stored next-yield value the correction targets.
    /// @param newNextYield_ The corrected next yield; must be lower than the stored value.
    /// @return actionId The queued action ID.
    function queueDecreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external returns (uint64 actionId);

    /// @notice Queues a batch of facility operational actions, stored and executed atomically
    ///         in array order.
    /// @dev Every sub-action must target the facility, use a supported operational selector,
    ///      and pass the same validation as its typed queue helper.
    /// @param actions_ The facility operational sub-actions to queue.
    /// @return actionId The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);

    // ========== CONFIGURATION ========== //

    /// @notice Sets the facility slot this policy manages.
    /// @param facility_ The facility address.
    function setFacility(address facility_) external;

    /// @notice Sets the timelock delay applied to future queued actions.
    /// @param delay_ The new timelock delay, in seconds.
    function setTimelockDelay(uint48 delay_) external;
}
