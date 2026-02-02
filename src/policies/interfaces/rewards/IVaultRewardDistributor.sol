// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IRewardDistributor} from "src/policies/interfaces/rewards/IRewardDistributor.sol";

/// @title IVaultRewardDistributor
/// @notice The interface for ERC4626 vault-based reward distributors.
/// @dev It extends IRewardDistributor with vault-specific functionality.
interface IVaultRewardDistributor is IRewardDistributor {
    // ========== STRUCTS ========== //

    /// @notice Parameters for claiming rewards from vault-based distributors.
    /// @dev Used for encoding/decoding params_ in claim.
    struct ClaimParams {
        bool asVaultToken;
    }

    // ========== EVENTS ========== //

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

    // ========== USER FUNCTIONS ========== //

    /// @notice Claims rewards for specified epochs.
    /// @param epochEndDates_ The list of epoch end dates being claimed for.
    /// @param amounts_ The claimable amounts corresponding to the epochs.
    /// @param proofs_ The Merkle proofs corresponding to each epoch.
    /// @param params_ The encoded ClaimParams struct (abi.encode(ClaimParams)).
    /// @return rewardToken The address of the token transferred.
    /// @return tokensTransferred The amount of tokens transferred.
    function claim(
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bytes calldata params_
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
