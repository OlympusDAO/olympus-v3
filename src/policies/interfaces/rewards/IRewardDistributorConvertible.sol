// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IRewardDistributor} from "src/policies/interfaces/rewards/IRewardDistributor.sol";

/// @title IRewardDistributorConvertible
/// @notice The interface for reward distributors for Convertible OHM Tokens.
/// @dev It extends IRewardDistributor with convertible token-specific functionality.
interface IRewardDistributorConvertible is IRewardDistributor {
    // ========== STRUCTS ========== //

    /// @notice Parameters for ending an epoch with convertible tokens.
    /// @dev Used for encoding/decoding params_ in endEpoch.
    struct EndEpochParams {
        address quoteToken;
        uint48 eligible;
        uint48 expiry;
        uint256 strikePrice;
    }

    // ========== EVENTS ========== //

    /// @notice Emitted when a user successfully claims their convertible tokens for an epoch.
    /// @param user The address of the user claiming rewards.
    /// @param convertibleToken The address of the convertible token claimed.
    /// @param amount The amount of convertible tokens claimed for this epoch.
    /// @param epochEndDate The epoch end date claimed for.
    event ConvertibleTokensClaimed(
        address indexed user,
        address indexed convertibleToken,
        uint256 amount,
        uint256 indexed epochEndDate
    );

    // ========== ERRORS ========== //

    /// @notice Thrown when an invalid token is referenced.
    error RewardDistributor_InvalidToken();

    // ========== USER FUNCTIONS ========== //

    /// @notice Claims convertible tokens for specified epochs.
    /// @param epochEndDates_ The list of epoch end dates being claimed for.
    /// @param amounts_ The claimable amounts corresponding to the epochs.
    /// @param proofs_ The Merkle proofs corresponding to each epoch.
    /// @return tokens The array of convertible tokens minted (one per epoch).
    /// @return mintedAmounts The array of amounts minted (one per epoch).
    function claim(
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external returns (address[] memory tokens, uint256[] memory mintedAmounts);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Previews claimable tokens and amounts for a user.
    /// @param user_ The recipient of the rewards.
    /// @param epochEndDates_ The list of epoch end dates being previewed.
    /// @param amounts_ The amounts to claim for each epoch.
    /// @param proofs_ The Merkle proofs for each epoch.
    /// @return tokens The array of convertible tokens that would be minted.
    /// @return claimableAmounts The array of amounts claimable per epoch.
    function previewClaim(
        address user_,
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (address[] memory tokens, uint256[] memory claimableAmounts);

    /// @notice Returns a convertible OHM token for a specific epoch.
    /// @param epochEndDate_ The epoch end date.
    /// @return The address of the convertible OHM token.
    function epochConvertibleTokens(uint256 epochEndDate_) external view returns (address);
}
