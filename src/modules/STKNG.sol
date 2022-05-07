// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

import {IERC20} from "../interfaces/IERC20.sol";

import {Kernel, Module} from "../Kernel.sol";

contract OlympusStaking is Module {
    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 1e9;
    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    uint256 public indexedSupply;

    // Both balances in gons
    mapping(address => uint256) public indexedBalance;

    mapping(address => mapping(address => uint256)) public allowances;

    // TODO Add auth
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (bytes5) {
        return "STKNG";
    }

    function mint(address to_, uint256 indexed_) public onlyPermitted {
        // TODO add checks for max supply
        indexedSupply += indexed_;
        indexedBalance[to_] += indexed_;
    }

    function burn(address from_, uint256 indexed_) public onlyPermitted {
        // TODO add checks for underflow
        indexedBalance[from_] -= indexed_;
        indexedSupply -= indexed_;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 indexed_
    ) public onlyPermitted {
        indexedBalance[from_] -= indexed_;
        indexedBalance[to_] += indexed_;
    }

    function approve(
        address owner_,
        address spender_,
        uint256 indexed_
    ) public onlyPermitted {
        // TODO steal from solmate
        allowances[owner_][spender_] = indexed_;
    }
}
