// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IConvertibleDepositRedemptionVault} from "../interfaces/IConvertibleDepositRedemptionVault.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title  CDRedemptionVault
/// @notice A contract that manages the redemption of convertible deposit (CD) tokens
abstract contract CDRedemptionVault is IConvertibleDepositRedemptionVault {
    using SafeTransferLib for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice The number of commitments per user
    mapping(address => uint16) internal _userCommitmentCount;

    /// @notice The commitments for each user and commitment ID
    mapping(address => mapping(uint16 => UserCommitment)) internal _userCommitments;

    /// @notice The address of the CDEPO module
    /// @dev    The inheriting contract must assign the CDEPO module address to this state variable using `configureDependencies()`
    IConvertibleDepository internal _CDEPO;

    // ========== USER COMMITMENTS ========== //

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function getUserCommitmentCount(address user_) external view returns (uint16 count) {
        return _userCommitmentCount[user_];
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    function getUserCommitment(
        address user_,
        uint16 commitmentId_
    ) external view returns (UserCommitment memory commitment) {
        commitment = _userCommitments[user_][commitmentId_];
        if (commitment.cdToken == IConvertibleDepositERC20(address(0)))
            revert CDRedemptionVault_InvalidCommitmentId(user_, commitmentId_);

        return commitment;
    }

    // ========== REDEMPTION FLOW ========== //

    modifier onlyValidCommitmentId(address user_, uint16 commitmentId_) {
        // If the CD token is the zero address, the commitment is invalid
        if (address(_userCommitments[user_][commitmentId_].cdToken) == address(0))
            revert CDRedemptionVault_InvalidCommitmentId(user_, commitmentId_);
        _;
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the CD token is configured in the CDEPO module
    ///             - Creates a new commitment for the user
    ///             - Transfers the CD tokens from the caller to this contract
    ///             - Emits the Committed event
    ///             - Returns the new commitment ID
    ///
    ///             The function will revert if:
    ///             - The CD token is not configured in the CDEPO module
    ///             - The caller has not approved this contract to spend the CD tokens
    ///             - The caller does not have enough CD tokens
    function commit(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint16 commitmentId) {
        // Check that the CD token is valid
        if (!_CDEPO.isConvertibleDepositToken(address(cdToken_)))
            revert CDRedemptionVault_InvalidCDToken(address(cdToken_));

        // Create a User Commitment
        commitmentId = _userCommitmentCount[msg.sender]++;
        _userCommitments[msg.sender][commitmentId] = UserCommitment({
            cdToken: cdToken_,
            amount: amount_,
            redeemableAt: uint48(block.timestamp + cdToken_.periodMonths() * 30 days)
        });

        // Transfer the CD tokens from the caller to this contract
        ERC20(address(cdToken_)).safeTransferFrom(msg.sender, address(this), amount_);

        // Return the new commitment ID
        emit Committed(msg.sender, commitmentId, address(cdToken_), amount_);
        return commitmentId;
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the commitment ID is valid
    ///             - Checks that the amount is not greater than the commitment
    ///             - Reduces the commitment amount
    ///             - Transfers the quantity of CD tokens to the caller
    ///             - Emits the Uncommitted event
    ///
    ///             The function will revert if:
    ///             - The commitment ID is invalid
    ///             - The amount is greater than the committed amount
    function uncommit(
        uint16 commitmentId_,
        uint256 amount_
    ) external onlyValidCommitmentId(msg.sender, commitmentId_) {
        // Get the commitment
        UserCommitment storage commitment = _userCommitments[msg.sender][commitmentId_];

        // Check that the amount is not greater than the commitment
        if (amount_ > commitment.amount)
            revert CDRedemptionVault_InvalidAmount(msg.sender, commitmentId_, amount_);

        // Update the commitment
        commitment.amount -= amount_;

        // Transfer the quantity of CD tokens to the caller
        ERC20(address(commitment.cdToken)).safeTransfer(msg.sender, amount_);

        // Emit the uncommitted event
        emit Uncommitted(msg.sender, commitmentId_, address(commitment.cdToken), amount_);
    }

    /// @inheritdoc IConvertibleDepositRedemptionVault
    /// @dev        This function performs the following:
    ///             - Checks that the commitment ID is valid
    ///             - Checks that the commitment is redeemable
    ///             - Updates the commitment
    ///             - Redeems the CD tokens for the underlying asset
    ///             - Transfers the underlying asset to the caller
    ///             - Emits the Redeemed event
    ///
    ///             The function will revert if:
    ///             - The commitment ID is invalid
    ///             - The commitment is not yet redeemable
    function redeem(
        uint16 commitmentId_
    ) external onlyValidCommitmentId(msg.sender, commitmentId_) {
        // Get the commitment
        UserCommitment storage commitment = _userCommitments[msg.sender][commitmentId_];

        // Check that the commitment is redeemable
        if (block.timestamp < commitment.redeemableAt)
            revert CDRedemptionVault_TooEarly(msg.sender, commitmentId_);

        // Update the commitment
        uint256 commitmentAmount = commitment.amount;
        commitment.amount = 0;

        // Redeem the CD tokens for the underlying asset
        // This also burns the CD tokens
        ERC20(address(commitment.cdToken)).safeApprove(address(_CDEPO), commitmentAmount);
        _CDEPO.redeemFor(commitment.cdToken, msg.sender, commitmentAmount);

        // Transfer the underlying asset to the caller
        ERC20(address(commitment.cdToken.asset())).safeTransfer(msg.sender, commitmentAmount);

        // Emit the redeemed event
        emit Redeemed(msg.sender, commitmentId_, address(commitment.cdToken), commitmentAmount);
    }
}
