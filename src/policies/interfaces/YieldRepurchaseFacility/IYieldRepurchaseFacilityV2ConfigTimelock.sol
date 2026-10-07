// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title IYieldRepurchaseFacilityV2ConfigTimelock
/// @notice The interface of the timelock policy through which the yrf_admin role queues the
///         operator setters of `IYieldRepurchaseFacilityV2Config`, for permissionless execution
///         after a delay.
/// @dev Every queued sub-action targets one operator setter of the configuration policy and is
///      validated at queue time with the facility's validation mirror of the forwarded
///      function. Each sub-action reserves the configuration domains it reads or writes and
///      records their state hashes, so that two unresolved changes of one domain cannot
///      coexist and a change cannot execute after the state it was queued against has moved.
///      The state is read from the facility bound to the configuration policy, which holds no
///      configuration of its own.
///
///      The domains, their destination-local keys, and the preimages of their state hashes
///      are, with `facility` the facility bound to the configuration policy:
///      - the initial discount: key `INITIAL_DISCOUNT_DOMAIN`, preimage
///        `abi.encode(INITIAL_DISCOUNT_DOMAIN, facility, initialDiscount)`;
///      - the max price premium: key `MAX_PRICE_PREMIUM_DOMAIN`, preimage
///        `abi.encode(MAX_PRICE_PREMIUM_DOMAIN, facility, maxPricePremium)`;
///      - the yield buyback share of a vault: key
///        `keccak256(abi.encode(YIELD_BUYBACK_SHARE_DOMAIN, vault))`, preimage
///        `abi.encode(YIELD_BUYBACK_SHARE_DOMAIN, facility, vault, yieldBuybackShare)`;
///      - the status of a vault: key `keccak256(abi.encode(ASSET_STATUS_DOMAIN, vault))`,
///        preimage `abi.encode(ASSET_STATUS_DOMAIN, facility, vault, isAssetEnabled,
///        isBackingVault)`, where `isBackingVault` is whether the vault is the backing vault;
///      - the stored next yield of a vault: key
///        `keccak256(abi.encode(NEXT_YIELD_DOMAIN, vault))`, preimage
///        `abi.encode(NEXT_YIELD_DOMAIN, facility, vault, nextYield)`;
///      - the receivables offset of a Clearinghouse: key
///        `keccak256(abi.encode(CLEARINGHOUSE_OFFSET_DOMAIN, clearinghouse))`, preimage
///        `abi.encode(CLEARINGHOUSE_OFFSET_DOMAIN, facility, clearinghouse, offset)`;
///      - the inclusion of a Clearinghouse: key
///        `keccak256(abi.encode(CLEARINGHOUSE_INCLUSION_DOMAIN, clearinghouse))`, preimage
///        `abi.encode(CLEARINGHOUSE_INCLUSION_DOMAIN, facility, clearinghouse, isIncluded)`.
///
///      `setInitialDiscount` and `setMaxPricePremium` reserve their global domain;
///      `setYieldBuybackShare` the share domain of its vault; `disableAsset` the status domain
///      of its vault; `enableAsset` the status and the next yield domains of its vault, since
///      it zeroes the stored next yield; `decreaseNextYield` the next yield domain of its
///      vault; `increaseClearinghouseOffset` the offset domain of its Clearinghouse; and
///      `excludeClearinghouse` the inclusion domain of its Clearinghouse. The hashes exclude
///      the live `principalReceivables` a Clearinghouse offset is validated against and the
///      yield snapshots: both move during normal operation, and the facility validates the
///      offset against the live receivables when the action executes.
///
///      A reserved key is scoped to the configuration policy:
///      `keccak256(abi.encode(config, localKey))`, the formula of `ConfigTimelockKeyLib`, with
///      the domain constants exposed below. Reserved domains are released only by execution or
///      cancellation, so an expired or stale action must be cancelled before its domains can
///      be queued again. A direct admin change through the configuration policy of a guarded
///      field makes the queued action stale, and so does a de-registration of its vault: the
///      state read of a de-registered vault reverts, so the action cannot execute and holds its
///      domains until it is cancelled. A vault that is de-registered and registered again
///      between queueing and execution is not distinguished from its original registration:
///      the hashes read only the guarded fields, so an action whose guarded fields match the
///      new registration executes against it.
///
///      Queueing requires this policy and the configuration policy to be enabled, the caller to
///      hold the yrf_admin role, and the configuration policy to name this policy as its
///      config operator. Execution is permissionless once the delay elapses and requires the
///      same enabled states and the config operator binding; the facility itself may be
///      disabled, since its configuration setters apply while it is disabled. Cancellation is
///      restricted to the emergency role and is available while this policy is disabled and
///      after the action has expired. Enabling and re-enabling this policy require the
///      configuration policy to be an active policy of this policy's kernel, and the grace
///      window of `reEnable` must be strictly shorter than `MAX_GRACE_PERIOD`.
///
///      The queue itself (`executeQueuedAction`, `cancelQueuedAction`, the stored actions,
///      `pendingActionId` and the other reservation views) is the `IConfigTimelockBatchQueue`
///      surface of the shared base, which the implementing contract exposes as a separate
///      interface next to this one; a caller holding this interface casts to it for those
///      functions, as it does to `IEnabler` for the lifecycle.
interface IYieldRepurchaseFacilityV2ConfigTimelock {
    // ============ ERRORS ============ //

    /// @notice Thrown when the configuration policy supplied at construction is the zero
    ///         address or does not advertise `IYieldRepurchaseFacilityV2Config`,
    ///         `IConfigOperator`, and `IEnabler` through ERC165.
    /// @param config The rejected configuration policy address.
    error IYieldRepurchaseFacilityV2ConfigTimelock_InvalidConfig(address config);

    /// @notice Thrown when the configuration policy supplied at construction reports a kernel
    ///         other than the kernel of this policy.
    /// @param configKernel The kernel reported by the configuration policy.
    error IYieldRepurchaseFacilityV2ConfigTimelock_KernelMismatch(address configKernel);

    /// @notice Thrown when this policy is enabled or re-enabled while the configuration policy
    ///         is not an active policy of this policy's kernel.
    /// @param config The configuration policy address.
    error IYieldRepurchaseFacilityV2ConfigTimelock_ConfigNotActive(address config);

    /// @notice Thrown when the configuration policy does not name this policy as its config
    ///         operator.
    /// @param configOperator The config operator currently named by the configuration policy,
    ///        or the zero address when none is set.
    error IYieldRepurchaseFacilityV2ConfigTimelock_NotConfigOperator(address configOperator);

    /// @notice Thrown when a state hash is requested for a configuration key that no supported
    ///         action reserves.
    /// @param localKey The unsupported destination-local key.
    error IYieldRepurchaseFacilityV2ConfigTimelock_UnsupportedConfigKey(bytes32 localKey);

    /// @notice Thrown when the re-enable grace window is configured with a length at or
    ///         above `MAX_GRACE_PERIOD`.
    error IYieldRepurchaseFacilityV2ConfigTimelock_GracePeriodTooLong();

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the configuration policy that receives the queued actions.
    /// @return config_ The configuration policy address.
    function config() external view returns (address config_);

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
    /// @return The bound, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_GRACE_PERIOD() external view returns (uint32);

    /// @notice Returns the domain constant of the initial discount, which is also its
    ///         destination-local key.
    /// @return domain The domain constant.
    // solhint-disable-next-line func-name-mixedcase
    function INITIAL_DISCOUNT_DOMAIN() external view returns (bytes32 domain);

    /// @notice Returns the domain constant of the max price premium, which is also its
    ///         destination-local key.
    /// @return domain The domain constant.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_PRICE_PREMIUM_DOMAIN() external view returns (bytes32 domain);

    /// @notice Returns the domain constant of the yield buyback share of a vault.
    /// @return domain The domain constant.
    // solhint-disable-next-line func-name-mixedcase
    function YIELD_BUYBACK_SHARE_DOMAIN() external view returns (bytes32 domain);

    /// @notice Returns the domain constant of the status of a vault: whether the asset is
    ///         enabled and whether it is the backing vault.
    /// @return domain The domain constant.
    // solhint-disable-next-line func-name-mixedcase
    function ASSET_STATUS_DOMAIN() external view returns (bytes32 domain);

    /// @notice Returns the domain constant of the stored next yield of a vault.
    /// @return domain The domain constant.
    // solhint-disable-next-line func-name-mixedcase
    function NEXT_YIELD_DOMAIN() external view returns (bytes32 domain);

    /// @notice Returns the domain constant of the receivables offset of a Clearinghouse.
    /// @return domain The domain constant.
    // solhint-disable-next-line func-name-mixedcase
    function CLEARINGHOUSE_OFFSET_DOMAIN() external view returns (bytes32 domain);

    /// @notice Returns the domain constant of the inclusion of a Clearinghouse in the backing
    ///         yield.
    /// @return domain The domain constant.
    // solhint-disable-next-line func-name-mixedcase
    function CLEARINGHOUSE_INCLUSION_DOMAIN() external view returns (bytes32 domain);

    // ============ QUEUE FUNCTIONS ============ //

    /// @notice Queues a `setYieldBuybackShare` call on the configuration policy. Intended to be
    ///         callable only by the yrf_admin role while the timelock is enabled and named as
    ///         config operator.
    /// @param vault_ The registered vault.
    /// @param newShare_ The new share (`1e18` = 100%); must not exceed `1e18`.
    /// @return actionId The queued action ID.
    function queueSetYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external returns (uint64 actionId);

    /// @notice Queues a `setInitialDiscount` call on the configuration policy. Intended to be
    ///         callable only by the yrf_admin role while the timelock is enabled and named as
    ///         config operator.
    /// @param initialDiscount_ The new discount (`1e18` = 100%); must be less than `1e18`.
    /// @return actionId The queued action ID.
    function queueSetInitialDiscount(uint256 initialDiscount_) external returns (uint64 actionId);

    /// @notice Queues a `setMaxPricePremium` call on the configuration policy. Intended to be
    ///         callable only by the yrf_admin role while the timelock is enabled and named as
    ///         config operator.
    /// @param maxPricePremium_ The new premium (`1e18` = 100%); must not exceed `10e18`.
    /// @return actionId The queued action ID.
    function queueSetMaxPricePremium(uint256 maxPricePremium_) external returns (uint64 actionId);

    /// @notice Queues an `increaseClearinghouseOffset` call on the configuration policy.
    ///         Intended to be callable only by the yrf_admin role while the timelock is enabled
    ///         and named as config operator.
    /// @dev The resulting offset is validated against the live `principalReceivables` at queue
    ///      time and again when the action executes.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param additionalOffset_ The amount added to the existing offset, in the receivables'
    ///        units.
    /// @return actionId The queued action ID.
    function queueIncreaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external returns (uint64 actionId);

    /// @notice Queues a `decreaseNextYield` call on the configuration policy. Intended to be
    ///         callable only by the yrf_admin role while the timelock is enabled and named as
    ///         config operator.
    /// @dev The stored next yield must equal `expectedNextYield_` at queue time and when the
    ///      action executes: a weekly reset that replaces the stored value in between makes the
    ///      action stale.
    /// @param vault_ The registered vault.
    /// @param expectedNextYield_ The stored next yield the correction targets, in reserve units.
    /// @param newNextYield_ The corrected next yield, in reserve units; must be lower than the
    ///        stored value.
    /// @return actionId The queued action ID.
    function queueDecreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external returns (uint64 actionId);

    /// @notice Queues an `excludeClearinghouse` call on the configuration policy. Intended to be
    ///         callable only by the yrf_admin role while the timelock is enabled and named as
    ///         config operator.
    /// @param clearinghouse_ The included Clearinghouse address.
    /// @return actionId The queued action ID.
    function queueExcludeClearinghouse(address clearinghouse_) external returns (uint64 actionId);

    /// @notice Queues an `enableAsset` call on the configuration policy. Intended to be callable
    ///         only by the yrf_admin role while the timelock is enabled and named as config
    ///         operator.
    /// @param vault_ The vault to enable.
    /// @return actionId The queued action ID.
    function queueEnableAsset(address vault_) external returns (uint64 actionId);

    /// @notice Queues a `disableAsset` call on the configuration policy. Intended to be callable
    ///         only by the yrf_admin role while the timelock is enabled and named as config
    ///         operator.
    /// @param vault_ The vault to disable.
    /// @return actionId The queued action ID.
    function queueDisableAsset(address vault_) external returns (uint64 actionId);

    /// @notice Queues a batch of configuration policy calls that executes atomically in array
    ///         order. Every sub-action must target the configuration policy with one of the
    ///         supported operator setters and a canonically encoded payload. Intended to be
    ///         callable only by the yrf_admin role while the timelock is enabled and named as
    ///         config operator.
    /// @dev Every sub-action is validated against the live state at queue time: the effect of
    ///      an earlier sub-action is not projected onto the validation of a later one.
    /// @param actions_ The sub-actions to queue.
    /// @return actionId The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);

    // ============ CONFIGURATION ============ //

    /// @notice Sets the delay applied to actions queued afterwards. Already queued actions keep
    ///         their stored timestamps. Intended to be callable only by the admin role, whether
    ///         or not the timelock is enabled.
    /// @param delay_ The new delay, in seconds, within the accepted bounds.
    function setTimelockDelay(uint48 delay_) external;
}
