// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IRewardDistributor} from "./IRewardDistributor.sol";

/// @title IVaultRewardDistributor
/// @notice Interface for ERC4626 vault-based reward distributors.
/// @dev Extends IRewardDistributor with vault-specific functionality.
interface IVaultRewardDistributor is IRewardDistributor {
    // ========== EVENTS ========== //

    /// @notice Emitted when an epoch ends with vault token rewards.
    /// @dev Emitted alongside MerkleRootSet to provide token-specific info.
    ///
    /// @param epochEndDate The end of the completed epoch (23:59:59 UTC).
    /// @param rewardToken The address of the reward token.
    event EpochEnded(uint256 indexed epochEndDate, address indexed rewardToken);

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
}
