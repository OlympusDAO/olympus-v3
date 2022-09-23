// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockUniV2Pair {
    address public token0;
    address public token1;

    uint112 reserve0;
    uint112 reserve1;
    uint32 blockTimestampLast;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    /// Functions
    function getReserves()
        external
        view
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

    function sync() external {
        reserve0 = uint112(ERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(ERC20(token1).balanceOf(address(this)));
        blockTimestampLast = uint32(block.timestamp);
    }
}
