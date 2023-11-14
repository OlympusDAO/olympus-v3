// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

interface IBasePool {
    function getPoolId() external view returns (bytes32);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);
}
