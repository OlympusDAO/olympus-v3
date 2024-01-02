// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

// Test
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {MockUniV3Pair} from "test/mocks/MockUniV3Pair.sol";

import {UniswapV3OracleHelper} from "libraries/UniswapV3/Oracle.sol";

contract OracleTest is Test {
    MockUniV3Pair internal uniswapPool;

    int56 internal constant MIN_TICK = -887272;
    int56 internal constant MAX_TICK = 887272;

    function setUp() public {
        uniswapPool = new MockUniV3Pair();
    }

    function test_getTimeWeightedTick_negativeInfinity(
        int56 tickCumulative0_,
        int56 tickCumulative1_
    ) public {
        uint32 period = 20;

        // tickCumulative1 - tickCumulative0 should be < 0
        int56 tickCumulative0 = int56(bound(tickCumulative0_, MIN_TICK, MAX_TICK));
        int56 tickCumulative1 = int56(bound(tickCumulative1_, MIN_TICK, MAX_TICK));
        vm.assume(
            tickCumulative1 < tickCumulative0 &&
                (tickCumulative1 - tickCumulative0) % int56(int32(period)) != 0
        );

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0;
        tickCumulatives[1] = tickCumulative1;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Round down towards negative infinity
        // See: https://github.com/Uniswap/v3-periphery/blob/697c2474757ea89fec12a4e6db16a574fe259610/contracts/libraries/OracleLibrary.sol#L35
        int56 expectedTick = (tickCumulative1 - tickCumulative0) / int56(int32(period)) - 1;

        // Get the time-weighted tick
        assertEq(
            expectedTick,
            UniswapV3OracleHelper.getTimeWeightedTick(address(uniswapPool), period)
        );
    }

    function test_getTimeWeightedTick(int56 tickCumulative0_, int56 tickCumulative1_) public {
        uint32 period = 20;

        int56 tickCumulative0 = int56(bound(tickCumulative0_, MIN_TICK, MAX_TICK));
        int56 tickCumulative1 = int56(bound(tickCumulative1_, MIN_TICK, MAX_TICK));
        vm.assume(tickCumulative1 > tickCumulative0);

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0;
        tickCumulatives[1] = tickCumulative1;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Round down towards negative infinity
        int56 expectedTick = (tickCumulative1 - tickCumulative0) / int56(int32(period));

        // Get the time-weighted tick
        assertEq(
            expectedTick,
            UniswapV3OracleHelper.getTimeWeightedTick(address(uniswapPool), period)
        );
    }
}
