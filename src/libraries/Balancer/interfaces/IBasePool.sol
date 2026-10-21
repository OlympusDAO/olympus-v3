// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

interface IBasePool {
    function getPoolId() external view returns (bytes32);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);
}
