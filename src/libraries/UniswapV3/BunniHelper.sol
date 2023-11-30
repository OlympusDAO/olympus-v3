// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Uniswap V3
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// Bunni
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";

// Standard libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "libraries/FullMath.sol";

/// @title      BunniHelper
/// @author     0xJem
/// @notice     Helper functions for the BunniManager policy
library BunniHelper {
    using FullMath for uint256;

    // ========  Functions  ======== //

    /// @notice         Convenience method to create a BunniKey identifier representing a full-range position.
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @return         The BunniKey identifier
    function getFullRangeBunniKey(address pool_) public view returns (BunniKey memory) {
        int24 tickSpacing = IUniswapV3Pool(pool_).tickSpacing();

        return
            BunniKey({
                pool: IUniswapV3Pool(pool_),
                // The ticks need to be divisible by the tick spacing
                // Source: https://github.com/Aboudoc/Uniswap-v3/blob/7aa9db0d0bf3d188a8a53a1dbe542adf7483b746/contracts/UniswapV3Liquidity.sol#L49C23-L49C23
                tickLower: (TickMath.MIN_TICK / tickSpacing) * tickSpacing,
                tickUpper: (TickMath.MAX_TICK / tickSpacing) * tickSpacing
            });
    }

    /// @notice         Returns the ratio of token1 to token0 based on the position reserves
    /// @dev            Includes uncollected fees
    ///
    /// @param key_     The BunniKey for the pool
    /// @param lens_    The BunniLens contract
    /// @return         The ratio of token1 to token0 in terms of token1 decimals
    function getReservesRatio(BunniKey memory key_, BunniLens lens_) public view returns (uint256) {
        IUniswapV3Pool pool = key_.pool;
        uint8 token0Decimals = ERC20(pool.token0()).decimals();

        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        (uint256 fee0, uint256 fee1) = lens_.getUncollectedFees(key_);

        return (reserve1 + fee1).mulDiv(10 ** token0Decimals, reserve0 + fee0);
    }
}
