// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IDepositRedemptionVault
/// @notice Interface for a contract that can manage the redemption of receipt tokens for their deposit
interface IDepositRedemptionVault {
    // ========== EVENTS ========== //

    event RedemptionStarted(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event RedemptionFinished(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event RedemptionCancelled(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    // ========== ERRORS ========== //

    error RedemptionVault_InvalidToken(address depositToken, uint8 depositPeriod);

    error RedemptionVault_ZeroAmount();

    error RedemptionVault_InvalidRedemptionId(address user, uint16 redemptionId);

    error RedemptionVault_InvalidAmount(address user, uint16 redemptionId, uint256 amount);

    error RedemptionVault_TooEarly(address user, uint16 redemptionId);

    error RedemptionVault_AlreadyRedeemed(address user, uint16 redemptionId);

    // ========== DATA STRUCTURES ========== //

    /// @notice Data structure for a redemption of a receipt token
    ///
    /// @param  depositToken    The address of the deposit token
    /// @param  depositPeriod   The period of the deposit in months
    /// @param  redeemableAt    The timestamp at which the redemption can be finished
    /// @param  amount          The amount of deposit tokens to redeem
    struct UserRedemption {
        address depositToken;
        uint8 depositPeriod;
        uint48 redeemableAt;
        uint256 amount;
    }

    // ========== REDEMPTION FLOW ========== //

    /// @notice Gets the details of a user's redemption
    ///
    /// @param  user_            The address of the user
    /// @param  redemptionId_    The ID of the redemption
    /// @return redemption       The details of the redemption
    function getUserRedemption(
        address user_,
        uint16 redemptionId_
    ) external view returns (UserRedemption memory redemption);

    /// @notice Gets the number of redemptions a user has started
    ///
    /// @param  user_ The address of the user
    /// @return count The number of redemptions
    function getUserRedemptionCount(address user_) external view returns (uint16 count);

    /// @notice Starts a redemption of a quantity of deposit tokens
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  amount_         The amount of deposit tokens to redeem
    /// @return redemptionId    The ID of the user redemption
    function startRedemption(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external returns (uint16 redemptionId);

    /// @notice Cancels a redemption of a quantity of deposit tokens
    ///
    /// @param  redemptionId_ The ID of the user redemption
    /// @param  amount_       The amount of deposit tokens to cancel
    function cancelRedemption(uint16 redemptionId_, uint256 amount_) external;

    /// @notice Finishes a redemption of a quantity of deposit tokens
    /// @dev    This function does not take an amount as an argument, because the amount is determined by the redemption
    ///
    /// @param  redemptionId_   The ID of the user redemption
    function finishRedemption(uint16 redemptionId_) external;

    // ========== RECLAIM ========== //

    /// @notice Preview the amount of deposit token that would be reclaimed
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Returning the total amount of deposit tokens that would be reclaimed
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  amount_         The amount of deposit tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the caller
    function previewReclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external view returns (uint256 reclaimed);

    /// @notice Reclaims deposit tokens, after applying a discount
    ///         Deposit tokens can be reclaimed at any time.
    ///         The caller is not required to have a position in the facility.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Burning the receipt tokens
    ///         - Transferring the deposit token to `recipient_`
    ///         - Emitting an event
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  recipient_      The address to reclaim the deposit token to
    /// @param  amount_         The amount of deposit tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the recipient
    function reclaimFor(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        address recipient_,
        uint256 amount_
    ) external returns (uint256 reclaimed);

    /// @notice Reclaims deposit tokens, after applying a discount
    /// @dev    This variant reclaims the underlying asset to the caller
    function reclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external returns (uint256 reclaimed);
}
