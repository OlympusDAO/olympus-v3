// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";

/// @title ICCIPTokenPoolGetters
/// @notice The view surface of a Chainlink CCIP `TokenPool` (version 1.5.1).
/// @dev Set-valued getters return the values of an enumerable set, whose order changes when
///      entries are removed. Rate limiter states are projected to the current block timestamp
///      before being returned, so the `tokens` and `lastUpdated` fields differ from storage.
///      Getters for an unknown chain selector return empty values rather than reverting.
interface ICCIPTokenPoolGetters {
    /// @notice Returns the owner of the pool.
    /// @return owner_ The owner.
    function owner() external view returns (address owner_);

    /// @notice Returns the token that the pool locks, burns, releases or mints.
    /// @return token The token.
    function getToken() external view returns (address token);

    /// @notice Returns the decimals of the pool token on the local chain.
    /// @return decimals The token decimals.
    function getTokenDecimals() external view returns (uint8 decimals);

    /// @notice Returns the RMN proxy consulted for curses.
    /// @return rmnProxy The RMN proxy.
    function getRmnProxy() external view returns (address rmnProxy);

    /// @notice Returns the router through which ramp authorization is resolved.
    /// @return router The router.
    function getRouter() external view returns (address router);

    /// @notice Returns the rate limit admin, or the zero address if none is set.
    /// @return rateLimitAdmin The rate limit admin.
    function getRateLimitAdmin() external view returns (address rateLimitAdmin);

    /// @notice Returns whether a remote chain is configured on the pool.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @return supported True if the chain is configured.
    function isSupportedChain(uint64 remoteChainSelector) external view returns (bool supported);

    /// @notice Returns the configured remote chain selectors.
    /// @return chainSelectors The chain selectors.
    function getSupportedChains() external view returns (uint64[] memory chainSelectors);

    /// @notice Returns the accepted remote pools of a remote chain.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @return remotePools The remote pool addresses.
    function getRemotePools(
        uint64 remoteChainSelector
    ) external view returns (bytes[] memory remotePools);

    /// @notice Returns whether a remote pool is accepted for a remote chain.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @param remotePoolAddress The remote pool address.
    /// @return accepted True if the remote pool is accepted.
    function isRemotePool(
        uint64 remoteChainSelector,
        bytes calldata remotePoolAddress
    ) external view returns (bool accepted);

    /// @notice Returns the token address on a remote chain.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @return remoteToken The remote token address.
    function getRemoteToken(
        uint64 remoteChainSelector
    ) external view returns (bytes memory remoteToken);

    /// @notice Returns the outbound token bucket of a remote chain, projected to the current
    ///         block timestamp.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @return bucket The outbound token bucket.
    function getCurrentOutboundRateLimiterState(
        uint64 remoteChainSelector
    ) external view returns (ICCIPRateLimiter.TokenBucket memory bucket);

    /// @notice Returns the inbound token bucket of a remote chain, projected to the current
    ///         block timestamp.
    /// @param remoteChainSelector The chain selector of the remote chain.
    /// @return bucket The inbound token bucket.
    function getCurrentInboundRateLimiterState(
        uint64 remoteChainSelector
    ) external view returns (ICCIPRateLimiter.TokenBucket memory bucket);

    /// @notice Returns whether the sender allowlist is enabled. The flag is fixed at pool
    ///         construction.
    /// @return enabled True if the allowlist is enabled.
    function getAllowListEnabled() external view returns (bool enabled);

    /// @notice Returns the sender allowlist.
    /// @return allowList The allowlisted addresses.
    function getAllowList() external view returns (address[] memory allowList);

    /// @notice Returns whether the pool supports a token.
    /// @param token The token.
    /// @return supported True if the token is the pool token.
    function isSupportedToken(address token) external view returns (bool supported);
}
