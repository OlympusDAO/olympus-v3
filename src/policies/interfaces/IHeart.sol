// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IHeart {
    /* ========== KEEPER FUNCTIONS ========== */
    /// @notice Beats the heart
    /// @notice Only callable when enough time has passed since last beat (determined by frequency variable)
    /// @notice This function is incentivized with an OHM reward
    /// @dev    Triggers price oracle update and market operations
    function beat() external;

    /* ========== ADMIN FUNCTIONS ========== */
    /// @notice Unlocks the cycle if stuck on one side, eject function
    /// @notice Access restricted
    function resetBeat() external;

    /// @notice Turns the heart on or off, emergency stop and resume function
    /// @notice Access restricted
    function toggleBeat() external;

    /// @notice           Sets the keeper reward for the beat function
    /// @notice           Access restricted
    /// @param reward_    New reward amount, in units of the reward token
    function setReward(uint256 reward_) external;

    /// @notice           Sets the reward token for the beat function
    /// @notice           Access restricted
    /// @param token_     New reward token address
    function setRewardToken(ERC20 token_) external;

    /// @notice           Withdraws unspent balance of provided token to sender
    /// @notice           Access restricted
    function withdrawUnspentRewards(ERC20 token_) external;

    /// @notice           Sets the frequency of the beat, in seconds
    /// @notice           Access restricted
    /// @param frequency_ Frequency of the beat, in seconds
    function setFrequency(uint256 frequency_) external;
}
