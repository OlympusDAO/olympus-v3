// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IDepositReceiptToken
/// @notice Interface for a deposit receipt token
/// @dev    This interface adds additional metadata to the IERC20 interface that is necessary for deposit receipt tokens.
interface IDepositReceiptToken is IERC20 {
    // ========== ERRORS ========== //

    error OnlyOwner();

    // ========== VIEW FUNCTIONS ========== //

    function owner() external view returns (address _owner);

    function asset() external view returns (IERC20 _asset);

    function depositPeriod() external view returns (uint8 _depositPeriod);

    function operator() external view returns (address _operator);
}
