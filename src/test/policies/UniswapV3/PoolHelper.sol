// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SwapRouter} from "test/lib/UniswapV3/SwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

library PoolHelper {
    function getAmountOutMinimum(
        IUniswapV3Pool pool_,
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 token1Token0Price_, // 18 dp
        uint16 slippageBps_
    ) internal view returns (uint256) {
        ERC20 tokenIn = ERC20(tokenIn_);
        ERC20 tokenOut = ERC20(tokenOut_);
        uint8 tokenInDecimals = tokenIn.decimals();
        uint8 tokenOutDecimals = tokenOut.decimals();

        bool zeroForOne = pool_.token0() == tokenIn_ ? true : false;

        uint256 amountOutMinimum = amountIn_;

        // Scale to 18 dp
        amountOutMinimum = (amountOutMinimum * 1e18) / 10 ** tokenInDecimals;

        // Convert using the price ratio
        if (zeroForOne) {
            amountOutMinimum = (amountOutMinimum * token1Token0Price_) / 1e18;
        } else {
            amountOutMinimum = (amountOutMinimum * 1e18) / token1Token0Price_;
        }

        // Adjust to tokenOut scale
        amountOutMinimum = (amountOutMinimum * 10 ** tokenOutDecimals) / 1e18;

        // Apply slippage
        amountOutMinimum = (amountOutMinimum * (10_000 - slippageBps_)) / 10_000;

        return amountOutMinimum;
    }

    /// @notice                 Simplifies the creation of an ExactInputSingleParams struct
    function getSwapParams(
        IUniswapV3Pool pool_,
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        address recipient_,
        uint256 token1Token0Price_, // 18 dp
        uint16 slippageBps_,
        int24 tickUpper_
    ) internal view returns (ISwapRouter.ExactInputSingleParams memory) {
        // NOTE: The docs say that a value of 0 should work in testing, but it reverts due to a check. This value seems to work, after days of testing.
        uint160 sqrtPriceLimitX96;
        {
            bool zeroForOne = pool_.token0() == tokenIn_ ? true : false;

            sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(zeroForOne ? -tickUpper_ : tickUpper_);
        }

        uint256 amountOutMinimum;
        {
            amountOutMinimum = getAmountOutMinimum(
                pool_,
                tokenIn_,
                tokenOut_,
                amountIn_,
                token1Token0Price_,
                slippageBps_
            );
        }

        return
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn_,
                tokenOut: tokenOut_,
                fee: pool_.fee(),
                recipient: recipient_,
                deadline: block.timestamp,
                amountIn: amountIn_,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });
    }
}
