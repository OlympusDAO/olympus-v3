// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

/// @title  ICCIPBridgeConfig
/// @notice The interface of the policy that owns the local Chainlink CCIP token pool of OHM and
///         exposes a typed, role-separated subset of the pool owner's authority.
/// @dev    The policy is bound to one pool for its lifetime. Its functions form four groups:
///         admin functions that change root authority and pool infrastructure; route functions
///         that change the supported chains, remote pools and allowlist, callable by the config
///         operator or the admin; the rate limit function, additionally callable by the bridge
///         rate limiter role; and containment functions, callable by the emergency or admin
///         role, that only reduce capacity and remain callable while the policy is disabled.
///         Every other state-changing function requires the policy to be enabled.
///
///         The config operator is the delegated operator of `IConfigOperator`: `configOperator`
///         returns it, or the zero address when none is set, and `setConfigOperator` replaces it
///         immediately or revokes it with the zero address; the setter is intended to be callable
///         only by the admin role while the policy is enabled. It is meant to be the config
///         timelock.
///
///         Amounts, capacities and rates are expressed in the smallest unit of the pool token.
///         Remote addresses are ABI-encoded for EVM chains and encoded per the remote chain
///         family otherwise. Every operation on the pool is emitted by this contract in addition
///         to the events that the pool emits itself.
interface ICCIPBridgeConfig is IConfigOperator {
    // ========== ERRORS ========== //

    /// @notice Thrown when a required address argument is the zero address.
    /// @param parameter The name of the invalid parameter.
    error CCIPBridgeConfig_InvalidAddress(string parameter);

    /// @notice Thrown when the pool supplied at construction does not advertise the CCIP v1
    ///         pool identifier `Pool.CCIP_POOL_V1` (`0xaff2afbf`) through ERC165, the identifier
    ///         that the CCIP on-ramp and off-ramp check before calling a pool.
    /// @param pool The rejected pool address.
    error CCIPBridgeConfig_InvalidPool(address pool);

    /// @notice Thrown when a configured module has an unsupported major version.
    error CCIPBridgeConfig_InvalidModuleVersion();

    /// @notice Thrown when a router candidate holds no code or does not answer
    ///         `typeAndVersion()`.
    /// @param router The rejected router address.
    error CCIPBridgeConfig_InvalidRouter(address router);

    /// @notice Thrown when a liquidity function is called and the pool does not advertise the
    ///         liquidity container interface.
    error CCIPBridgeConfig_NotLiquidityContainer();

    /// @notice Thrown when a liquidity transfer amount is zero.
    error CCIPBridgeConfig_ZeroAmount();

    /// @notice Thrown when a chain is added without any remote pool.
    error CCIPBridgeConfig_RemotePoolsEmpty();

    /// @notice Thrown when the remote token to set for a route is empty.
    error CCIPBridgeConfig_RemoteTokenEmpty();

    /// @notice Thrown when the remote token to set for a route equals its current remote token.
    error CCIPBridgeConfig_RemoteTokenUnchanged();

    /// @notice Thrown when a supplied or current rate limiter configuration is disabled.
    ///         Every route served by the pool carries enabled limiters in both directions.
    error CCIPBridgeConfig_RateLimiterDisabled();

    /// @notice Thrown when the removal of a remote pool would leave the route without any
    ///         accepted remote pool.
    /// @param chainSelector The chain selector of the route.
    error CCIPBridgeConfig_LastRemotePool(uint64 chainSelector);

    /// @notice Thrown when an allowlist update contains neither removals nor additions.
    error CCIPBridgeConfig_AllowListUpdatesEmpty();

    // ========== EVENTS ========== //

    /// @notice Emitted when the policy accepts ownership of the pool.
    /// @param pool The pool.
    event PoolOwnershipAccepted(address indexed pool);

    /// @notice Emitted when the policy proposes a new owner of the pool.
    /// @param newOwner The proposed owner.
    event PoolOwnershipTransferRequested(address indexed newOwner);

    /// @notice Emitted when the pool router is set.
    /// @param router The router.
    event PoolRouterSet(address indexed router);

    /// @notice Emitted when the pool rebalancer is set.
    /// @param rebalancer The rebalancer, or the zero address if cleared.
    event PoolRebalancerSet(address indexed rebalancer);

    /// @notice Emitted when the pool rate limit admin is set.
    /// @param rateLimitAdmin The rate limit admin, or the zero address if cleared.
    event PoolRateLimitAdminSet(address indexed rateLimitAdmin);

    /// @notice Emitted when liquidity is pulled from another pool into the pool.
    /// @param from The pool the liquidity was pulled from.
    /// @param amount The amount transferred.
    event PoolLiquidityTransferred(address indexed from, uint256 amount);

    /// @notice Emitted when a route is added.
    /// @param chainSelector The chain selector of the route.
    /// @param update The chain configuration added.
    event RouteAdded(uint64 indexed chainSelector, ICCIPTokenPoolAdmin.ChainUpdate update);

    /// @notice Emitted when a route is removed.
    /// @param chainSelector The chain selector of the route.
    event RouteRemoved(uint64 indexed chainSelector);

    /// @notice Emitted when the remote token of a route is set.
    /// @param chainSelector The chain selector of the route.
    /// @param previousRemoteToken The remote token before the change.
    /// @param remoteToken The remote token after the change.
    event RemoteTokenSet(
        uint64 indexed chainSelector,
        bytes previousRemoteToken,
        bytes remoteToken
    );

    /// @notice Emitted when a remote pool is added to a route.
    /// @param chainSelector The chain selector of the route.
    /// @param remotePool The remote pool address added.
    event RouteRemotePoolAdded(uint64 indexed chainSelector, bytes remotePool);

    /// @notice Emitted when a remote pool is removed from a route.
    /// @param chainSelector The chain selector of the route.
    /// @param remotePool The remote pool address removed.
    event RouteRemotePoolRemoved(uint64 indexed chainSelector, bytes remotePool);

    /// @notice Emitted when the sender allowlist of the pool is updated.
    /// @param removes The addresses removed.
    /// @param adds The addresses added.
    event AllowListUpdated(address[] removes, address[] adds);

    /// @notice Emitted when the rate limits of a route are set.
    /// @param chainSelector The chain selector of the route.
    /// @param previousOutbound The outbound configuration before the change.
    /// @param previousInbound The inbound configuration before the change.
    /// @param outbound The outbound configuration after the change.
    /// @param inbound The inbound configuration after the change.
    event RouteRateLimitsSet(
        uint64 indexed chainSelector,
        ICCIPRateLimiter.Config previousOutbound,
        ICCIPRateLimiter.Config previousInbound,
        ICCIPRateLimiter.Config outbound,
        ICCIPRateLimiter.Config inbound
    );

    /// @notice Emitted when a route is contained by setting both of its buckets to the disabled
    ///         rate limiter configuration.
    /// @param chainSelector The chain selector of the route.
    event RouteDisabled(uint64 indexed chainSelector);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the token pool owned by this policy.
    /// @return pool_ The pool address.
    function pool() external view returns (address pool_);

    /// @notice Returns whether the pool advertises the liquidity container interface, which
    ///         enables `setRebalancer` and `transferLiquidity`.
    /// @return isContainer True if the pool is a liquidity container.
    function isLiquidityContainer() external view returns (bool isContainer);

    /// @notice Returns the rate limiter configuration written to both buckets of a route by the
    ///         containment functions. At this capacity every real transfer exceeds the bucket
    ///         size and fails immediately.
    /// @return config The disabled rate limiter configuration.
    function getDisabledRateLimiterConfig()
        external
        pure
        returns (ICCIPRateLimiter.Config memory config);

    /// @notice Returns whether both buckets of a configured route hold the disabled rate limiter
    ///         configuration. Only `isEnabled`, `capacity` and `rate` are compared. A route with
    ///         exactly one contained bucket is reported as not disabled.
    /// @param chainSelector_ The chain selector of the route.
    /// @return disabled True if both buckets are contained.
    function isChainDisabled(uint64 chainSelector_) external view returns (bool disabled);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Accepts a pending transfer of the pool ownership to this policy. Intended to be
    ///         callable only by the admin role while the policy is enabled.
    function acceptPoolOwnership() external;

    /// @notice Proposes a new owner of the pool. Ownership moves only when the proposed owner
    ///         accepts, and a later proposal overwrites a pending one. Intended to be callable
    ///         only by the admin role while the policy is enabled.
    /// @param newOwner_ The proposed owner.
    function transferPoolOwnership(address newOwner_) external;

    /// @notice Sets the router of the pool after checking that the candidate holds code and
    ///         answers `typeAndVersion()`. Intended to be callable only by the admin role while
    ///         the policy is enabled.
    /// @param router_ The router address.
    function setRouter(address router_) external;

    /// @notice Sets the rebalancer of a liquidity container pool. The zero address clears the
    ///         rebalancer. Intended to be callable only by the admin role while the policy is
    ///         enabled.
    /// @param rebalancer_ The rebalancer address.
    function setRebalancer(address rebalancer_) external;

    /// @notice Sets the rate limit admin of the pool. The zero address clears the role. Intended
    ///         to be callable only by the admin role while the policy is enabled.
    /// @param rateLimitAdmin_ The rate limit admin address.
    function setRateLimitAdmin(address rateLimitAdmin_) external;

    /// @notice Pulls liquidity from another lock/release pool into the pool. The pool must be
    ///         the rebalancer of `from_`. Intended to be callable only by the admin role while
    ///         the policy is enabled.
    /// @param from_ The pool to pull liquidity from.
    /// @param amount_ The amount to transfer.
    function transferLiquidity(address from_, uint256 amount_) external;

    // ========== ROUTE FUNCTIONS ========== //

    /// @notice Adds a route with its remote token, accepted remote pools and enabled rate limits
    ///         in both directions. Both buckets start full. Intended to be callable only by the
    ///         config operator or the admin role while the policy is enabled.
    /// @param update_ The chain configuration to add.
    function addChain(ICCIPTokenPoolAdmin.ChainUpdate calldata update_) external;

    /// @notice Removes a route together with its remote pools, remote token and both buckets.
    ///         In-flight messages from the route are rejected afterwards. Intended to be
    ///         callable only by the config operator or the admin role while the policy is enabled.
    /// @param chainSelector_ The chain selector of the route.
    function removeChain(uint64 chainSelector_) external;

    /// @notice Sets the remote token of a route. The pool has no update path for the remote
    ///         token, so the route is recreated: it is removed and re-added in one pool call with
    ///         the same remote pools and rate limiter configurations, after which the fill level
    ///         of both buckets is restored to its level before the replacement, with a floor of
    ///         two units. Intended to be callable only by the config operator or the admin role
    ///         while the policy is enabled.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remoteToken_ The new remote token address.
    function setRemoteToken(uint64 chainSelector_, bytes calldata remoteToken_) external;

    /// @notice Adds an accepted remote pool to a route. Previously accepted pools remain
    ///         accepted. Intended to be callable only by the config operator or the admin role while
    ///         the policy is enabled.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remotePool_ The remote pool address to add.
    function addRemotePool(uint64 chainSelector_, bytes calldata remotePool_) external;

    /// @notice Removes an accepted remote pool from a route. The last accepted pool of a route
    ///         cannot be removed. In-flight messages from the removed pool are rejected
    ///         afterwards. Intended to be callable only by the config operator or the admin role
    ///         while the policy is enabled.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remotePool_ The remote pool address to remove.
    function removeRemotePool(uint64 chainSelector_, bytes calldata remotePool_) external;

    /// @notice Removes and then adds sender allowlist entries on a pool deployed with an
    ///         allowlist. Intended to be callable only by the config operator or the admin role
    ///         while the policy is enabled.
    /// @param removes_ The addresses to remove.
    /// @param adds_ The addresses to add.
    function applyAllowListUpdates(address[] calldata removes_, address[] calldata adds_) external;

    // ========== RATE LIMIT FUNCTIONS ========== //

    /// @notice Sets both rate limiter configurations of a route together. Both configurations
    ///         must be enabled. The fill level of each bucket is clamped to the new capacity and
    ///         is never raised. Intended to be callable only by the bridge rate limiter role, the
    ///         config operator or the admin role while the policy is enabled.
    /// @param chainSelector_ The chain selector of the route.
    /// @param outbound_ The outbound rate limiter configuration.
    /// @param inbound_ The inbound rate limiter configuration.
    function setChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config calldata outbound_,
        ICCIPRateLimiter.Config calldata inbound_
    ) external;

    // ========== CONTAINMENT FUNCTIONS ========== //

    /// @notice Sets both buckets of a route to the disabled rate limiter configuration. Safe to
    ///         call on a route that is already contained. Intended to be callable only by the
    ///         emergency or admin role, whether or not the policy is enabled.
    /// @param chainSelector_ The chain selector of the route.
    function disableChain(uint64 chainSelector_) external;

    /// @notice Sets both buckets of every configured route to the disabled rate limiter
    ///         configuration. Does nothing when no route is configured. Intended to be callable
    ///         only by the emergency or admin role, whether or not the policy is enabled.
    function disableAllChains() external;

    // ========== VALIDATION FUNCTIONS ========== //

    /// @notice Validates the arguments of `addChain` against the live pool state, with the same
    ///         checks and errors as the state-changing call, and returns without effect when
    ///         they are valid.
    /// @param update_ The chain configuration to validate.
    function validateAddChain(ICCIPTokenPoolAdmin.ChainUpdate calldata update_) external view;

    /// @notice Validates the arguments of `removeChain` against the live pool state, with the
    ///         same checks and errors as the state-changing call, and returns without effect
    ///         when they are valid.
    /// @param chainSelector_ The chain selector of the route.
    function validateRemoveChain(uint64 chainSelector_) external view;

    /// @notice Validates the arguments of `setRemoteToken` against the live pool state, with the
    ///         same checks and errors as the state-changing call, and returns without effect
    ///         when they are valid.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remoteToken_ The new remote token address.
    function validateSetRemoteToken(
        uint64 chainSelector_,
        bytes calldata remoteToken_
    ) external view;

    /// @notice Validates the arguments of `addRemotePool` against the live pool state, with the
    ///         same checks and errors as the state-changing call, and returns without effect
    ///         when they are valid.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remotePool_ The remote pool address to add.
    function validateAddRemotePool(uint64 chainSelector_, bytes calldata remotePool_) external view;

    /// @notice Validates the arguments of `removeRemotePool` against the live pool state, with
    ///         the same checks and errors as the state-changing call, and returns without effect
    ///         when they are valid.
    /// @param chainSelector_ The chain selector of the route.
    /// @param remotePool_ The remote pool address to remove.
    function validateRemoveRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external view;

    /// @notice Validates the arguments of `applyAllowListUpdates` against the live pool state,
    ///         with the same checks and errors as the state-changing call, and returns without
    ///         effect when they are valid.
    /// @param removes_ The addresses to remove.
    /// @param adds_ The addresses to add.
    function validateApplyAllowListUpdates(
        address[] calldata removes_,
        address[] calldata adds_
    ) external view;

    /// @notice Validates the arguments of `setChainRateLimits` against the live pool state, with
    ///         the same checks and errors as the state-changing call, and returns without effect
    ///         when they are valid.
    /// @param chainSelector_ The chain selector of the route.
    /// @param outbound_ The outbound rate limiter configuration.
    /// @param inbound_ The inbound rate limiter configuration.
    function validateSetChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config calldata outbound_,
        ICCIPRateLimiter.Config calldata inbound_
    ) external view;
}
