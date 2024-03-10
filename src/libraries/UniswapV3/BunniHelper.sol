// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Uniswap V3
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {UniswapV3Positions} from "libraries/UniswapV3/Positions.sol";
import {UniswapV3PoolLibrary} from "libraries/UniswapV3/PoolLibrary.sol";

// Bunni
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";

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

    /// @notice         Convenience method to generate BunniHub withdaw parameters
    function getWithdrawParams(
        uint256 shares_,
        uint16 slippageBps_,
        BunniKey memory key_,
        IBunniToken existingToken_,
        address positionOwner_,
        address recipient_
    ) public view returns (IBunniHub.WithdrawParams memory) {
        // Determine the minimum amounts
        uint256 amount0Min;
        uint256 amount1Min;
        {
            (uint256 amount0, uint256 amount1) = UniswapV3Positions.getPositionAmounts(
                key_.pool,
                key_.tickLower,
                key_.tickUpper,
                positionOwner_
            );

            // Adjust for proportion of total supply
            uint256 totalSupply = existingToken_.totalSupply();
            amount0 = amount0.mulDiv(shares_, totalSupply);
            amount1 = amount1.mulDiv(shares_, totalSupply);

            amount0Min = UniswapV3PoolLibrary.getAmountMin(amount0, slippageBps_);
            amount1Min = UniswapV3PoolLibrary.getAmountMin(amount1, slippageBps_);
        }

        // Construct the parameters
        IBunniHub.WithdrawParams memory params = IBunniHub.WithdrawParams({
            key: key_,
            recipient: recipient_,
            shares: shares_,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp // Ensures that the action be executed in this block or reverted
        });

        return params;
    }
}
