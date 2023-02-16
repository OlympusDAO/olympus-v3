// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

// Define Booster Interface
interface IAuraBooster {
    function deposit(
        uint256 pid_,
        uint256 amount_,
        bool stake_
    ) external;
}

// Define Base Reward Pool interface
interface IAuraRewardPool {
    function balanceOf(address account_) external view returns (uint256);

    function deposit(uint256 assets_, address receiver_) external;

    function getReward(address account_, bool claimExtras_) external;

    function withdrawAndUnwrap(uint256 amount_, bool claim_) external;
}
