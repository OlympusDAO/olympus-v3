// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @dev Shared unordered grant-action bits used by public actions, Core and Auth.
uint8 constant BL_ACTION_DEPOSIT = 1;
uint8 constant BL_ACTION_BORROW = 2;
uint8 constant BL_ACTION_WITHDRAW = 4;
uint8 constant BL_ACTION_EXTEND = 8;
