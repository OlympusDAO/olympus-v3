// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Uniswap V3
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

/// @title          UniswapV3Positions
/// @notice         Helper functions for Uniswap V3 positions
/// @author         0xJem
library UniswapV3Positions {
    /// @notice             Gets the amount of token0 and token1 that would be received if the position was closed
    ///
    /// @param pool_        The address of the Uniswap V3 pool
    /// @param tickLower_   The lower tick of the position
    /// @param tickUpper_   The upper tick of the position
    /// @param owner_       The owner of the position
    /// @return             The amount of token0
    /// @return             The amount of token1
    function getPositionAmounts(
        IUniswapV3Pool pool_,
        int24 tickLower_,
        int24 tickUpper_,
        address owner_
    ) public view returns (uint256, uint256) {
        (uint160 sqrtRatioX96, , , , , , ) = pool_.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower_);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper_);

        // Copied from BunniHub.deposit()
        (uint128 existingLiquidity, , , , ) = pool_.positions(
            keccak256(abi.encodePacked(owner_, tickLower_, tickUpper_))
        );

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            existingLiquidity
        );

        return (amount0, amount1);
    }

    /// @notice             Gets the fees accrued for the position
    ///
    /// @param pool_        The address of the Uniswap V3 pool
    /// @param tickLower_   The lower tick of the position
    /// @param tickUpper_   The upper tick of the position
    /// @param owner_       The owner of the position
    /// @return             The amount of token0 fees accrued
    /// @return             The amount of token1 fees accrued
    function getPositionFees(
        IUniswapV3Pool pool_,
        int24 tickLower_,
        int24 tickUpper_,
        address owner_
    ) public view returns (uint128, uint128) {
        (, , , uint128 fees0, uint128 fees1) = pool_.positions(
            keccak256(abi.encodePacked(address(owner_), tickLower_, tickUpper_))
        );

        return (fees0, fees1);
    }

    /// @notice             Gets the amount of liquidity in the position
    ///
    /// @param pool_        The address of the Uniswap V3 pool
    /// @param tickLower_   The lower tick of the position
    /// @param tickUpper_   The upper tick of the position
    /// @param owner_       The owner of the position
    /// @return             The amount of liquidity
    function getPositionLiquidity(
        IUniswapV3Pool pool_,
        int24 tickLower_,
        int24 tickUpper_,
        address owner_
    ) public view returns (uint128) {
        (uint128 liquidity, , , , ) = pool_.positions(
            keccak256(abi.encodePacked(address(owner_), tickLower_, tickUpper_))
        );

        return liquidity;
    }

    /// @notice             Checks if the position has liquidity
    ///
    /// @param pool_        The address of the Uniswap V3 pool
    /// @param tickLower_   The lower tick of the position
    /// @param tickUpper_   The upper tick of the position
    /// @param owner_       The owner of the position
    /// @return             True if the position has liquidity
    function positionHasLiquidity(
        IUniswapV3Pool pool_,
        int24 tickLower_,
        int24 tickUpper_,
        address owner_
    ) public view returns (bool) {
        return getPositionLiquidity(pool_, tickLower_, tickUpper_, owner_) > 0;
    }
}
