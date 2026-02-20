// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

/// @title IRewardDistributor
/// @notice Interface for Merkle tree-based reward distributors
interface IRewardDistributor is IERC165 {
    // ========== EVENTS ========== //

    /// @notice Emitted when a Merkle root is set for a completed epoch.
    /// @dev The `epochEndDate` is the END of the epoch whose rewards are being finalized.
    ///      The next epoch starts 1 second after `epochEndDate`.
    ///      Token-specific information should be emitted in derived contract events.
    ///
    /// @param epochEndDate The end of the completed epoch (23:59:59 UTC).
    /// @param merkleRoot The Merkle root containing accumulated rewards for that epoch.
    event MerkleRootSet(uint256 indexed epochEndDate, bytes32 merkleRoot);

    /// @notice Emitted when an epoch ends with rewards configured.
    /// @param epochEndDate The end of the completed epoch (23:59:59 UTC).
    /// @param token The reward token address for this epoch.
    /// @param params Implementation-specific parameters (abi.encoded).
    event EpochEnded(uint256 indexed epochEndDate, address indexed token, bytes params);

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

    /// @notice Thrown when a user tries to claim rewards for an epoch they have already claimed
    ///
    /// @param  epochEndDate    The epoch end date that was already claimed
    error RewardDistributor_AlreadyClaimed(uint256 epochEndDate);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Ends an epoch and sets its Merkle root.
    /// @param epochEndDate_ The epoch end date (23:59:59 UTC timestamp).
    /// @param merkleRoot_ The Merkle root to be set.
    /// @param params_ Implementation-specific parameters (abi.encoded).
    /// @return token The token address for this epoch's rewards.
    function endEpoch(
        uint40 epochEndDate_,
        bytes32 merkleRoot_,
        bytes calldata params_
    ) external returns (address token);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the start timestamp for first epoch (00:00:00 UTC)
    ///
    /// @return epochStartDate The timestamp when first epoch starts
    function EPOCH_START_DATE() external view returns (uint40 epochStartDate);

    /// @notice Returns the Merkle root for a given epoch
    ///
    /// @param  epochEndDate    The epoch end date to get the Merkle root for
    /// @return merkleRoot      The Merkle root bytes32 value
    function epochMerkleRoots(uint256 epochEndDate) external view returns (bytes32 merkleRoot);

    /// @notice Returns whether a user has already claimed rewards for a given epoch
    ///
    /// @param  user            The user address to check for
    /// @param  epochEndDate    The epoch end date to check for
    /// @return claimed         Whether the user has claimed for this epoch
    function hasClaimed(address user, uint256 epochEndDate) external view returns (bool claimed);

    /// @notice Returns the last epoch end date for which a merkle root was set
    ///
    /// @return epochEndDate    The last epoch end date
    function lastEpochEndDate() external view returns (uint40 epochEndDate);
}
