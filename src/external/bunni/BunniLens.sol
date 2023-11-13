// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "./base/Structs.sol";
import {IBunniHub} from "./interfaces/IBunniHub.sol";
import {IBunniLens} from "./interfaces/IBunniLens.sol";
import {IBunniToken} from "./interfaces/IBunniToken.sol";

/// @title BunniLens
/// @author zefram.eth
/// @notice Helper functions for fetching info about Bunni positions
contract BunniLens is IBunniLens {
    uint256 internal constant SHARE_PRECISION = 1e18;

    IBunniHub public immutable override hub;

    constructor(IBunniHub hub_) {
        hub = hub_;
    }

    /// @inheritdoc IBunniLens
    function pricePerFullShare(
        BunniKey calldata key
    ) external view virtual override returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        IBunniToken shareToken = hub.getBunniToken(key);
        uint256 existingShareSupply = shareToken.totalSupply();
        if (existingShareSupply == 0) {
            return (0, 0, 0);
        }

        (liquidity, , , , ) = key.pool.positions(
            keccak256(abi.encodePacked(address(hub), key.tickLower, key.tickUpper))
        );
        // liquidity is uint128, SHARE_PRECISION uses 60 bits
        // so liquidity * SHARE_PRECISION can't overflow 256 bits
        liquidity = uint128((liquidity * SHARE_PRECISION) / existingShareSupply);
        (amount0, amount1) = _getReserves(key, liquidity);
    }

    /// @inheritdoc IBunniLens
    function getReserves(
        BunniKey calldata key
    ) external view override returns (uint112 reserve0, uint112 reserve1) {
        (uint128 existingLiquidity, , , , ) = key.pool.positions(
            keccak256(abi.encodePacked(address(hub), key.tickLower, key.tickUpper))
        );
        return _getReserves(key, existingLiquidity);
    }

    /// @inheritdoc IBunniLens
    function getUncollectedFees(
        BunniKey calldata key
    ) external view override returns (uint256 fee0, uint256 fee1) {
        // TODO write tests
        (, int24 tick, , , , , ) = key.pool.slot0();
        (, , uint256 feeGrowthOutside0Lower, uint256 feeGrowthOutside1Lower, , , , ) = key
            .pool
            .ticks(key.tickLower);
        (, , uint256 feeGrowthOutside0Upper, uint256 feeGrowthOutside1Upper, , , , ) = key
            .pool
            .ticks(key.tickUpper);
        (uint128 liquidity, uint256 feeGrowthInside0Last, uint256 feeGrowthInside1Last, , ) = key
            .pool
            .positions(keccak256(abi.encodePacked(address(hub), key.tickLower, key.tickUpper)));
        uint256 feeGrowthGlobal = key.pool.feeGrowthGlobal0X128();

        fee0 = _computeFeesEarned(
            key,
            tick,
            liquidity,
            feeGrowthInside0Last,
            feeGrowthOutside0Lower,
            feeGrowthOutside0Upper,
            feeGrowthGlobal
        );
        fee1 = _computeFeesEarned(
            key,
            tick,
            liquidity,
            feeGrowthInside1Last,
            feeGrowthOutside1Lower,
            feeGrowthOutside1Upper,
            feeGrowthGlobal
        );
    }

    /// @notice Cast a uint256 to a uint112, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint112
    function _toUint112(uint256 y) internal pure returns (uint112 z) {
        require((z = uint112(y)) == y);
    }

    /// @dev See getReserves
    function _getReserves(
        BunniKey calldata key,
        uint128 existingLiquidity
    ) internal view returns (uint112 reserve0, uint112 reserve1) {
        (uint160 sqrtRatioX96, , , , , , ) = key.pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(key.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(key.tickUpper);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            existingLiquidity
        );

        reserve0 = _toUint112(amount0);
        reserve1 = _toUint112(amount1);
    }

    function _computeFeesEarned(
        BunniKey memory key,
        int24 tick,
        uint128 existingLiquidity,
        uint256 feeGrowthInsideLast,
        uint256 feeGrowthOutsideLower,
        uint256 feeGrowthOutsideUpper,
        uint256 feeGrowthGlobal
    ) internal pure returns (uint256 fee) {
        unchecked {
            // Calculate fee growth below
            uint256 feeGrowthBelow;
            if (tick >= key.tickLower) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // Calculate fee growth above
            uint256 feeGrowthAbove;
            if (tick < key.tickUpper) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;
            fee = FullMath.mulDiv(
                existingLiquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }
}
