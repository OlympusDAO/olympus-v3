// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStaking {
    function unstake(
        address to,
        uint256 amount,
        bool trigger,
        bool rebasing
    ) external returns (uint256);
}
