// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity 0.8.15;

import {IUniswapV2Pair} from "src/interfaces/Uniswap/IUniswapV2Pair.sol";

contract MockUniswapV2Pool is IUniswapV2Pair {
    address private _token0;
    address private _token1;
    uint112 private _reserve0;
    uint112 private _reserve1;
    uint256 private _totalSupply;

    function setToken0(address token0_) public {
        _token0 = token0_;
    }

    function token0() external view override returns (address) {
        return _token0;
    }

    function setToken1(address token1_) public {
        _token1 = token1_;
    }

    function token1() external view override returns (address) {
        return _token1;
    }

    function setReserves(uint112 reserve0_, uint112 reserve1_) public {
        _reserve0 = reserve0_;
        _reserve1 = reserve1_;
    }

    function getReserves()
        external
        view
        override
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        return (_reserve0, _reserve1, 0);
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function setTotalSupply(uint256 totalSupply_) public {
        _totalSupply = totalSupply_;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function swap(uint256, uint256, address, bytes calldata) external pure override {
        revert("Not implemented");
    }

    function mint(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function sync() external pure override {
        revert("Not implemented");
    }

    function approve(address, uint256) external pure override returns (bool) {
        revert("Not implemented");
    }

    function transfer(address, uint256) external pure override returns (bool) {
        revert("Not implemented");
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        revert("Not implemented");
    }

    function DOMAIN_SEPARATOR() external pure override returns (bytes32) {
        revert("Not implemented");
    }

    function PERMIT_TYPEHASH() external pure override returns (bytes32) {
        revert("Not implemented");
    }

    function name() external pure override returns (string memory) {
        revert("Mock Uniswap V2 Pool");
    }

    function symbol() external pure override returns (string memory) {
        revert("Mock Uniswap V2 Pool");
    }

    function nonces(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function permit(
        address,
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) external pure override {
        revert("Not implemented");
    }

    function balanceOf(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function allowance(address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }
}
/// forge-lint: disable-end(mixed-case-function)
