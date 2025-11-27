// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

/// @title  IRewardDistributor
/// @notice Interface for the Reward Distributor contract
interface IRewardDistributor is IERC165 {
    // ========== EVENTS ========== //

    /// @notice Emitted when a new Merkle root is set for an epoch
    ///
    /// @param  epochStartDate  The epoch start date for which the Merkle root is set
    /// @param  merkleRoot      The Merkle root for that epoch's distribution
    /// @param  rewardToken     The address of the reward token
    event MerkleRootSet(uint256 indexed epochStartDate, bytes32 merkleRoot, address rewardToken);

    /// @notice Emitted when a user successfully claims their rewards
    ///
    /// @param  user            The address of the user claiming rewards
    /// @param  totalAmount     The total amount of rewards claimed
    /// @param  rewardToken     The address of the reward token
    /// @param  epochCount      The number of epochs claimed for
    event RewardsClaimed(
        address indexed user,
        uint256 totalAmount,
        address rewardToken,
        uint256 epochCount
    );

    /// @notice Emitted when rewards are claimed as vault tokens
    ///
    /// @param  user            The address of the user claiming as vault token
    /// @param  rewardAmount    The total amount of underlying rewards
    /// @param  vaultShares     The amount of vault shares issued to the user
    /// @param  vaultToken      The address of the vault token
    /// @param  epochCount      The number of epochs claimed for
    event RewardsClaimedAsVaultToken(
        address indexed user,
        uint256 rewardAmount,
        uint256 vaultShares,
        address vaultToken,
        uint256 epochCount
    );

    // ========== ERRORS ========== //

    /// @notice Emitted when the Merkle root for an epoch is already set
    ///
    /// @param  epochStartDate  The epoch start date in question
    error RewardDistributor_EpochAlreadySet(uint256 epochStartDate);

    /// @notice Emitted when an invalid Merkle proof is submitted
    error RewardDistributor_InvalidProof();

    /// @notice Emitted when no epochs are specified for a claim
    error RewardDistributor_NoEpochsSpecified();

    /// @notice Emitted when a Merkle root has not been set for a given epoch
    ///
    /// @param  epochStartDate  The epoch start date missing a Merkle root
    error RewardDistributor_MerkleRootNotSet(uint256 epochStartDate);

    /// @notice Emitted when provided arrays are not the same length
    error RewardDistributor_ArrayLengthMismatch();

    /// @notice Emitted when an invalid address is provided
    error RewardDistributor_InvalidAddress();

    /// @notice Emitted when setting a Merkle root before required time has elapsed
    error RewardDistributor_EpochTooEarly();

    /// @notice Emitted when the epoch start date is not at the start of a day
    error RewardDistributor_EpochNotStartOfDay();

    /// @notice Emitted when the epoch start date is zero
    error RewardDistributor_EpochIsZero();

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Set the Merkle root for a specific epoch
    ///
    /// @param  epochStartDate_ The epoch start date to set the Merkle root for
    /// @param  merkleRoot_     The Merkle root to be set
    /// @return epochStartDate  The epoch start date at which the root was set
    function setMerkleRoot(
        uint40 epochStartDate_,
        bytes32 merkleRoot_
    ) external returns (uint256 epochStartDate);

    // ========== USER FUNCTIONS ========== //

    /// @notice Claim rewards for specified epochs
    ///
    /// @param  epochStartDates_ The list of epoch start dates being claimed for
    /// @param  amounts_        The claimable amounts corresponding to the epochs
    /// @param  proofs_         Merkle proofs corresponding to each epoch
    /// @param  asVaultToken_   Whether to receive rewards as vault token or as the underlying
    function claim(
        uint256[] calldata epochStartDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bool asVaultToken_
    ) external;

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Preview claimable amount and (optionally) vault shares for a claim
    ///
    /// @param  user_                   The recipient of the rewards
    /// @param  claimEpochStartDates_   List of epoch start dates being previewed for claim
    /// @param  amounts_                The amounts to claim for each epoch
    /// @param  proofs_                 Merkle proofs for each epoch
    /// @return claimableAmount         The amount of rewards the user can claim
    /// @return vaultShares             The amount of vault shares the user would receive (if applicable)
    function previewClaim(
        address user_,
        uint256[] calldata claimEpochStartDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares);

    /// @notice Returns the start timestamp for epoch 0
    ///
    /// @return The timestamp when epoch 0 starts
    function EPOCH_START_DATE() external view returns (uint40);

    /// @notice Returns the Merkle root for a given epoch
    ///
    /// @param  epochStartDate  The epoch start date to get the Merkle root for
    /// @return                 The Merkle root bytes32 value
    function epochMerkleRoots(uint256 epochStartDate) external view returns (bytes32);

    /// @notice Returns whether a user has already claimed rewards for a given epoch
    ///
    /// @param  user                The user address to check for
    /// @param  epochStartDate      The epoch start date to check for
    /// @return                     Whether the user has claimed for this epoch
    function hasClaimed(address user, uint256 epochStartDate) external view returns (bool);

    /// @notice Returns the last epoch start date for which a merkle root was set
    ///
    /// @return                 The last epoch start date
    function lastEpochStartDate() external view returns (uint40);
}
