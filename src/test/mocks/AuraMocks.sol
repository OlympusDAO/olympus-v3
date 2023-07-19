// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IAuraBooster, IAuraRewardPool, IAuraMiningLib, ISTASHToken} from "policies/BoostedLiquidity/interfaces/IAura.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

/// @title  Used for extra/virtual reward pools
interface IRewards {
    function deposits() external view returns (address);

    function getReward(address) external;

    function stake(address, uint256) external;

    function rewardToken() external view returns (address);

    function rewardRate() external view returns (uint256);
}

contract MockAuraBooster is IAuraBooster {
    address[] public pools;

    constructor(address pool_) {
        pools.push(pool_);
    }

    function deposit(uint256 pid_, uint256 amount_, bool stake_) external returns (bool) {
        address pool = pools[pid_];
        address token = MockAuraRewardPool(pool).depositToken();

        MockERC20(token).transferFrom(msg.sender, address(this), amount_);

        MockERC20(token).approve(pool, amount_);
        IAuraRewardPool(pool).deposit(amount_, msg.sender);

        return true;
    }

    function addPool(address pool_) external {
        pools.push(pool_);
    }
}

contract MockAuraRewardPool is IAuraRewardPool {
    // Tokens
    address public depositToken;
    address public rewardToken;
    address public aura;

    // Reward Token Reward Rate (per second)
    uint256 public rewardRate = 1e18;

    // Extra Rewards
    uint256 public extraRewardsLength;
    address[] public extraRewards;

    // User balances
    mapping(address => uint256) public balanceOf;

    constructor(address depositToken_, address reward_, address aura_) {
        depositToken = depositToken_;
        rewardToken = reward_;
        aura = aura_;
    }

    function deposit(uint256 assets_, address receiver_) external {
        balanceOf[receiver_] += assets_;
        MockERC20(depositToken).transferFrom(msg.sender, address(this), assets_);

        for (uint256 i; i < extraRewardsLength; i++) {
            IRewards(extraRewards[i]).stake(receiver_, assets_);
            ++i;
        }
    }

    function getReward(address account_, bool claimExtras_) public {
        if (balanceOf[account_] == 0) return;

        MockERC20(rewardToken).mint(account_, 1e18);
        if (aura != address(0)) MockERC20(aura).mint(account_, 1e18);

        if (claimExtras_) {
            for (uint256 i; i < extraRewardsLength; i++) {
                IRewards(extraRewards[i]).getReward(account_);
                ++i;
            }
        }
    }

    function withdrawAndUnwrap(uint256 amount_, bool claim_) external returns (bool) {
        MockERC20(depositToken).transfer(msg.sender, amount_);
        if (claim_) getReward(msg.sender, true);

        balanceOf[msg.sender] -= amount_;

        return true;
    }

    function earned(address account_) external view returns (uint256) {
        if (balanceOf[account_] != 0) return 1e18;
        return 0;
    }

    function addExtraReward(address reward_) external {
        extraRewards.push(reward_);
        extraRewardsLength++;
    }

    function setRewardRate(uint256 rate_) external {
        rewardRate = rate_;
    }
}

contract MockAuraMiningLib is IAuraMiningLib {
    constructor() {}

    function convertCrvToCvx(uint256 amount_) external view returns (uint256) {
        return amount_;
    }
}

contract MockAuraStashToken is ISTASHToken, MockERC20 {
    address public baseToken;

    // Constructor with the address of the baseToken and arguments to pass to MockERC20
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address baseToken_
    ) MockERC20(name_, symbol_, decimals_) {
        baseToken = baseToken_;
    }
}

contract MockAuraVirtualRewardPool is IRewards {
    address private _rewardToken;
    address private _deposits;

    constructor(address depositToken_, address rewardToken_) {
        _rewardToken = rewardToken_;
        _deposits = depositToken_;
    }

    function deposits() external view override returns (address) {
        return _deposits;
    }

    function getReward(address account_) external override {
        // Mimic transferring the base token of the reward token from the virtual reward pool
        // See: https://etherscan.io/address/0xA40A280b8ce1eba3E33E638b4BD72D5B701109FC#code#F1#L194
        MockERC20(ISTASHToken(_rewardToken).baseToken()).mint(account_, 1e18);
    }

    function stake(address, uint256) external override {
        // Do nothing
    }

    function rewardToken() external view override returns (address) {
        return _rewardToken;
    }

    function rewardRate() external view override returns (uint256) {
        return 1e18;
    }
}
