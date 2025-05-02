// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

/// @title  IConvertibleDepositRedemptionVault
/// @notice Interface for a contract that can manage the redemption of convertible deposit (CD) tokens
interface IConvertibleDepositRedemptionVault {
    // ========== EVENTS ========== //

    event Committed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    event Redeemed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    event Uncommitted(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    // ========== ERRORS ========== //

    error CDRedemptionVault_InvalidCDToken(address cdToken);

    error CDRedemptionVault_ZeroAmount();

    error CDRedemptionVault_InvalidCommitmentId(address user, uint16 commitmentId);

    error CDRedemptionVault_InvalidAmount(address user, uint16 commitmentId, uint256 amount);

    error CDRedemptionVault_TooEarly(address user, uint16 commitmentId);

    error CDRedemptionVault_AlreadyRedeemed(address user, uint16 commitmentId);

    // ========== DATA STRUCTURES ========== //

    /// @notice Data structure for a commitment to redeem a CD token
    ///
    /// @param  cdToken         The address of the CD token
    /// @param  amount          The amount of CD tokens committed
    /// @param  redeemableAt    The timestamp at which the commitment can be redeemed
    struct UserCommitment {
        IConvertibleDepositERC20 cdToken;
        uint256 amount;
        uint48 redeemableAt;
    }

    // ========== MINT/BURN ========== //

    /// @notice Burn CD tokens from the caller
    ///
    /// @param  cdToken_    The address of the CD token
    /// @param  amount_     The amount of CD tokens to burn
    function burn(IConvertibleDepositERC20 cdToken_, uint256 amount_) external;

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

    /// @notice Commits to redeem a quantity of CD tokens
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  amount_         The amount of CD tokens to commit
    /// @return commitmentId    The ID of the user commitment
    function commitRedeem(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint16 commitmentId);

    /// @notice Revokes a commitment to redeem a quantity of CD tokens
    ///
    /// @param  commitmentId_ The ID of the user commitment
    /// @param  amount_       The amount of CD tokens to uncommit
    function uncommitRedeem(uint16 commitmentId_, uint256 amount_) external;

    /// @notice Redeems CD tokens that has been committed
    /// @dev    This function does not take an amount as an argument, because the amount is determined by the commitment
    ///
    /// @param  commitmentId_ The ID of the user commitment
    function redeem(uint16 commitmentId_) external;

    // ========== RECLAIM ========== //

    /// @notice Preview the amount of deposit token that would be reclaimed
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Returning the total amount of deposit tokens that would be reclaimed
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  amount_         The amount of CD tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the caller
    function previewReclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view returns (uint256 reclaimed);

    /// @notice Reclaims CD tokens, after applying a discount
    ///         CD tokens can be reclaimed at any time.
    ///         The caller is not required to have a position in the facility.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Burning the CD tokens
    ///         - Transferring the deposit token to `account_`
    ///         - Emitting an event
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  account_        The address to reclaim the deposit token to
    /// @param  amount_         The amount of CD tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the caller
    function reclaimFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external returns (uint256 reclaimed);

    /// @notice Reclaims CD tokens, after applying a discount
    /// @dev    This variant reclaims the underlying asset to the caller
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 reclaimed);
}
