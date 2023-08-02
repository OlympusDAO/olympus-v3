// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IStaking {
    function stake(
        address to_,
        uint256 amount_,
        bool rebasing_,
        bool claim_
    ) external returns (uint256);
}
