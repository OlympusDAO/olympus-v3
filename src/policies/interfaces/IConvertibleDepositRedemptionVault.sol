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

    // ========== ERRORS ========== //

    error CDRedemptionVault_InvalidCDToken(address cdToken);

    error CDRedemptionVault_ZeroAmount(address user);

    error CDRedemptionVault_InvalidCommitmentId(address user, uint16 commitmentId);

    error CDRedemptionVault_InvalidAmount(address user, uint16 commitmentId, uint256 amount);

    error CDRedemptionVault_TooEarly(address user, uint16 commitmentId);

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

    // ========== USER COMMITMENTS ========== //

    /// @notice Gets the details of a user's commitment
    ///
    /// @param  user_            The address of the user
    /// @param  commitmentId_    The ID of the commitment
    /// @return commitment       The details of the commitment
    function getUserCommitment(
        address user_,
        uint16 commitmentId_
    ) external view returns (UserCommitment memory commitment);

    /// @notice Gets the number of commitments a user has made
    ///
    /// @param  user_ The address of the user
    /// @return count The number of commitments
    function getUserCommitmentCount(address user_) external view returns (uint16 count);

    // ========== REDEMPTION FLOW ========== //

    /// @notice Commits to redeem a quantity of CD tokens
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  amount_         The amount of CD tokens to commit
    /// @return commitmentId    The ID of the user commitment
    function commit(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint16 commitmentId);

    /// @notice Revokes a commitment to redeem a quantity of CD tokens
    ///
    /// @param  commitmentId_ The ID of the user commitment
    /// @param  amount_       The amount of CD tokens to uncommit
    function uncommit(uint16 commitmentId_, uint256 amount_) external;

    /// @notice Redeems CD tokens that has been committed
    /// @dev    This function does not take an amount as an argument, because the amount is determined by the commitment
    ///
    /// @param  commitmentId_ The ID of the user commitment
    function redeem(uint16 commitmentId_) external;
}
