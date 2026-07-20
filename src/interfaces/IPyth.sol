// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.15;

/// @title      IPyth
/// @notice     Minimal interface for Pyth Network price feeds
/// @dev        Based on Pyth Network's IPyth interface
interface IPyth {
    /// @notice     Price struct returned by Pyth Network
    /// @param  price   Price value (multiply by 10^expo to get the decimal value)
    /// @param  conf    Confidence interval, indicating that the actual asset price is ± conf (multiply by 10^expo to get the decimal value)
    /// @param  expo    Exponent
    /// @param  publishTime Timestamp when price was published
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    /// @notice                 Get the price object with a published timestamp from before than `age` seconds in the past
    /// @dev                    Returns the latest price object for the requested price feed ID, if it has been updated sufficiently recently
    ///
    /// @param priceId          The ID of the price feed
    /// @param age              Maximum age of the on-chain price in seconds
    /// @return price           Price struct containing price, confidence interval, exponent, and publishTime
    function getPriceNoOlderThan(
        bytes32 priceId,
        uint256 age
    ) external view returns (Price memory price);
}
