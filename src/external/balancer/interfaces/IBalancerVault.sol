// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

interface IBalancerVault {
    function getPoolTokens(
        bytes32 poolId
    )
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}
