// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolGetters} from "src/external/bridge/ICCIPTokenPoolGetters.sol";

/// @title ICCIPTokenPoolAdmin
/// @notice The owner-facing surface of a Chainlink CCIP `TokenPool` (version 1.5.1), together
///         with the pool events and errors and the view surface inherited from
///         `ICCIPTokenPoolGetters`.
/// @dev The `ChainUpdate` struct layout is identical to `TokenPool.ChainUpdate` of Chainlink CCIP
///      1.6.0, so `applyChainUpdates` and `setChainRateLimiterConfig` declared here have the same
///      selectors as the pool functions. Every state-changing function is restricted to the pool
///      owner, except the rate limiter setters, which also accept the pool's rate limit admin.
///      Remote addresses are ABI-encoded for EVM chains and encoded per the remote chain family
///      otherwise.
interface ICCIPTokenPoolAdmin is ICCIPTokenPoolGetters {
    // ========== DATA STRUCTURES ========== //

    /// @notice A remote chain to add to the pool.
    /// @param remoteChainSelector The CCIP chain selector of the remote chain.
    /// @param remotePoolAddresses The pool addresses on the remote chain accepted as message
    ///        sources.
    /// @param remoteTokenAddress The token address on the remote chain.
    /// @param outboundRateLimiterConfig The rate limiter configuration for transfers to the
    ///        remote chain.
    /// @param inboundRateLimiterConfig The rate limiter configuration for transfers from the
    ///        remote chain.
    struct ChainUpdate {
        uint64 remoteChainSelector;
        bytes[] remotePoolAddresses;
        bytes remoteTokenAddress;
        ICCIPRateLimiter.Config outboundRateLimiterConfig;
        ICCIPRateLimiter.Config inboundRateLimiterConfig;
    }

    // ========== EVENTS ========== //

    /// @notice Emitted when tokens are locked in the pool.
    /// @param sender The calling on-ramp.
    /// @param amount The amount locked.
    event Locked(address indexed sender, uint256 amount);

    /// @notice Emitted when tokens are burned by the pool.
    /// @param sender The calling on-ramp.
    /// @param amount The amount burned.
    event Burned(address indexed sender, uint256 amount);

    /// @notice Emitted when tokens are released by the pool.
    /// @param sender The calling off-ramp.
    /// @param recipient The recipient of the tokens.
    /// @param amount The amount released, in local token units.
    event Released(address indexed sender, address indexed recipient, uint256 amount);

    /// @notice Emitted when tokens are minted by the pool.
    /// @param sender The calling off-ramp.
    /// @param recipient The recipient of the tokens.
    /// @param amount The amount minted, in local token units.
    event Minted(address indexed sender, address indexed recipient, uint256 amount);

    /// @notice Emitted when a remote chain is added.
    /// @param remoteChainSelector The chain selector added.
    /// @param remoteToken The token address on the remote chain.
    /// @param outboundRateLimiterConfig The outbound rate limiter configuration.
    /// @param inboundRateLimiterConfig The inbound rate limiter configuration.
    event ChainAdded(
        uint64 remoteChainSelector,
        bytes remoteToken,
        ICCIPRateLimiter.Config outboundRateLimiterConfig,
        ICCIPRateLimiter.Config inboundRateLimiterConfig
    );

    /// @notice Emitted when the rate limiter configurations of a remote chain are set.
    /// @param remoteChainSelector The chain selector configured.
    /// @param outboundRateLimiterConfig The outbound rate limiter configuration.
    /// @param inboundRateLimiterConfig The inbound rate limiter configuration.
    event ChainConfigured(
        uint64 remoteChainSelector,
        ICCIPRateLimiter.Config outboundRateLimiterConfig,
        ICCIPRateLimiter.Config inboundRateLimiterConfig
    );

    /// @notice Emitted when a remote chain is removed.
    /// @param remoteChainSelector The chain selector removed.
    event ChainRemoved(uint64 remoteChainSelector);

    /// @notice Emitted when a remote pool is added to a remote chain.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @param remotePoolAddress The remote pool address added.
    event RemotePoolAdded(uint64 indexed remoteChainSelector, bytes remotePoolAddress);

    /// @notice Emitted when a remote pool is removed from a remote chain.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @param remotePoolAddress The remote pool address removed.
    event RemotePoolRemoved(uint64 indexed remoteChainSelector, bytes remotePoolAddress);

    /// @notice Emitted when an address is added to the sender allowlist.
    /// @param sender The address added.
    event AllowListAdd(address sender);

    /// @notice Emitted when an address is removed from the sender allowlist.
    /// @param sender The address removed.
    event AllowListRemove(address sender);

    /// @notice Emitted when the router is set.
    /// @param oldRouter The previous router.
    /// @param newRouter The router set.
    event RouterUpdated(address oldRouter, address newRouter);

    /// @notice Emitted when the rate limit admin is set.
    /// @param rateLimitAdmin The rate limit admin set.
    event RateLimitAdminSet(address rateLimitAdmin);

    /// @notice Emitted when an ownership transfer is requested.
    /// @param from The current owner.
    /// @param to The proposed owner.
    event OwnershipTransferRequested(address indexed from, address indexed to);

    /// @notice Emitted when an ownership transfer is accepted.
    /// @param from The previous owner.
    /// @param to The new owner.
    event OwnershipTransferred(address indexed from, address indexed to);

    // ========== ERRORS ========== //

    /// @notice Thrown when the caller is not a ramp of the configured router.
    /// @param caller The rejected caller.
    error CallerIsNotARampOnRouter(address caller);

    /// @notice Thrown when a zero address or an empty encoded address is supplied.
    error ZeroAddressNotAllowed();

    /// @notice Thrown when the sender is not on the enabled allowlist.
    /// @param sender The rejected sender.
    error SenderNotAllowed(address sender);

    /// @notice Thrown when the allowlist is updated on a pool without an allowlist.
    error AllowListNotEnabled();

    /// @notice Thrown when a remote chain is not configured on the pool.
    /// @param remoteChainSelector The chain selector.
    error NonExistentChain(uint64 remoteChainSelector);

    /// @notice Thrown when a transfer is attempted for a remote chain that is not configured.
    /// @param remoteChainSelector The chain selector.
    error ChainNotAllowed(uint64 remoteChainSelector);

    /// @notice Thrown when the remote chain is cursed by the RMN.
    error CursedByRMN();

    /// @notice Thrown when a remote chain is added twice.
    /// @param chainSelector The chain selector.
    error ChainAlreadyExists(uint64 chainSelector);

    /// @notice Thrown when a message originates from a remote pool that is not accepted.
    /// @param sourcePoolAddress The rejected source pool address.
    error InvalidSourcePoolAddress(bytes sourcePoolAddress);

    /// @notice Thrown when the token of a transfer is not the pool token.
    /// @param token The rejected token.
    error InvalidToken(address token);

    /// @notice Thrown when the caller is not authorized.
    /// @param caller The rejected caller.
    error Unauthorized(address caller);

    /// @notice Thrown when a remote pool is added twice for a remote chain.
    /// @param remoteChainSelector The chain selector.
    /// @param remotePoolAddress The remote pool address.
    error PoolAlreadyAdded(uint64 remoteChainSelector, bytes remotePoolAddress);

    /// @notice Thrown when a remote pool to remove is not configured for a remote chain.
    /// @param remoteChainSelector The chain selector.
    /// @param remotePoolAddress The remote pool address.
    error InvalidRemotePoolForChain(uint64 remoteChainSelector, bytes remotePoolAddress);

    /// @notice Thrown when the decimals encoded by a remote pool are malformed.
    /// @param sourcePoolData The rejected pool data.
    error InvalidRemoteChainDecimals(bytes sourcePoolData);

    /// @notice Thrown when array arguments have different lengths.
    error MismatchedArrayLengths();

    /// @notice Thrown when a remote amount cannot be represented in local decimals.
    /// @param remoteDecimals The remote token decimals.
    /// @param localDecimals The local token decimals.
    /// @param remoteAmount The remote amount.
    error OverflowDetected(uint8 remoteDecimals, uint8 localDecimals, uint256 remoteAmount);

    /// @notice Thrown when the supplied token decimals differ from the token's decimals.
    /// @param expected The supplied decimals.
    /// @param actual The token's decimals.
    error InvalidDecimalArgs(uint8 expected, uint8 actual);

    /// @notice Thrown when the owner is set to the zero address.
    error OwnerCannotBeZero();

    /// @notice Thrown when `acceptOwnership` is called by an address other than the proposed
    ///         owner.
    error MustBeProposedOwner();

    /// @notice Thrown when the owner proposes itself as the new owner.
    error CannotTransferToSelf();

    /// @notice Thrown when an owner-only function is called by another address.
    error OnlyCallableByOwner();

    // ========== OWNERSHIP ========== //

    /// @notice Proposes a new owner. Ownership moves when the proposed owner accepts.
    /// @param to The proposed owner.
    function transferOwnership(address to) external;

    /// @notice Accepts a proposed ownership transfer. Callable only by the proposed owner.
    function acceptOwnership() external;

    // ========== CHAIN CONFIGURATION ========== //

    /// @notice Removes and then adds remote chains. The removals run before the additions, so a
    ///         selector present in both arguments is replaced in place. Removing a chain deletes
    ///         its remote pools, remote token and both buckets. Added chains start with both
    ///         buckets full.
    /// @param remoteChainSelectorsToRemove The chain selectors to remove.
    /// @param chainsToAdd The chains to add.
    function applyChainUpdates(
        uint64[] calldata remoteChainSelectorsToRemove,
        ChainUpdate[] calldata chainsToAdd
    ) external;

    /// @notice Adds an accepted remote pool for a configured remote chain.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @param remotePoolAddress The remote pool address to add.
    function addRemotePool(uint64 remoteChainSelector, bytes calldata remotePoolAddress) external;

    /// @notice Removes an accepted remote pool from a configured remote chain. In-flight
    ///         messages from the removed pool are rejected afterwards.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @param remotePoolAddress The remote pool address to remove.
    function removeRemotePool(
        uint64 remoteChainSelector,
        bytes calldata remotePoolAddress
    ) external;

    /// @notice Sets the router through which the pool resolves ramp authorization.
    /// @param newRouter The router address.
    function setRouter(address newRouter) external;

    /// @notice Sets the rate limit admin, which may set rate limiter configurations alongside
    ///         the owner. The zero address clears the role.
    /// @param rateLimitAdmin The rate limit admin address.
    function setRateLimitAdmin(address rateLimitAdmin) external;

    /// @notice Sets both rate limiter configurations of a configured remote chain. The bucket
    ///         fill level is clamped to the new capacity and is never raised.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @param outboundConfig The outbound rate limiter configuration.
    /// @param inboundConfig The inbound rate limiter configuration.
    function setChainRateLimiterConfig(
        uint64 remoteChainSelector,
        ICCIPRateLimiter.Config calldata outboundConfig,
        ICCIPRateLimiter.Config calldata inboundConfig
    ) external;

    /// @notice Sets both rate limiter configurations of several configured remote chains.
    /// @param remoteChainSelectors The chain selectors of the remote chains.
    /// @param outboundConfigs The outbound rate limiter configurations, one per chain.
    /// @param inboundConfigs The inbound rate limiter configurations, one per chain.
    function setChainRateLimiterConfigs(
        uint64[] calldata remoteChainSelectors,
        ICCIPRateLimiter.Config[] calldata outboundConfigs,
        ICCIPRateLimiter.Config[] calldata inboundConfigs
    ) external;

    /// @notice Removes and then adds sender allowlist entries. Absent removals, duplicate
    ///         additions and zero addresses are skipped silently.
    /// @param removes The addresses to remove.
    /// @param adds The addresses to add.
    function applyAllowListUpdates(address[] calldata removes, address[] calldata adds) external;
}
