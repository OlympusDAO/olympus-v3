// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import "./base/Structs.sol";
import {ERC20} from "./lib/ERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IBunniHub} from "./interfaces/IBunniHub.sol";
import {IBunniToken} from "./interfaces/IBunniToken.sol";

/// @title BunniToken
/// @author zefram.eth
/// @notice ERC20 token that represents a user's LP position
contract BunniToken is IBunniToken, ERC20 {
    IUniswapV3Pool public immutable override pool;
    int24 public immutable override tickLower;
    int24 public immutable override tickUpper;
    IBunniHub public immutable override hub;

    constructor(
        IBunniHub hub_,
        BunniKey memory key_
    )
        ERC20(
            string(
                abi.encodePacked(
                    "Bunni ",
                    IERC20(key_.pool.token0()).symbol(),
                    "/",
                    IERC20(key_.pool.token1()).symbol(),
                    " LP"
                )
            ),
            "BUNNI-LP",
            18
        )
    {
        pool = key_.pool;
        tickLower = key_.tickLower;
        tickUpper = key_.tickUpper;
        hub = hub_;
    }

    function mint(address to, uint256 amount) external override {
        require(msg.sender == address(hub), "WHO");

        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override {
        require(msg.sender == address(hub), "WHO");

        _burn(from, amount);
    }
}
