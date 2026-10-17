// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Libraries
import {ConfigTimelockKeyLib} from "src/policies/utils/ConfigTimelockKeyLib.sol";

/// @title  CCIPTokenPoolConfigKeyLib
/// @notice Derives the configuration domains and keys of `CCIPTokenPoolConfigTimelock`: the four
///         domain constants, the destination-local key of each domain, and the destination-scoped
///         key that the timelock reserves and that `pendingActionId` takes, scoped to the config
///         policy the timelock is bound to.
/// @dev    A route contributes three domains, keyed per chain selector; the allowlist is one
///         pool-wide domain whose local key is the domain constant itself. Shared by the timelock
///         and the tooling that reads its reservations, so that both compute a key with one formula.
library CCIPTokenPoolConfigKeyLib {
    // ========== DOMAINS ========== //

    /// @notice The domain of the rate limits of a route: `isEnabled`, `capacity` and `rate` of
    ///         both buckets.
    bytes32 internal constant RATE_LIMITS_DOMAIN = keccak256("CCIP_TOKEN_POOL_CONFIG_RATE_LIMITS");

    /// @notice The domain of the accepted remote pools of a route.
    bytes32 internal constant REMOTE_POOLS_DOMAIN =
        keccak256("CCIP_TOKEN_POOL_CONFIG_REMOTE_POOLS");

    /// @notice The domain of the identity of a route: whether the route exists and its remote
    ///         token.
    bytes32 internal constant ROUTE_IDENTITY_DOMAIN =
        keccak256("CCIP_TOKEN_POOL_CONFIG_ROUTE_IDENTITY");

    /// @notice The domain of the pool-wide sender allowlist.
    bytes32 internal constant ALLOWLIST_DOMAIN = keccak256("CCIP_TOKEN_POOL_CONFIG_ALLOWLIST");

    // ========== LOCAL KEYS ========== //

    /// @notice Returns the destination-local key of a route domain.
    /// @param  domain_ The domain constant.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return localKey The key `keccak256(abi.encode(domain_, chainSelector_))`.
    function routeLocalKey(
        bytes32 domain_,
        uint64 chainSelector_
    ) internal pure returns (bytes32 localKey) {
        return keccak256(abi.encode(domain_, chainSelector_));
    }

    /// @notice Returns the destination-local key of the rate limits domain of a route.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return localKey The local key.
    function rateLimitsLocalKey(uint64 chainSelector_) internal pure returns (bytes32 localKey) {
        return routeLocalKey(RATE_LIMITS_DOMAIN, chainSelector_);
    }

    /// @notice Returns the destination-local key of the remote pools domain of a route.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return localKey The local key.
    function remotePoolsLocalKey(uint64 chainSelector_) internal pure returns (bytes32 localKey) {
        return routeLocalKey(REMOTE_POOLS_DOMAIN, chainSelector_);
    }

    /// @notice Returns the destination-local key of the identity domain of a route.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return localKey The local key.
    function routeIdentityLocalKey(uint64 chainSelector_) internal pure returns (bytes32 localKey) {
        return routeLocalKey(ROUTE_IDENTITY_DOMAIN, chainSelector_);
    }

    /// @notice Returns the destination-local key of the allowlist domain: the domain constant
    ///         itself, since the domain has no chain selector.
    /// @return localKey The local key.
    function allowListLocalKey() internal pure returns (bytes32 localKey) {
        return ALLOWLIST_DOMAIN;
    }

    // ========== SCOPED KEYS ========== //

    /// @notice Returns the reserved key of the rate limits domain of a route.
    /// @param  config_ The config policy the timelock is bound to.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return key The destination-scoped key.
    function rateLimitsKey(
        address config_,
        uint64 chainSelector_
    ) internal pure returns (bytes32 key) {
        return ConfigTimelockKeyLib.scope(config_, rateLimitsLocalKey(chainSelector_));
    }

    /// @notice Returns the reserved key of the remote pools domain of a route.
    /// @param  config_ The config policy the timelock is bound to.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return key The destination-scoped key.
    function remotePoolsKey(
        address config_,
        uint64 chainSelector_
    ) internal pure returns (bytes32 key) {
        return ConfigTimelockKeyLib.scope(config_, remotePoolsLocalKey(chainSelector_));
    }

    /// @notice Returns the reserved key of the identity domain of a route.
    /// @param  config_ The config policy the timelock is bound to.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return key The destination-scoped key.
    function routeIdentityKey(
        address config_,
        uint64 chainSelector_
    ) internal pure returns (bytes32 key) {
        return ConfigTimelockKeyLib.scope(config_, routeIdentityLocalKey(chainSelector_));
    }

    /// @notice Returns the reserved key of the allowlist domain.
    /// @param  config_ The config policy the timelock is bound to.
    /// @return key The destination-scoped key.
    function allowListKey(address config_) internal pure returns (bytes32 key) {
        return ConfigTimelockKeyLib.scope(config_, allowListLocalKey());
    }
}
