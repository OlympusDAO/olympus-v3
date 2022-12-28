// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import {LENDRv1} from "src/modules/LENDR/LENDR.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1, RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import "src/Kernel.sol";

// Import internal dependencies
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Import types
import {ERC20} from "solmate/tokens/ERC20.sol";

import {console2} from "forge-std/Script.sol";

/// @title Olympus Base Liquidity AMO
contract BaseLiquidityAMO is Policy, ReentrancyGuard, RolesConsumer {
    // ========= ERRORS ========= //

    error LiquidityAMO_PoolImbalanced();

    // ========= DATA STRUCTURES ========= //

    struct RewardToken {
        address token;
        uint256 rewardsPerSecond;
        uint256 lastRewardTime;
        uint256 accumulatedRewardsPerShare;
    }

    // ========= STATE ========= //

    // Modules
    MINTRv1 public MINTR;
    LENDRv1 public LENDR;

    // Tokens
    ERC20 public ohm;
    ERC20 public pairToken;
    ERC20 public lpToken;

    // User State
    mapping(address => uint256) public pairTokenDeposits; // User pair token deposits
    mapping(address => uint256) public lpPositions; // User LP positions
    mapping(address => mapping(address => uint256)) public userRewardDebts; // User reward debts (masterchef math)

    // Reward Token State
    RewardToken[] public rewardTokens;

    // Configuration values
    uint256 public THRESHOLD;
    uint256 public FEE;
    uint256 public constant PRECISION = 1000;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address pairToken_,
        address lpToken_
    ) Policy(kernel_) {
        // Set tokens
        ohm = ERC20(ohm_);
        pairToken = ERC20(pairToken_);
        lpToken = ERC20(lpToken_);
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("LENDR");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        LENDR = LENDRv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = MINTR.KEYCODE();
        Keycode lendrKeycode = LENDR.KEYCODE();

        permissions = new Permissions[](5);
        permissions[0] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.burnOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[3] = Permissions(lendrKeycode, LENDR.borrow.selector);
        permissions[4] = Permissions(lendrKeycode, LENDR.repay.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @dev    This needs to be non-reentrant since the contract only knows the amount of LP tokens it
    ///         receives after an external interaction with the Balancer pool
    function deposit(uint256 amount_) external nonReentrant returns (uint256 lpAmountOut) {
        _updateRewardState();

        // Update state about user's deposits and borrows
        pairTokenDeposits[msg.sender] += amount_;

        // Take pair token from user
        pairToken.transferFrom(msg.sender, address(this), amount_);

        // Borrow OHM
        uint256 ohmToBorrow = _valueCollateral(amount_);
        _borrow(ohmToBorrow);

        uint256 lpReceived = _deposit(ohmToBorrow, amount_);

        // Update user's LP position
        lpPositions[msg.sender] += lpReceived;

        // Update user's reward debt
        uint256 numRewardTokens = rewardTokens.length;
        for (uint256 i; i < numRewardTokens; ) {
            address rewardToken = rewardTokens[i].token;
            userRewardDebts[msg.sender][rewardToken] +=
                (lpReceived * rewardTokens[i].accumulatedRewardsPerShare) /
                1e18;

            unchecked {
                ++i;
            }
        }
    }

    /// TODO: Decide if we even want this, it foregoes rewards
    /// @dev    This needs to be non-reentrant since the contract only knows the amount of OHM and
    ///         pair tokens it receives after an external call to withdraw liquidity from Balancer
    function withdraw(uint256 lpAmount_) external nonReentrant returns (uint256) {
        if (!_isPoolSafe()) revert LiquidityAMO_PoolImbalanced();
        _updateRewardState();

        lpPositions[msg.sender] -= lpAmount_;

        // Update user's reward debt
        uint256 numRewardTokens = rewardTokens.length;
        for (uint256 i; i < numRewardTokens; ) {
            address rewardToken = rewardTokens[i].token;
            userRewardDebts[msg.sender][rewardToken] -=
                (lpAmount_ * rewardTokens[i].accumulatedRewardsPerShare) /
                1e18;

            unchecked {
                ++i;
            }
        }

        (uint256 ohmReceived, uint256 pairTokenReceived) = _withdraw(lpAmount_);

        // Reduce deposit values
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;

        // Return assets
        _repay(ohmReceived);
        pairToken.transfer(msg.sender, pairTokenReceived);

        return pairTokenReceived;
    }

    function withdrawAndClaim(uint256 lpAmount_) external nonReentrant returns (uint256) {
        if (!_isPoolSafe()) revert LiquidityAMO_PoolImbalanced();
        _updateRewardState();
        _claimRewards();

        // Update user's reward debt
        uint256 numRewardTokens = rewardTokens.length;
        for (uint256 i; i < numRewardTokens; ) {
            address rewardToken = rewardTokens[i].token;

            userRewardDebts[msg.sender][rewardToken] =
                (lpPositions[msg.sender] *
                    rewardTokens[i].accumulatedRewardsPerShare -
                    (lpAmount_ * rewardTokens[i].accumulatedRewardsPerShare)) /
                1e18;

            unchecked {
                ++i;
            }
        }

        lpPositions[msg.sender] -= lpAmount_;

        // Withdraw OHM and stETH from LP
        (uint256 ohmReceived, uint256 pairTokenReceived) = _withdraw(lpAmount_);

        // Reduce deposit values
        uint256 userDeposit = pairTokenDeposits[msg.sender];
        pairTokenDeposits[msg.sender] -= pairTokenReceived > userDeposit
            ? userDeposit
            : pairTokenReceived;

        // Return assets
        _repay(ohmReceived);
        pairToken.transfer(msg.sender, pairTokenReceived);

        return pairTokenReceived;
    }

    function claimRewards() external returns (uint256) {
        _claimRewards();
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    function rewardsForToken(uint256 id_, address user_) public view returns (uint256) {
        RewardToken memory rewardToken = rewardTokens[id_];
        uint256 accumulatedRewardsPerShare = rewardToken.accumulatedRewardsPerShare;
        uint256 totalLP = lpToken.balanceOf(address(this));

        if (block.timestamp > rewardToken.lastRewardTime && totalLP != 0) {
            uint256 timeDiff = block.timestamp - rewardToken.lastRewardTime;
            uint256 totalRewards = (timeDiff * rewardToken.rewardsPerSecond);
            accumulatedRewardsPerShare += (totalRewards * 1e18) / totalLP;
        }

        return
            ((lpPositions[user_] * accumulatedRewardsPerShare) / 1e18) -
            userRewardDebts[user_][rewardToken.token];
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _valueCollateral(uint256 amount_) internal view virtual returns (uint256) {}

    function _getPoolPrice() internal view virtual returns (uint256) {}

    function _isPoolSafe() internal view returns (bool) {
        uint256 poolPrice = _getPoolPrice();
        uint256 oraclePrice = _valueCollateral(1e18); // TODO: Switch this so it pulls token decimals from the pair token

        uint256 lowerBound = (oraclePrice * (PRECISION - THRESHOLD)) / PRECISION;
        uint256 upperBound = (oraclePrice * (PRECISION + THRESHOLD)) / PRECISION;

        return poolPrice >= lowerBound && poolPrice <= upperBound;
    }

    function _deposit(uint256 ohmAmount_, uint256 pairAmount_) internal virtual returns (uint256) {}

    function _withdraw(uint256 lpAmount_) internal virtual returns (uint256, uint256) {}

    function _updateRewardState() internal {
        // Update reward state and user's reward debts
        uint256 numRewardTokens = rewardTokens.length;
        uint256 totalLP = ERC20(lpToken).balanceOf(address(this));

        for (uint256 i; i < numRewardTokens; ) {
            RewardToken storage rewardToken = rewardTokens[i];

            // Update reward state
            if (block.timestamp > rewardToken.lastRewardTime && totalLP != 0) {
                uint256 timeDiff = block.timestamp - rewardToken.lastRewardTime;
                uint256 totalRewards = timeDiff * rewardToken.rewardsPerSecond;

                rewardToken.accumulatedRewardsPerShare += (totalRewards * 1e18) / totalLP;
                rewardToken.lastRewardTime = block.timestamp;
            }

            unchecked {
                ++i;
            }
        }
    }

    function _claimRewards() internal returns (uint256) {
        uint256 numRewardTokens = rewardTokens.length;
        for (uint256 i; i < numRewardTokens; ) {
            RewardToken memory rewardToken = rewardTokens[i];
            uint256 reward = rewardsForToken(i, msg.sender);
            if (reward > 0) {
                ERC20(rewardToken.token).transfer(msg.sender, reward);
            }

            unchecked {
                ++i;
            }
        }
    }

    // TODO: Decide if we want to use the LENDR for this or not
    function _borrow(uint256 amount_) internal {
        LENDR.borrow(amount_);
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(address(this), amount_);
    }

    // TODO: Decide if we want to use the LENDR for this or not
    // TODO: Need a way to report net minted amount
    function _repay(uint256 amount_) internal {
        MINTR.burnOhm(address(this), amount_);
        LENDR.repay(amount_);
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    function addRewardToken(
        address token_,
        uint256 rewardsPerSecond_,
        uint256 startTimestamp_
    ) external onlyRole("liquidityamo_admin") {
        RewardToken memory newRewardToken = RewardToken({
            token: token_,
            rewardsPerSecond: rewardsPerSecond_,
            lastRewardTime: block.timestamp > startTimestamp_ ? block.timestamp : startTimestamp_,
            accumulatedRewardsPerShare: 0
        });

        rewardTokens.push(newRewardToken);
    }

    function setThreshold(uint256 threshold_) external onlyRole("liquidityamo_admin") {
        THRESHOLD = threshold_;
    }

    function setFee(uint256 fee_) external onlyRole("liquidityamo_admin") {
        FEE = fee_;
    }
}
