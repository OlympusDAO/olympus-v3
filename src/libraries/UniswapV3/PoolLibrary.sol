// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title      UniswapV3PoolLibrary
/// @author     0xJem
/// @notice     Library for common functions on Uniswap V3 pool contracts
library UniswapV3PoolLibrary {
    // ========  Constants  ========

    uint16 public constant SLIPPAGE_SCALE = 10_000; // 100%

    // ========  Errors  ========

    /// @notice                 Emitted if the given slippage is invalid
    /// @param slippage_        The invalid slippage
    /// @param maxSlippage_     The maximum value for slippage
    error InvalidSlippage(uint16 slippage_, uint16 maxSlippage_);

    // ========  Functions  ========

    /// @notice         Determines if `pool_` is a valid Uniswap V3 pool
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @return         true if `pool_` is a valid Uniswap V3 pool, otherwise false
    function isValidPool(address pool_) internal view returns (bool) {
        bool isValid = false;

        try IUniswapV3Pool(pool_).slot0() returns (
            uint160,
            int24,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            isValid = true;
        } catch (bytes memory) {
            // If slot0 throws, then pool_ is not a Uniswap V3 pool
            // Do nothing
        }

        return isValid;
    }

    /// @notice         Gets the tokens for the given Uniswap V3 pool
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @return         The address of token0
    /// @return         The address of token1
    function getPoolTokens(address pool_) internal view returns (address, address) {
        IUniswapV3Pool pool = IUniswapV3Pool(pool_);

        return (pool.token0(), pool.token1());
    }

    /// @notice             Convenience method to calculate the minimum amount of tokens to receive
    /// @dev                This is calculated as `amount_ * (1 - slippageTolerance)`
    ///
    /// @param amount_      The amount of tokens to calculate the minimum for
    /// @param slippageBps_ The maximum percentage slippage allowed in basis points (100 = 1%)
    /// @return             The minimum amount of tokens to receive
    function getAmountMin(uint256 amount_, uint16 slippageBps_) internal pure returns (uint256) {
        // Check bounds
        if (slippageBps_ > SLIPPAGE_SCALE) revert InvalidSlippage(slippageBps_, SLIPPAGE_SCALE);

        return (amount_ * uint256(SLIPPAGE_SCALE - slippageBps_)) / uint256(SLIPPAGE_SCALE);
    }
}
