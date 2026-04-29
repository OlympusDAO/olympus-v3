// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IPriceOracle} from "src/policies/interfaces/price/IPriceOracle.sol";

/// @title IERC7726Oracle
/// @notice ERC7726 oracle interface extending Euler's common IPriceOracle.
interface IERC7726Oracle is IPriceOracle {
    /// @notice Thrown when the oracle is not enabled in the factory
    error ERC7726Oracle_NotEnabled();

    /// @notice Thrown when the direct pair cache is unset or stale
    ///
    /// @param  cachedTimestamp               The cached timestamp used for the requested base/quote pair
    /// @param  latestPermissibleTimestamp    The oldest permissible timestamp (`block.timestamp - maxAge()`),
    ///                                       floored to 0 when `block.timestamp <= maxAge()`. A zero value is
    ///                                       valid and means there is no lower timestamp bound yet.
    error ERC7726Oracle_Stale(uint256 cachedTimestamp, uint256 latestPermissibleTimestamp);

    /// @notice Get the maximum allowed age for cached prices.
    ///
    /// @return maxAge_ The configured maximum cache age in seconds.
    function maxAge() external view returns (uint48 maxAge_);

    /// @notice Returns whether the direct pair cache is stale for a given pair.
    ///
    /// @param base         The address of the base token
    /// @param quote        The address of the quote token
    /// @return isStale_    Returns true if the pair cache is unset or older than maxAge.
    function isStale(address base, address quote) external view returns (bool isStale_);

    /// @notice Returns the cached timestamp used for a given base/quote pair.
    ///
    /// @param base         The address of the base token
    /// @param quote        The address of the quote token
    /// @return timestamp_  The cached UNIX timestamp (`uint48`) for this base/quote pair used to judge staleness.
    function timestamp(address base, address quote) external view returns (uint48 timestamp_);
}
