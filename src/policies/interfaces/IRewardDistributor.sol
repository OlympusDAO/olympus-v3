// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

/// @title  IRewardDistributor
/// @notice Interface for the Reward Distributor contract
interface IRewardDistributor is IERC165 {
    // ========== EVENTS ========== //

    /// @notice Emitted when a Merkle root is set for a completed epoch
    /// @dev    The `epochEndDate` is the END of the epoch whose rewards are being finalized.
    ///         The next epoch starts 1 second after `epochEndDate`.
    ///
    /// @param  epochEndDate    The end of the completed epoch (23:59:59 UTC)
    /// @param  merkleRoot      The Merkle root containing accumulated rewards for that epoch
    /// @param  rewardToken     The address of the reward token
    event MerkleRootSet(uint256 indexed epochEndDate, bytes32 merkleRoot, address rewardToken);

    /// @notice Emitted when a user successfully claims their rewards
    /// @dev    If `vaultShares` is 0, the user claimed as underlying token.
    ///         If `vaultShares` > 0, the user claimed as vault token.
    ///
    /// @param  user            The address of the user claiming rewards
    /// @param  rewardAmount    The total amount of underlying rewards claimed
    /// @param  vaultShares     The amount of vault shares transferred (0 if claimed as underlying)
    /// @param  epochEndDates   The epoch end dates claimed for
    event RewardsClaimed(
        address indexed user,
        uint256 rewardAmount,
        uint256 vaultShares,
        uint256[] epochEndDates
    );

    // ========== ERRORS ========== //

    /// @notice Thrown when the Merkle root for an epoch is already set
    ///
    /// @param  epochEndDate    The epoch end date in question
    error RewardDistributor_EpochAlreadySet(uint256 epochEndDate);

    /// @notice Thrown when an invalid Merkle proof is submitted
    error RewardDistributor_InvalidProof();

    /// @notice Thrown when no epochs are specified for a claim
    error RewardDistributor_NoEpochsSpecified();

    /// @notice Thrown when a Merkle root has not been set for a given epoch
    ///
    /// @param  epochEndDate    The epoch end date missing a Merkle root
    error RewardDistributor_MerkleRootNotSet(uint256 epochEndDate);

    /// @notice Thrown when provided arrays are not the same length
    error RewardDistributor_ArrayLengthMismatch();

    /// @notice Thrown when an invalid address is provided
    error RewardDistributor_InvalidAddress();

    /// @notice Thrown when ending an epoch before required time has elapsed
    error RewardDistributor_EpochTooEarly();

    /// @notice Thrown when the epoch timestamp is invalid (not at day boundary)
    error RewardDistributor_InvalidEpochTimestamp();

    /// @notice Thrown when the epoch start date is zero
    error RewardDistributor_EpochIsZero();

    /// @notice Thrown when no rewards are claimable
    error RewardDistributor_NothingToClaim();

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice End an epoch and set its Merkle root
    /// @dev    The epochEndDate must be at 23:59:59 UTC (end of day)
    ///
    /// @param  epochEndDate_   The epoch end date (23:59:59 UTC timestamp)
    /// @param  merkleRoot_     The Merkle root to be set
    function endEpoch(uint40 epochEndDate_, bytes32 merkleRoot_) external;

    // ========== USER FUNCTIONS ========== //

    /// @notice Claim rewards for specified epochs
    ///
    /// @param  epochEndDates_      The list of epoch end dates being claimed for
    /// @param  amounts_            The claimable amounts corresponding to the epochs
    /// @param  proofs_             Merkle proofs corresponding to each epoch
    /// @param  asVaultToken_       Whether to receive rewards as vault token or as the underlying
    /// @return rewardToken         The address of the token transferred (vault token if asVaultToken_, otherwise underlying)
    /// @return tokensTransferred   The amount of tokens transferred (vault shares if asVaultToken_, otherwise underlying)
    function claim(
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bool asVaultToken_
    ) external returns (address rewardToken, uint256 tokensTransferred);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Preview claimable amount and (optionally) vault shares for a claim
    ///
    /// @param  user_               The recipient of the rewards
    /// @param  epochEndDates_      List of epoch end dates being previewed for claim
    /// @param  amounts_            The amounts to claim for each epoch
    /// @param  proofs_             Merkle proofs for each epoch
    /// @return claimableAmount     The amount of rewards the user can claim
    /// @return vaultShares         The amount of vault shares the user would receive (if applicable)
    function previewClaim(
        address user_,
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares);

    /// @notice Returns the start timestamp for first epoch (00:00:00 UTC)
    ///
    /// @return The timestamp when first epoch starts
    function EPOCH_START_DATE() external view returns (uint40);

    /// @notice Returns the Merkle root for a given epoch
    ///
    /// @param  epochEndDate    The epoch end date to get the Merkle root for
    /// @return                 The Merkle root bytes32 value
    function epochMerkleRoots(uint256 epochEndDate) external view returns (bytes32);

    /// @notice Returns whether a user has already claimed rewards for a given epoch
    ///
    /// @param  user            The user address to check for
    /// @param  epochEndDate    The epoch end date to check for
    /// @return                 Whether the user has claimed for this epoch
    function hasClaimed(address user, uint256 epochEndDate) external view returns (bool);

    /// @notice Returns the last epoch end date for which a merkle root was set
    ///
    /// @return                 The last epoch end date
    function lastEpochEndDate() external view returns (uint40);
}
