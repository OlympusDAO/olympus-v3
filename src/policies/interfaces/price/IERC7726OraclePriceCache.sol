// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title  IERC7726OraclePriceCache
/// @author OlympusDAO
/// @notice Pair-level cache interface for oracle clones
/// @dev    Use this interface for clone contracts that expose cache helpers for arbitrary
///         base/quote pairs while applying their own configured max-age policy internally.
interface IERC7726OraclePriceCache {
    /// @notice             Updates the cached direct pair unconditionally
    ///
    /// @param base_        The base asset address
    /// @param quote_       The quote asset address
    function cachePrice(address base_, address quote_) external;

    /// @notice                 Updates the cached direct pair only if stale or unset
    ///
    /// @param base_            The base asset address
    /// @param quote_           The quote asset address
    function cachePriceIfNecessary(address base_, address quote_) external;
}
