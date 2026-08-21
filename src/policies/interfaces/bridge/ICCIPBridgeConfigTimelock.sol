// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title  ICCIPBridgeConfigTimelock
/// @notice The interface of the timelock policy through which the bridge admin role queues
///         typed route, remote pool, allowlist and rate limit changes of a `CCIPBridgeConfig`
///         policy, for permissionless execution after a delay.
/// @dev    Every queued sub-action targets one function of the config policy and is validated at
///         queue time with the config policy's validation mirror of that function. Each
///         sub-action reserves the configuration domains it reads or writes and records their
///         state hashes, so that two unresolved changes of one domain cannot coexist and a change
///         cannot execute after the state it was queued against has moved.
///
///         The domains and their state hashes are:
///         - rate limits of a route: `isEnabled`, `capacity` and `rate` of both buckets, never
///           the fill level or the refill timestamp;
///         - remote pools of a route: the number of accepted remote pools and the XOR of
///           `keccak256(remotePool)` over the raw bytes of each of them;
///         - identity of a route: whether the route exists and its remote token;
///         - the pool-wide allowlist: whether the allowlist is enabled, the number of allowlisted
///           addresses and the XOR of `keccak256(abi.encode(member))` over each of them.
///
///         The two set aggregates are independent of the order in which the pool returns the
///         members, which changes when an entry is removed from the underlying enumerable set.
///         Members are hashed before the XOR and the cardinality is part of the preimage: the
///         preimages are `abi.encode(REMOTE_POOLS_DOMAIN, chainSelector, count, aggregate)` for
///         the remote pools of a route and `abi.encode(ALLOWLIST_DOMAIN, allowListEnabled, count,
///         aggregate)` for the allowlist. The XOR aggregate is not collision resistant against
///         members chosen by an adversary, since XOR is linear: two distinct sets of equal
///         cardinality whose hashed members XOR to the same value collide. It serves as a
///         detector of state drift between queueing and execution and relies on the pool storing
///         both sets as enumerable sets, so that `getRemotePools` and `getAllowList` return each
///         member exactly once and only the pool owner writes them.
///
///         `addChain`, `removeChain` and `setRemoteToken` reserve all three domains of their
///         route; `addRemotePool` and `removeRemotePool` reserve the remote pools domain;
///         `setChainRateLimits` reserves the rate limits domain; and `applyAllowListUpdates`
///         reserves the allowlist domain. Reserved domains are released only by execution or
///         cancellation, so an expired or invalidated action must be cancelled before its domains
///         can be queued again. Queueing does not require the config policy to be enabled, only
///         execution does, so an action queued while the config policy is disabled holds its
///         domains until it executes or is cancelled.
interface ICCIPBridgeConfigTimelock is IConfigTimelockBatchQueue {
    // ========== ERRORS ========== //

    /// @notice Thrown when a constructor argument is the zero address.
    /// @param parameter The name of the invalid parameter.
    error CCIPBridgeConfigTimelock_InvalidAddress(string parameter);

    /// @notice Thrown when the config policy supplied at construction does not advertise the
    ///         `ICCIPBridgeConfig` interface through ERC165.
    /// @param config The rejected config policy address.
    error CCIPBridgeConfigTimelock_InvalidConfig(address config);

    /// @notice Thrown when a configured module has an unsupported major version.
    error CCIPBridgeConfigTimelock_InvalidModuleVersion();

    /// @notice Thrown when the config policy does not name this timelock as its configurator.
    /// @param configurator The configurator currently named by the config policy.
    error CCIPBridgeConfigTimelock_NotConfigurator(address configurator);

    /// @notice Thrown when a state hash is requested for a configuration key that no supported
    ///         action reserves.
    /// @param localKey The unsupported destination-local key.
    error CCIPBridgeConfigTimelock_UnsupportedConfigKey(bytes32 localKey);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the config policy that receives the queued actions.
    /// @return config_ The config policy address.
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

    /// @notice Returns the domain constant of the rate limits of a route.
    // solhint-disable-next-line func-name-mixedcase
    function RATE_LIMITS_DOMAIN() external view returns (bytes32);

    /// @notice Returns the domain constant of the accepted remote pools of a route.
    // solhint-disable-next-line func-name-mixedcase
    function REMOTE_POOLS_DOMAIN() external view returns (bytes32);

    /// @notice Returns the domain constant of the identity of a route.
    // solhint-disable-next-line func-name-mixedcase
    function ROUTE_IDENTITY_DOMAIN() external view returns (bytes32);

    /// @notice Returns the domain constant of the pool-wide sender allowlist.
    // solhint-disable-next-line func-name-mixedcase
    function ALLOWLIST_DOMAIN() external view returns (bytes32);

    /// @notice Returns the reserved key of the rate limits domain of a route, as used by
    ///         `pendingActionId`.
    /// @param chainSelector_ The chain selector of the route.
    /// @return key The destination-scoped key.
    function getRateLimitsKey(uint64 chainSelector_) external view returns (bytes32 key);

    /// @notice Returns the reserved key of the remote pools domain of a route, as used by
    ///         `pendingActionId`.
    /// @param chainSelector_ The chain selector of the route.
    /// @return key The destination-scoped key.
    function getRemotePoolsKey(uint64 chainSelector_) external view returns (bytes32 key);

    /// @notice Returns the reserved key of the identity domain of a route, as used by
    ///         `pendingActionId`.
    /// @param chainSelector_ The chain selector of the route.
    /// @return key The destination-scoped key.
    function getRouteIdentityKey(uint64 chainSelector_) external view returns (bytes32 key);

    /// @notice Returns the reserved key of the allowlist domain, as used by `pendingActionId`.
    /// @return key The destination-scoped key.
    function getAllowListKey() external view returns (bytes32 key);

    // ========== QUEUE FUNCTIONS ========== //

    /// @notice Queues an `addChain` call on the config policy. Intended to be callable only by
    ///         the bridge admin role while the timelock is enabled and named as configurator.
    /// @param update_ The chain configuration to add.
    /// @return actionId The queued action ID.
    function queueAddChain(
        ICCIPTokenPoolAdmin.ChainUpdate calldata update_
    ) external returns (uint64 actionId);

    /// @notice Queues a `removeChain` call on the config policy. Intended to be callable only by
    ///         the bridge admin role while the timelock is enabled and named as configurator.
    /// @param chainSelector_ The chain selector of the route.
    /// @return actionId The queued action ID.
    function queueRemoveChain(uint64 chainSelector_) external returns (uint64 actionId);

    /// @notice Queues a `setRemoteToken` call on the config policy. Intended to be callable only
    ///         by the bridge admin role while the timelock is enabled and named as configurator.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remoteToken_ The new remote token address.
    /// @return actionId The queued action ID.
    function queueSetRemoteToken(
        uint64 chainSelector_,
        bytes calldata remoteToken_
    ) external returns (uint64 actionId);

    /// @notice Queues an `addRemotePool` call on the config policy. Intended to be callable only
    ///         by the bridge admin role while the timelock is enabled and named as configurator.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remotePool_ The remote pool address to add.
    /// @return actionId The queued action ID.
    function queueAddRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external returns (uint64 actionId);

    /// @notice Queues a `removeRemotePool` call on the config policy. Intended to be callable
    ///         only by the bridge admin role while the timelock is enabled and named as
    ///         configurator.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remotePool_ The remote pool address to remove.
    /// @return actionId The queued action ID.
    function queueRemoveRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external returns (uint64 actionId);

    /// @notice Queues an `applyAllowListUpdates` call on the config policy. Intended to be
    ///         callable only by the bridge admin role while the timelock is enabled and named as
    ///         configurator.
    /// @param removes_ The addresses to remove.
    /// @param adds_ The addresses to add.
    /// @return actionId The queued action ID.
    function queueApplyAllowListUpdates(
        address[] calldata removes_,
        address[] calldata adds_
    ) external returns (uint64 actionId);

    /// @notice Queues a `setChainRateLimits` call on the config policy. Intended to be callable
    ///         only by the bridge admin role while the timelock is enabled and named as
    ///         configurator.
    /// @param chainSelector_ The chain selector of the route.
    /// @param outbound_ The outbound rate limiter configuration.
    /// @param inbound_ The inbound rate limiter configuration.
    /// @return actionId The queued action ID.
    function queueSetChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config calldata outbound_,
        ICCIPRateLimiter.Config calldata inbound_
    ) external returns (uint64 actionId);

    /// @notice Queues a batch of config policy calls that executes atomically in array order.
    ///         Every sub-action must target the config policy with one of the supported
    ///         selectors and a canonically encoded payload. Intended to be callable only by the
    ///         bridge admin role while the timelock is enabled and named as configurator.
    /// @param actions_ The sub-actions to queue.
    /// @return actionId The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);

    // ========== CONFIGURATION ========== //

    /// @notice Sets the delay applied to actions queued afterwards. Already queued actions keep
    ///         their stored timestamps. Intended to be callable only by the admin role while the
    ///         timelock is enabled.
    /// @param delay_ The new delay, in seconds, within the accepted bounds.
    function setTimelockDelay(uint48 delay_) external;
}
