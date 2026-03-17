// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @title IPriceOracle
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Common PriceOracle interface.
interface IERC7726Oracle {
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

    /// @notice Get the name of the oracle.
    ///
    /// @return name_   The name of the oracle.
    function name() external view returns (string memory name_);

    /// @notice Get the maximum allowed age for cached prices.
    ///
    /// @return maxAge_ The configured maximum cache age in seconds.
    function maxAge() external view returns (uint48 maxAge_);

    /// @notice One-sided price: How much quote token you would get for inAmount of base token, assuming no price spread.
    ///
    /// @param inAmount     The amount of `base` to convert.
    /// @param base         The token that is being priced.
    /// @param quote        The token that is the unit of account.
    /// @return outAmount   The amount of `quote` that is equivalent to `inAmount` of `base`.
    function getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) external view returns (uint256 outAmount);

    /// @notice Two-sided price: How much quote token you would get/spend for selling/buying inAmount of base token.
    ///
    /// @param inAmount         The amount of `base` to convert.
    /// @param base             The token that is being priced.
    /// @param quote            The token that is the unit of account.
    /// @return bidOutAmount    The amount of `quote` you would get for selling `inAmount` of `base`.
    /// @return askOutAmount    The amount of `quote` you would spend for buying `inAmount` of `base`.
    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    ) external view returns (uint256 bidOutAmount, uint256 askOutAmount);

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
