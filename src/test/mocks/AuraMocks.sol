// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IAuraBooster, IAuraRewardPool, IAuraMiningLib} from "policies/BoostedLiquidity/interfaces/IAura.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockAuraBooster is IAuraBooster {
    address public token;
    address[] public pools;

    constructor(address token_, address pool_) {
        token = token_;
        pools.push(pool_);
    }

    function deposit(uint256 pid_, uint256 amount_, bool stake_) external {
        MockERC20(token).transferFrom(msg.sender, pools[pid_], amount_);
    }

    function addPool(address pool_) external {
        pools.push(pool_);
    }
}

contract MockAuraRewardPool is IAuraRewardPool {
    // Tokens
    address public depositToken;
    address public rewardToken;

    // Reward Token Reward Rate (per second)
    uint256 public rewardRate = 1e18;

    // Extra Rewards
    uint256 public extraRewardsLength;
    address[] public extraRewards;

    constructor(address depositToken_, address reward_) {
        depositToken = depositToken_;
        rewardToken = reward_;
    }

    function balanceOf(address account_) public view returns (uint256) {
        return MockERC20(depositToken).balanceOf(address(this));
    }

    function deposit(uint256 assets_, address receiver_) external {
        MockERC20(depositToken).transferFrom(receiver_, address(this), assets_);
    }

    function getReward(address account_, bool claimExtras_) public {
        MockERC20(rewardToken).mint(account_, 1e18);
    }

    function withdrawAndUnwrap(uint256 amount_, bool claim_) external {
        MockERC20(depositToken).transfer(msg.sender, amount_);
        if (claim_) getReward(msg.sender, true);
    }

    function earned(address account_) external view returns (uint256) {
        return 1e18;
    }
}

contract MockAuraMiningLib is IAuraMiningLib {
    constructor() {}

    function convertCrvToCvx(uint256 amount_) external view returns (uint256) {
        return amount_;
    }
}
