// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 * @title Cooler Treasury Borrower
 * @notice Policy which can borrow from Treasury on behalf of Cooler
 *  - Cooler will always represent the debt amount in 18 decimal places.
 *  - If the actual debt token is changed (with a new deployment of this contract) to a non 18dp asset
 *    eg USDC, then borrow() and repay() will need to do the conversion.
 */
interface ICoolerTreasuryBorrower {
    error OnlyCooler();
    error InvalidParam();
    error InvalidAddress();
    error ExpectedNonZero();

    /// @notice The token (USD based stablecoin) which Cooler users borrow and repay
    function debtToken() external view returns (ERC20);

    /// @notice The cooler contract
    function cooler() external view returns (address);

    /// @notice Cooler borrows `amount` of `debtToken` from treasury, sent to `recipient`
    /// @param amount The amount to borrow. Always 18 decimal places
    ///               regardless of the `debtToken.decimals()`
    /// @dev If the debtToken is 6dp (eg USDC) then this contract needs to handle the conversion internally
    function borrow(uint256 amount, address recipient) external;

    /// @notice Repay any `debtToken` in this contract back to treasury.
    /// @dev Cooler is expected to transfer the amount to this contract prior to calling
    function repay() external;

    /// @notice The decimal precision of the `amount` used in borrow and repay functions
    function DECIMALS() external view returns (uint8);
}
