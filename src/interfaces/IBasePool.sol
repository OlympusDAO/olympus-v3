// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IBasePool {
    function getPoolId() external view returns (bytes32);

    function balanceOf(address user_) external view returns (uint256);

    function approve(address spender_, uint256 amount_) external returns (bool);
}
