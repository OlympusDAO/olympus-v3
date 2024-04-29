// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Uniswap V3
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

// Standard libraries
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title      UniswapV3OracleHelper
/// @author     0xJem
/// @notice     Helper functions for Uniswap V3 oracles
library UniswapV3OracleHelper {
    // ========  Constants  ======== //

    /// @notice     The minimum length of the TWAP observation window in seconds
    ///             From testing, a value under 19 seconds is rejected by `OracleLibrary.getQuoteAtTick()`
    ///             A value of 600 seconds is used to ensure the observation window is long enough to mitigate manipulation
    uint32 internal constant TWAP_MIN_OBSERVATION_WINDOW = 600; // seconds

    // ========  Errors  ======== //

    /// @notice                       The observation window for `pool_` is too short
    ///
    /// @param pool_                  The address of the pool
    /// @param observationWindow_     The observation window
    /// @param minObservationWindow_  The minimum observation window
    error UniswapV3OracleHelper_ObservationTooShort(
        address pool_,
        uint32 observationWindow_,
        uint32 minObservationWindow_
    );

    /// @notice                     The observation window for `pool_` is invalid
    ///
    /// @param pool_                The address of the pool
    /// @param observationWindow_   The observation window
    error UniswapV3OracleHelper_InvalidObservation(address pool_, uint32 observationWindow_);

    /// @notice                     The time-weighted tick is out of bounds
    ///
    /// @param pool_                The address of the pool
    /// @param timeWeightedTick_    The time-weighted tick
    /// @param minTick_             The minimum tick
    /// @param maxTick_             The maximum tick
    error UniswapV3OracleHelper_TickOutOfBounds(
        address pool_,
        int56 timeWeightedTick_,
        int24 minTick_,
        int24 maxTick_
    );

    // ========  Functions  ======== //

    /// @notice            Determines the time-weighted tick
    /// @dev               This is calculated as the difference between the tick at the end of the period and the tick at the beginning of the period, divided by the period
    ///
    /// @dev               This function will revert if:
    ///                    - The observation window is too short
    ///                    - The observation window is longer than the oldest observation in the pool
    ///                    - The time-weighted tick is outside the bounds of permissible ticks
    ///
    /// @param pool_       The address of the Uniswap V3 pool
    /// @param period_     The period (in seconds) over which to calculate the time-weighted tick
    /// @return            The time-weighted tick
    function getTimeWeightedTick(address pool_, uint32 period_) internal view returns (int56) {
        IUniswapV3Pool pool = IUniswapV3Pool(pool_);

        // Ensure the observation window is long enough
        if (period_ < TWAP_MIN_OBSERVATION_WINDOW)
            revert UniswapV3OracleHelper_ObservationTooShort(
                pool_,
                period_,
                TWAP_MIN_OBSERVATION_WINDOW
            );

        // Get tick and liquidity from the TWAP
        uint32[] memory observationWindow = new uint32[](2);
        observationWindow[0] = period_;
        observationWindow[1] = 0;

        int56 timeWeightedTick;
        try pool.observe(observationWindow) returns (
            int56[] memory tickCumulatives,
            uint160[] memory
        ) {
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            timeWeightedTick = (tickCumulativesDelta) / int32(period_);

            // If the time-weighted tick is negative, round down towards negative infinity
            // Matches the Uniswap V3 library: https://github.com/Uniswap/v3-periphery/blob/697c2474757ea89fec12a4e6db16a574fe259610/contracts/libraries/OracleLibrary.sol#L35
            if (tickCumulativesDelta < 0 && tickCumulativesDelta % int32(period_) != 0)
                timeWeightedTick--;
        } catch (bytes memory) {
            // This function will revert if the observation window is longer than the oldest observation in the pool
            // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/Oracle.sol#L226C30-L226C30
            revert UniswapV3OracleHelper_InvalidObservation(pool_, period_);
        }

        // Ensure the time-weighted tick is within the bounds of permissible ticks
        // Otherwise getQuoteAtTick will revert: https://docs.uniswap.org/contracts/v3/reference/error-codes
        if (timeWeightedTick > TickMath.MAX_TICK || timeWeightedTick < TickMath.MIN_TICK)
            revert UniswapV3OracleHelper_TickOutOfBounds(
                pool_,
                timeWeightedTick,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        return timeWeightedTick;
    }

    /// @notice                 Returns the ratio of token1 to token0 based on the TWAP
    ///
    /// @param pool_            The Uniswap V3 pool
    /// @param period_          The period of the TWAP in seconds
    /// @return                 The ratio of token1 to token0 in the scale of token1 decimals
    function getTWAPRatio(address pool_, uint32 period_) internal view returns (uint256) {
        int56 timeWeightedTick = getTimeWeightedTick(pool_, period_);

        IUniswapV3Pool pool = IUniswapV3Pool(pool_);
        ERC20 token0 = ERC20(pool.token0());
        ERC20 token1 = ERC20(pool.token1());

        // Quantity of token1 for 1 unit of token0 at the time-weighted tick
        // Scale: token1 decimals
        uint256 baseInQuote = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** token0.decimals()), // 1 unit of token0
            address(token0),
            address(token1)
        );

        return baseInQuote;
    }

    /// @notice                 Returns the ratio of the quote token to the base token based on the TWAP
    ///
    /// @param pool_                The Uniswap V3 pool
    /// @param period_              The period of the TWAP in seconds
    /// @param baseToken_           The base token
    /// @param quoteToken_          The quote token
    /// @param baseTokenDecimals_   The decimals of `baseToken_`
    /// @return                     The ratio of the quote token to the base token in the scale of the quote token decimals
    function getTWAPRatio(
        address pool_,
        uint32 period_,
        address baseToken_,
        address quoteToken_,
        uint8 baseTokenDecimals_
    ) internal view returns (uint256) {
        int56 timeWeightedTick = getTimeWeightedTick(pool_, period_);

        // Quantity of quoteToken_ for 1 unit of baseToken_ at the time-weighted tick
        // Scale: token1 decimals
        uint256 baseInQuote = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** baseTokenDecimals_), // 1 unit of baseToken_
            baseToken_,
            quoteToken_
        );

        return baseInQuote;
    }
}
