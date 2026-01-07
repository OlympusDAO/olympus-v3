// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IRewardDistributor} from "src/policies/interfaces/IRewardDistributor.sol";
import {ConvertibleOHMToken} from "src/policies/rewards/convertible/ConvertibleOHMToken.sol";

/// @title IRewardDistributorConvertible
/// @notice The interface for reward distributors for Convertible OHM Tokens.
/// @dev It extends IRewardDistributor with convertible token-specific functionality.
interface IRewardDistributorConvertible is IRewardDistributor {
    // ========== EVENTS ========== //

    /// @notice Emitted when an epoch ends with a newly deployed convertible OHM token.
    /// @dev Emitted alongside MerkleRootSet to provide token-specific info.
    /// @param epochEndDate The end of the completed epoch (23:59:59 UTC).
    /// @param convertibleToken The convertible token for this epoch's rewards.
    /// @param quoteToken The ERC20 token that the user will need to provide on exercise.
    /// @param eligible The timestamp at which the convertible token can first be exercised.
    /// @param expiry The timestamp at which the convertible token can no longer be exercised.
    /// @param strikePrice The strike price of the convertible token (in units of the `quoteToken_` per OHM).
    event EpochEnded(
        uint256 indexed epochEndDate,
        ConvertibleOHMToken indexed convertibleToken,
        address indexed quoteToken,
        uint48 eligible,
        uint48 expiry,
        uint256 strikePrice
    );

    /// @notice Emitted when a user successfully claims their convertible tokens for an epoch.
    /// @param user The address of the user claiming rewards.
    /// @param convertibleToken The address of the convertible token claimed.
    /// @param amount The amount of convertible tokens claimed for this epoch.
    /// @param epochEndDate The epoch end date claimed for.
    event ConvertibleTokensClaimed(
        address indexed user,
        ConvertibleOHMToken indexed convertibleToken,
        uint256 amount,
        uint256 indexed epochEndDate
    );

    // ========== ERRORS ========== //

    /// @notice Thrown when an invalid token is referenced.
    error RewardDistributor_InvalidToken();

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Ends an epoch, deploys a new convertible token, and sets a merkle root.
    /// @dev The epochEndDate_ should be at 23:59:59 UTC (end of day).
    ///      Creates a new ConvertibleOHMToken via the teller.
    /// @param epochEndDate_ The epoch end date (23:59:59 UTC timestamp).
    /// @param merkleRoot_ The Merkle root to be set.
    /// @param quoteToken_ The ERC20 token that the user will need to provide on exercise.
    /// @param eligible_ The timestamp at which the convertible token can first be exercised.
    /// @param expiry_ The timestamp at which the convertible token can no longer be exercised.
    /// @param strikePrice_ The strike price of the convertible token (in units of the `quoteToken_` per OHM).
    /// @return token The newly deployed convertible token.
    function endEpoch(
        uint40 epochEndDate_,
        bytes32 merkleRoot_,
        address quoteToken_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) external returns (ConvertibleOHMToken token);

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
    ) external returns (ConvertibleOHMToken[] memory tokens, uint256[] memory mintedAmounts);

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
    )
        external
        view
        returns (ConvertibleOHMToken[] memory tokens, uint256[] memory claimableAmounts);

    /// @notice Returns a convertible OHM token for a specific epoch.
    /// @param epochEndDate_ The epoch end date.
    /// @return The address of the convertible OHM token.
    function epochConvertibleTokens(
        uint256 epochEndDate_
    ) external view returns (ConvertibleOHMToken);
}
