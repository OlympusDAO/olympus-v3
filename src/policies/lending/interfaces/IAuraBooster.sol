// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IAuraBooster {
    function deposit(
        uint256 pid_,
        uint256 amount_,
        bool stake_
    ) external;
}
