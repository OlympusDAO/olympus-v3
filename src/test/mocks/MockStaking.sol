// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract MockStaking {
    function unstake(address, uint256 amount, bool, bool) external pure returns (uint256) {
        return amount;
    }
}
