// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IERC7726OraclePriceCache
/// @author OlympusDAO
/// @notice Pair-level cache interface for oracle clones
/// @dev    Use this interface for clone contracts that expose cache helpers for arbitrary
///         base/quote pairs while applying their own configured max-age policy internally.
interface IERC7726OraclePriceCache {
    /// @notice             Updates cached prices for base and quote assets unconditionally
    ///
    /// @param base_        The base asset address
    /// @param quote_       The quote asset address
    function cachePrices(address base_, address quote_) external;

    /// @notice                 Updates cached prices only if stale for this oracle or no cache exists
    ///
    /// @param base_            The base asset address
    /// @param quote_           The quote asset address
    function cachePricesIfNecessary(address base_, address quote_) external;
}
