// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IHeart} from "policies/interfaces/IHeart.sol";
import {IOperator} from "policies/interfaces/IOperator.sol";

import {OlympusPrice} from "modules/PRICE.sol";

import "src/Kernel.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title  Olympus Heart
/// @notice Olympus Heart (Policy) Contract
/// @dev    The Olympus Heart contract provides keeper rewards to call the heart beat function which fuels
///         Olympus market operations. The Heart orchestrates state updates in the correct order to ensure
///         market operations use up to date information.
contract OlympusHeart is IHeart, Policy, ReentrancyGuard {
    using TransferHelper for ERC20;

    error Heart_OutOfCycle();
    error Heart_BeatStopped();
    error Heart_InvalidParams();

    event Beat(uint256 timestamp_);
    event RewardIssued(address to_, uint256 rewardAmount_);
    event RewardUpdated(ERC20 token_, uint256 rewardAmount_);

    /// @notice Status of the Heart, false = stopped, true = beating
    bool public active;

    /// @notice Timestamp of the last beat (UTC, in seconds)
    uint256 public lastBeat;

    /// @notice Reward for beating the Heart (in reward token decimals)
    uint256 public reward;

    /// @notice Reward token address that users are sent for beating the Heart
    ERC20 public rewardToken;

    // Modules
    OlympusPrice internal PRICE;

    // Policies
    IOperator internal _operator;

    /*//////////////////////////////////////////////////////////////
                            POLICY INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(
        Kernel kernel_,
        IOperator operator_,
        ERC20 rewardToken_,
        uint256 reward_
    ) Policy(kernel_) {
        _operator = operator_;

        active = true;
        lastBeat = block.timestamp;
        rewardToken = rewardToken_;
        reward = reward_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("PRICE");

        PRICE = OlympusPrice(getModuleAddress(dependencies[0]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](1);
        permissions[0] = Permissions(PRICE.KEYCODE(), PRICE.updateMovingAverage.selector);
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHeart
    function beat() external nonReentrant {
        if (!active) revert Heart_BeatStopped();
        if (block.timestamp < lastBeat + frequency()) revert Heart_OutOfCycle();

        // Update the moving average on the Price module
        PRICE.updateMovingAverage();

        // Trigger price range update and market operations
        _operator.operate();

        // Update the last beat timestamp
        lastBeat += frequency();

        // Issue reward to sender
        _issueReward(msg.sender);

        emit Beat(block.timestamp);
    }

    function _issueReward(address to_) internal {
        rewardToken.safeTransfer(to_, reward);
        emit RewardIssued(to_, reward);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHeart
    function frequency() public view returns (uint256) {
        return uint256(PRICE.observationFrequency());
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHeart
    function resetBeat() external onlyRole("heart_admin") {
        lastBeat = block.timestamp - frequency();
    }

    /// @inheritdoc IHeart
    function toggleBeat() external onlyRole("heart_admin") {
        active = !active;
    }

    /// @inheritdoc IHeart
    function setRewardTokenAndAmount(ERC20 token_, uint256 reward_)
        external
        onlyRole("heart_admin")
    {
        rewardToken = token_;
        reward = reward_;
        emit RewardUpdated(token_, reward_);
    }

    /// @inheritdoc IHeart
    function withdrawUnspentRewards(ERC20 token_) external onlyRole("heart_admin") {
        token_.safeTransfer(msg.sender, token_.balanceOf(address(this)));
    }
}
