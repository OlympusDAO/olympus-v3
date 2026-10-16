// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

interface IBurnerLoansCompositesToken {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}
