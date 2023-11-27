// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

interface IBalancerPool {
    function balanceOf(address account_) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getPoolId() external view returns (bytes32);
}
