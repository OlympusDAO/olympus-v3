// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

/// @title  IRewardDistributor
/// @notice Interface for the Reward Distributor contract
interface IRewardDistributor is IERC165 {
    // ========== EVENTS ========== //

    /// @notice Emitted when a new Merkle root is set for a week
    ///
    /// @param  week            The week number for which the Merkle root is set
    /// @param  merkleRoot      The Merkle root for that week's distribution
    /// @param  rewardToken     The address of the reward token
    event MerkleRootSet(uint256 indexed week, bytes32 merkleRoot, address rewardToken);

    /// @notice Emitted when a user successfully claims their rewards
    ///
    /// @param  user            The address of the user claiming rewards
    /// @param  totalAmount     The total amount of rewards claimed
    /// @param  rewardToken     The address of the reward token
    /// @param  weekCount       The number of weeks claimed for
    event RewardsClaimed(
        address indexed user,
        uint256 totalAmount,
        address rewardToken,
        uint256 weekCount
    );

    /// @notice Emitted when rewards are claimed as vault tokens
    ///
    /// @param  user            The address of the user claiming as vault token
    /// @param  rewardAmount    The total amount of underlying rewards
    /// @param  vaultShares     The amount of vault shares issued to the user
    /// @param  vaultToken      The address of the vault token
    /// @param  weekCount       The number of weeks claimed for
    event RewardsClaimedAsVaultToken(
        address indexed user,
        uint256 rewardAmount,
        uint256 vaultShares,
        address vaultToken,
        uint256 weekCount
    );

    // ========== ERRORS ========== //

    /// @notice Emitted when the Merkle root for a week is already set
    ///
    /// @param  week            The week in question
    error RewardDistributor_WeekAlreadySet(uint256 week);

    /// @notice Emitted when an invalid Merkle proof is submitted
    error RewardDistributor_InvalidProof();

    /// @notice Emitted when no weeks are specified for a claim
    error RewardDistributor_NoWeeksSpecified();

    /// @notice Emitted when a Merkle root has not been set for a given week
    ///
    /// @param  week            The week missing a Merkle root
    error RewardDistributor_MerkleRootNotSet(uint256 week);

    /// @notice Emitted when provided arrays are not the same length
    error RewardDistributor_ArrayLengthMismatch();

    /// @notice Emitted when an invalid address is provided
    error RewardDistributor_InvalidAddress();

    /// @notice Emitted when setting a Merkle root before week has elapsed
    error RewardDistributor_WeekTooEarly();

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Set the Merkle root for a specific week
    ///
    /// @param  week_           The week number to set the Merkle root for
    /// @param  merkleRoot_     The Merkle root to be set
    /// @return timestamp       The timestamp at which the root was set
    function setMerkleRoot(uint40 week_, bytes32 merkleRoot_) external returns (uint256 timestamp);

    // ========== USER FUNCTIONS ========== //

    /// @notice Claim rewards for specified weeks
    ///
    /// @param  weeks_          The list of weeks being claimed for
    /// @param  amounts_        The claimable amounts corresponding to the weeks
    /// @param  proofs_         Merkle proofs corresponding to each week
    /// @param  asVaultToken_   Whether to receive rewards as vault token or as the underlying
    function claim(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bool asVaultToken_
    ) external;

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Preview claimable amount and (optionally) vault shares for a claim
    ///
    /// @param  user_               The recipient of the rewards
    /// @param  claimWeeks_         List of weeks being previewed for claim
    /// @param  amounts_            The amounts to claim for each week
    /// @param  proofs_             Merkle proofs for each week
    /// @return claimableAmount     The amount of rewards the user can claim
    /// @return vaultShares         The amount of vault shares the user would receive (if applicable)
    function previewClaim(
        address user_,
        uint256[] calldata claimWeeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares);

    /// @notice Returns the start timestamp for week 0
    ///
    /// @return The timestamp when week 0 starts
    function START_TIMESTAMP() external view returns (uint40);

    /// @notice Returns the duration of a week in seconds
    ///
    /// @return The length of a week
    function WEEK_DURATION() external view returns (uint256);

    /// @notice Returns the Merkle root for a given week
    ///
    /// @param  week            The week to get the Merkle root for
    /// @return                 The Merkle root bytes32 value
    function weeklyMerkleRoots(uint256 week) external view returns (bytes32);

    /// @notice Returns whether a user has already claimed rewards for a given week
    ///
    /// @param  user            The user address to check for
    /// @param  week            The week to check for
    /// @return                 Whether the user has claimed for this week
    function hasClaimed(address user, uint256 week) external view returns (bool);
}
