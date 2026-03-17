// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IPriceOracle} from "src/policies/interfaces/price/IPriceOracle.sol";

/// @title IERC7726Oracle
/// @notice ERC7726 oracle interface extending Euler's common IPriceOracle.
interface IERC7726Oracle is IPriceOracle {
    /// @notice Thrown when the oracle is not enabled in the factory
    error ERC7726Oracle_NotEnabled();

    /// @notice Thrown when base/quote timestamps resolve to different sources/times
    ///
    /// @param  baseTimestamp_ The resolved base timestamp
    /// @param  quoteTimestamp_ The resolved quote timestamp
    error ERC7726Oracle_InconsistentTimestamps(uint48 baseTimestamp_, uint48 quoteTimestamp_);

    /// @notice Thrown when cached base/quote prices are stale
    ///
    /// @param  timestamp_ The shared cached timestamp used for quote resolution
    /// @param  maxAge_ The configured maximum cache age
    error ERC7726Oracle_Stale(uint48 timestamp_, uint48 maxAge_);

    /// @notice Get the maximum allowed age for cached prices.
    ///
    /// @return maxAge_ The configured maximum cache age in seconds.
    function maxAge() external view returns (uint48 maxAge_);

    /// @notice Returns whether the cached feed state is stale for a given pair.
    ///
    /// @return isStale_    Returns true if timestamps are inconsistent, unset, or older than maxAge.
    function isStale(address base, address quote) external view returns (bool isStale_);

    /// @notice Returns the shared cached timestamp used for a given quote pair.
    ///
    /// @param base         The address of the base token
    /// @param quote        The address of the quote token
    /// @return timestamp_  The timestamp from the
    function timestamp(address base, address quote) external view returns (uint48 timestamp_);
}
