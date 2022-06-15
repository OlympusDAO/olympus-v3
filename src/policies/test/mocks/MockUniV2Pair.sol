// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import "src/interfaces/Uniswap/IUniswapV2Pair.sol";
import "src/interfaces/IERC20.sol";

contract MockUniV2Pair is IUniswapV2Pair {
    address public token0;
    address public token1;

    uint112 reserve0;
    uint112 reserve1;
    uint32 blockTimestampLast;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    /// Setters
    function setToken0(address token0_) external {
        token0 = token0_;
    }

    function setToken1(address token1_) external {
        token1 = token1_;
    }

    /// Functions

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override {}

    function getReserves()
        external
        view
        override
        returns (
            uint112 reserve0_,
            uint112 reserve1_,
            uint32 blockTimestampLast_
        )
    {
        reserve0_ = reserve0;
        reserve1_ = reserve1;
        blockTimestampLast_ = blockTimestampLast;
    }

    function mint(address to) external override returns (uint256 liquidity) {}

    function sync() external override {
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
        blockTimestampLast = uint32(block.timestamp);
    }

    /// Functions from IUniswapV2ERC20 to have but not implement

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {}

    function PERMIT_TYPEHASH() external pure override returns (bytes32) {}

    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {}

    function approve(address spender, uint256 value)
        external
        override
        returns (bool)
    {}

    function balanceOf(address owner)
        external
        view
        override
        returns (uint256)
    {}

    function decimals() external pure returns (uint8) {}

    function name() external pure returns (string memory) {}

    function nonces(address owner) external view returns (uint256) {}

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {}

    function symbol() external pure override returns (string memory) {}

    function totalSupply() external view override returns (uint256) {}

    function transfer(address to, uint256 value)
        external
        override
        returns (bool)
    {}

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {}
}
