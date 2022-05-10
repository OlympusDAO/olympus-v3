// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// @notice General errors
error InvalidArgument();
error AddressIsZero();
error AmountMustBeNonzero(uint256 amount_);
error NotAuthorized();
error InsufficientBalance(uint256 requested_, uint256 balance_);
error AlreadyInitialized();

/// @notice Message bus errors
error CallerMustBeLZEndpoint();

/// @notice Debt facility errors
error DebtExceedsAllowance(uint256 exceededBy_);
error DebtExceedsBalance();
error CannotTransferDueToDebt();

/// @notice Treasury errors
error NoAssignedAllocator(address token_);
error NoAssignedAppraiser(address token_);

/// @notice TXBLK
error TXBLK_LockExtensionPeriodIs0();
error TXBLK_NotEnoughTokensUnlocked(uint256 unlocked_);
error TXBLK_CouldNotExtendLockForAmount(uint256 amount_);
error TXBLK_NotEnoughUnlockedForSlashing(uint256 unlocked_);
error TXBLK_NotEnoughLockedForSlashing(uint256 locked_);
