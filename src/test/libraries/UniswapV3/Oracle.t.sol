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
        // See: https://github.com/Uniswap/v3-periphery/blob/697c2474757ea89fec12a4e6db16a574fe259610/contracts/libraries/OracleLibrary.sol#L35
        uint32 period = 20;

        // tickCumulative1 - tickCumulative0 should be < 0
        // Also sufficiently negative to cause the time-weighted tick to be very negative
        int56 tickCumulative0 = int56(bound(tickCumulative0_, type(int56).max / 4, type(int56).max / 2));
        int56 tickCumulative1 = int56(bound(tickCumulative1_, type(int56).min / 2, type(int56).min / 4));
        vm.assume(
            tickCumulative1 < tickCumulative0 &&
                (tickCumulative1 - tickCumulative0) % int56(int32(period)) != 0
        );

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0;
        tickCumulatives[1] = tickCumulative1;
        uniswapPool.setTickCumulatives(tickCumulatives);

        // Get the time-weighted tick
        int56 expectedTick = (tickCumulative1 - tickCumulative0) / int56(int32(period));

        bytes memory err = abi.encodeWithSelector(
            UniswapV3OracleHelper.UniswapV3OracleHelper_TickOutOfBounds.selector,
            address(uniswapPool),
            expectedTick,
            MIN_TICK,
            MAX_TICK
        );
        vm.expectRevert(err);
        UniswapV3OracleHelper.getTimeWeightedTick(poolAddress, period);
    }
}
