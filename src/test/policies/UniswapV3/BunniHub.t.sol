// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {SwapRouter} from "@uniswap/v3-periphery/contracts/SwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {WETH} from "solmate/tokens/WETH.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import "src/external/bunni/base/Structs.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";
import {IBunniLens} from "src/external/bunni/interfaces/IBunniLens.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {UniswapDeployer} from "test/lib/UniswapV3/UniswapDeployer.sol";
import {LiquidityManagement} from "src/external/bunni/uniswap/LiquidityManagement.sol";

/// @notice POC to demonstrate the freeze of yield does not work after Olympus' modifications
///         on the original `BunniHub.compound()` implementation.
contract BunniHubTest is Test, UniswapDeployer {
    uint256 constant PRECISION = 10 ** 18;
    uint8 constant DECIMALS = 18;
    uint256 constant PROTOCOL_FEE = 5e16;

    IUniswapV3Factory factory;
    IUniswapV3Pool pool;
    SwapRouter router;
    ERC20Mock token0;
    ERC20Mock token1;
    WETH weth;
    IBunniHub hub;
    IBunniLens lens;
    IBunniToken bunniToken;
    uint24 fee;
    BunniKey key;
    address WHALE = address(0xDEADDEADDEAD);

    function setUp() public {
        // initialize uniswap
        token0 = new ERC20Mock("Token0", "TKN0", address(this), 0);
        token1 = new ERC20Mock("Token1", "TKN1", address(this), 0);
        if (address(token0) >= address(token1)) {
            (token0, token1) = (token1, token0);
        }
        factory = IUniswapV3Factory(deployUniswapV3Factory());
        fee = 500;
        pool = IUniswapV3Pool(factory.createPool(address(token0), address(token1), fee));
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        weth = new WETH();
        router = new SwapRouter(address(factory), address(weth));

        // initialize bunni hub
        hub = new BunniHub(factory, address(this), PROTOCOL_FEE);

        // initialize bunni lens
        lens = new BunniLens(hub);

        // initialize bunni
        key = BunniKey({pool: pool, tickLower: -10, tickUpper: 10});
        bunniToken = hub.deployBunniToken(key);

        // approve tokens
        token0.approve(address(hub), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(hub), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
    }

    function test_FixedFreezeOfYield() public {
        // make whale deposit, to satisfy requests outside victim's liquidity
        // in real scenario this can be either bunni positions or direct Uni-V3 positions
        BunniKey memory key2 = BunniKey({pool: pool, tickLower: -100000, tickUpper: 100000});
        hub.deployBunniToken(key2);
        uint256 depositWhaleAmount0 = PRECISION * 1000;
        uint256 depositWhaleAmount1 = PRECISION * 1000;

        token0.mint(address(this), depositWhaleAmount0);
        token1.mint(address(this), depositWhaleAmount1);
        // deposit tokens
        // max slippage is 1%
        IBunniHub.DepositParams memory depositParams = IBunniHub.DepositParams({
            key: key2,
            amount0Desired: depositWhaleAmount0,
            amount1Desired: depositWhaleAmount1,
            amount0Min: depositWhaleAmount0,
            amount1Min: depositWhaleAmount1,
            deadline: block.timestamp,
            recipient: WHALE
        });
        hub.deposit(depositParams);

        // victim's concentrated liquidity
        uint256 depositAmount0 = PRECISION * 10;
        uint256 depositAmount1 = PRECISION * 10;
        (uint256 shares, , , ) = _makeDeposit(depositAmount0, depositAmount1);

        // utility to print tick sign, foundry can't print int24
        bool negtick;

        // print current tick
        (, int24 tick, , , , , ) = pool.slot0();
        negtick = tick < 0;
        if (tick < 0) tick = -tick;
        console.log("Current tick: %s %s", uint256(int256(tick)), negtick);

        // trade in and out of victim's concentrated liquidity, generate fees
        for (uint i = 0; i < 1000; i++) {
            {
                // swap token0 to token1
                uint256 amountIn = PRECISION * 30;
                token0.mint(address(this), amountIn);
                ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: address(token0),
                        tokenOut: address(token1),
                        fee: fee,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amountIn,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                router.exactInputSingle(swapParams);
            }
            {
                // swap token1 to token0
                uint256 amountIn = PRECISION * 60;
                token1.mint(address(this), amountIn);
                ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: address(token1),
                        tokenOut: address(token0),
                        fee: fee,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amountIn,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                router.exactInputSingle(swapParams);
            }
            {
                // swap token0 to token1
                uint256 amountIn = PRECISION * 30;
                token0.mint(address(this), amountIn);
                ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: address(token0),
                        tokenOut: address(token1),
                        fee: fee,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amountIn,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                router.exactInputSingle(swapParams);
            }
        }

        // Now step out of victim's range
        {
            // swap token1 to token0
            uint256 amountIn = PRECISION * 20;
            token0.mint(address(this), amountIn);
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: address(token1),
                    tokenOut: address(token0),
                    fee: fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });
            router.exactInputSingle(swapParams);
        }

        // print current tick
        (, tick, , , , , ) = pool.slot0();
        negtick = tick < 0;
        if (tick < 0) tick = -tick;
        console.log("Current tick: %s %s", uint256(int256(tick)), negtick);

        uint128 cachedFeesOwed0;
        uint128 cachedFeesOwed1;

        // prank the hub and call burn(0) to update fees owed so that we can log them
        vm.prank(address(hub));
        key.pool.burn(key.tickLower, key.tickUpper, 0);

        // log fees owed
        (, , , cachedFeesOwed0, cachedFeesOwed1) = pool.positions(
            keccak256(abi.encodePacked(hub, key.tickLower, key.tickUpper))
        );

        console.log("Fees owed 0: %d", cachedFeesOwed0);
        console.log("Fees owed 1: %d", cachedFeesOwed1);
        console.log("---");

        {
            uint256 cachedAmount0 = token0.balanceOf(address(this));
            uint256 cachedAmount1 = token1.balanceOf(address(this));

            // call compound - fees are collected and compounded.
            // out-of-range fees are sent back to the owner.
            (uint256 addedLiquidity, uint256 amount0, uint256 amount1) = hub.compound(key);

            console.log("Compounded liquidity: %d", addedLiquidity);
            console.log("Compounded amt0: %d", amount0);
            console.log("Compounded amt1: %d", amount1);

            uint256 collected0 = token0.balanceOf(address(this)) - cachedAmount0;
            uint256 collected1 = token1.balanceOf(address(this)) - cachedAmount1;

            // assertGt(collected0, 0);
            // assertGe(collected1, 0);
            console.log("Collected fee0: %d", collected0);
            console.log("Collected fee1: %d", collected1);
        }

        (, , , cachedFeesOwed0, cachedFeesOwed1) = pool.positions(
            keccak256(abi.encodePacked(hub, key.tickLower, key.tickUpper))
        );

        console.log("Fees owed 0: %d", cachedFeesOwed0);
        console.log("Fees owed 1: %d", cachedFeesOwed1);

        // withdraw all victim shares
        IBunniHub.WithdrawParams memory withdrawParams = IBunniHub.WithdrawParams({
            key: key,
            recipient: address(this),
            shares: shares,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (, uint256 withdrawAmount0, uint256 withdrawAmount1) = hub.withdraw(withdrawParams);

        // confirm that NO fees are leaked forever
        (, , , cachedFeesOwed0, cachedFeesOwed1) = pool.positions(
            keccak256(abi.encodePacked(hub, key.tickLower, key.tickUpper))
        );

        assertEq(cachedFeesOwed0, 0);
        assertEq(cachedFeesOwed1, 0);

        console.log("---");
        console.log("Fees owed 0: %d", cachedFeesOwed0);
        console.log("Fees owed 1: %d", cachedFeesOwed1);

        // final deposit & withdraw stats
        console.log("Deposit amt0: %d", depositAmount0);
        console.log("Deposit amt1: %d", depositAmount1);

        console.log("Withdraw amt0: %d", withdrawAmount0);
        console.log("Withdraw amt1: %d", withdrawAmount1);
    }

    function _makeDeposit(
        uint256 depositAmount0,
        uint256 depositAmount1
    ) internal returns (uint256 shares, uint128 newLiquidity, uint256 amount0, uint256 amount1) {
        // mint tokens
        token0.mint(address(this), depositAmount0);
        token1.mint(address(this), depositAmount1);

        // deposit tokens
        // max slippage is 1%
        IBunniHub.DepositParams memory depositParams = IBunniHub.DepositParams({
            key: key,
            amount0Desired: depositAmount0,
            amount1Desired: depositAmount1,
            amount0Min: (depositAmount0 * 99) / 100,
            amount1Min: (depositAmount1 * 99) / 100,
            deadline: block.timestamp,
            recipient: address(this)
        });
        return hub.deposit(depositParams);
    }
}
