// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/interfaces/UniswapV3/IUniswapV3Pool.sol";

contract MockUniV3Pair is IUniswapV3Pool {
    uint160 internal _sqrtPrice;
    address internal _token0;
    address internal _token1;
    int56[] internal _tickCumulatives;

    // Setters

    function setSqrtPrice(uint160 sqrtPrice_) public {
        _sqrtPrice = sqrtPrice_;
    }

    function setToken0(address token_) public {
        _token0 = token_;
    }

    function setToken1(address token_) public {
        _token1 = token_;
    }

    function setTickCumulatives(int56[] memory observations_) public {
        _tickCumulatives = observations_;
    }

    // Standard functions

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (_sqrtPrice, 0, 0, 0, 0, 0, true);
    }

    function observe(
        uint32[] calldata secondsAgos_
    )
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        )
    {
        uint160[] memory secondsPerLiquidity;

        return (_tickCumulatives, secondsPerLiquidity);
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }

    // Not implemented

    function fee() external view returns (uint24) {}

    function tickSpacing() external view returns (int24) {}

    function maxLiquidityPerTick() external view returns (uint128) {}

    function setFeeProtocol(uint8 feeProtocol0_, uint8 feeProtocol1_) external {}

    function collectProtocol(
        address recipient_,
        uint128 amount0Requested_,
        uint128 amount1Requested_
    ) external returns (uint128 amount0_, uint128 amount1_) {}

    function initialize(uint160 sqrtPriceX96_) external {}

    function mint(
        address recipient_,
        int24 tickLower_,
        int24 tickUpper_,
        uint128 amount_,
        bytes calldata data_
    ) external returns (uint256 amount0_, uint256 amount1_) {}

    function collect(
        address recipient_,
        int24 tickLower_,
        int24 tickUpper_,
        uint128 amount0Requested_,
        uint128 amount1Requested_
    ) external returns (uint128 amount0_, uint128 amount1_) {}

    function burn(
        int24 tickLower_,
        int24 tickUpper_,
        uint128 amount_
    ) external returns (uint256 amount0_, uint256 amount1_) {}

    function swap(
        address recipient_,
        bool zeroForOne_,
        int256 amountSpecified_,
        uint160 sqrtPriceLimitX96_,
        bytes calldata data_
    ) external returns (int256 amount0_, int256 amount1_) {}

    function flash(
        address recipient_,
        uint256 amount0_,
        uint256 amount1_,
        bytes calldata data_
    ) external {}

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext_) external {}

    function snapshotCumulativesInside(
        int24 tickLower_,
        int24 tickUpper_
    )
        external
        view
        returns (
            int56 tickCumulativeInside_,
            uint160 secondsPerLiquidityInsideX128_,
            uint32 secondsInside_
        )
    {}

    function factory() external view returns (address) {}

    function feeGrowthGlobal0X128() external view returns (uint256) {}

    function feeGrowthGlobal1X128() external view returns (uint256) {}

    function protocolFees() external view returns (uint128 token0_, uint128 token1_) {}

    function liquidity() external view returns (uint128) {}

    function ticks(
        int24 tick_
    )
        external
        view
        returns (
            uint128 liquidityGross_,
            int128 liquidityNet_,
            uint256 feeGrowthOutside0X128_,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside_,
            uint160 secondsPerLiquidityOutsideX128_,
            uint32 secondsOutside_,
            bool initialized_
        )
    {}

    function tickBitmap(int16 wordPosition_) external view returns (uint256) {}

    function positions(
        bytes32 key_
    )
        external
        view
        returns (
            uint128 liquidity_,
            uint256 feeGrowthInside0LastX128_,
            uint256 feeGrowthInside1LastX128_,
            uint128 tokensOwed0_,
            uint128 tokensOwed1_
        )
    {}

    function observations(
        uint256 index_
    )
        external
        view
        returns (
            uint32 blockTimestamp_,
            int56 tickCumulative_,
            uint160 secondsPerLiquidityCumulativeX128_,
            bool initialized_
        )
    {}
}