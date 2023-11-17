// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Uniswap V3
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// Bunni
import {BunniKey} from "src/external/bunni/base/Structs.sol";

/// @title      BunniHelper
/// @author     0xJem
/// @notice     Helper functions for the BunniManager policy
library BunniHelper {
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
}
