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

/// @notice TBL
error TBL_LockExtensionPeriodIs0();
error TBL_NotEnoughTokensUnlocked(uint256 unlocked_);
error TBL_CouldNotExtendLockForAmount(uint256 amount_, uint256 surplus_);
error TBL_NotEnoughTokensUnlockedForSlashing(uint256 unlocked_);
error TBL_NotEnoughLockedForSlashing(uint256 amount_, uint256 surplus_);
