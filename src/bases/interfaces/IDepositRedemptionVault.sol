// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IDepositRedemptionVault
/// @notice Interface for a contract that can manage the redemption of receipt tokens for their deposit
interface IDepositRedemptionVault {
    // ========== EVENTS ========== //

    event Committed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event Redeemed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event Uncommitted(
        address indexed user,
        uint16 indexed commitmentId,
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

    error RedemptionVault_InvalidCommitmentId(address user, uint16 commitmentId);

    error RedemptionVault_InvalidAmount(address user, uint16 commitmentId, uint256 amount);

    error RedemptionVault_TooEarly(address user, uint16 commitmentId);

    error RedemptionVault_AlreadyRedeemed(address user, uint16 commitmentId);

    // ========== DATA STRUCTURES ========== //

    /// @notice Data structure for a commitment to redeem a receipt token
    ///
    /// @param  depositToken    The address of the deposit token
    /// @param  depositPeriod   The period of the deposit in months
    /// @param  amount          The amount of deposit tokens committed
    /// @param  redeemableAt    The timestamp at which the commitment can be redeemed
    struct UserCommitment {
        IERC20 depositToken;
        uint8 depositPeriod;
        uint256 amount;
        uint48 redeemableAt;
    }

    // ========== REDEMPTION FLOW ========== //

    /// @notice Gets the details of a user's redeem commitment
    ///
    /// @param  user_            The address of the user
    /// @param  commitmentId_    The ID of the commitment
    /// @return commitment       The details of the commitment
    function getRedeemCommitment(
        address user_,
        uint16 commitmentId_
    ) external view returns (UserCommitment memory commitment);

    /// @notice Gets the number of redeem commitments a user has made
    ///
    /// @param  user_ The address of the user
    /// @return count The number of redeem commitments
    function getRedeemCommitmentCount(address user_) external view returns (uint16 count);

    /// @notice Commits to redeem a quantity of deposit tokens
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  amount_         The amount of deposit tokens to commit
    /// @return commitmentId    The ID of the user commitment
    function commitRedeem(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external returns (uint16 commitmentId);

    /// @notice Revokes a commitment to redeem a quantity of deposit tokens
    ///
    /// @param  commitmentId_ The ID of the user commitment
    /// @param  amount_       The amount of deposit tokens to uncommit
    function uncommitRedeem(uint16 commitmentId_, uint256 amount_) external;

    /// @notice Redeems deposit tokens that has been committed
    /// @dev    This function does not take an amount as an argument, because the amount is determined by the commitment
    ///
    /// @param  commitmentId_ The ID of the user commitment
    function redeem(uint16 commitmentId_) external;

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
