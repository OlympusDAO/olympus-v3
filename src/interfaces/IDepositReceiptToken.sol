// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IDepositReceiptToken
/// @notice Interface for a deposit receipt token
/// @dev    Receipt-specific metadata; ERC20 functionality is exposed separately through IERC20.
interface IDepositReceiptToken {
    // ========== ERRORS ========== //

    error OnlyOwner();

    // ========== VIEW FUNCTIONS ========== //

    function owner() external view returns (address _owner);

    function asset() external view returns (IERC20 _asset);

    function depositPeriod() external view returns (uint8 _depositPeriod);

    function operator() external view returns (address _operator);
}
