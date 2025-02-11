// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";

/**
 * @title Cooler Treasury Borrower
 * @notice Policy which can borrow from Treasury on behalf of Cooler
 *  - Cooler will always represent the debt amount in 18 decimal places.
 *  - This logic is split out into a separate policy (rather than using `TreasuryCustodian`):
 *      1/ So the Cooler debt token can be updated if required in future to another stablecoin without a redeploy of Cooler.
 *      2/ In this case, debt is denominated in USDS but stored 'at rest' in Treasury into sUSDS for extra yield.
 *  - Upon an upgreade, if the actual debt token is changed (with a new deployment of this contract) to a non 18dp asset
 *    eg USDC, then borrow() and repay() will need to do the conversion.
 */
interface ICoolerTreasuryBorrower {
    error OnlyCooler();
    error InvalidParam();
    error InvalidAddress();
    error ExpectedNonZero();

    /// @notice Cooler borrows `amount` of `debtToken` from treasury, sent to `recipient`
    /// @param amountInWad The amount to borrow. Always 18 decimal places
    ///               regardless of the `debtToken.decimals()`
    /// @dev If the debtToken is 6dp (eg USDC) then this contract needs to handle the conversion internally
    function borrow(uint256 amountInWad, address recipient) external;

    /// @notice Repay any `debtToken` in this contract back to treasury.
    /// @dev Cooler is expected to transfer the amount to this contract prior to calling
    function repay() external;

    /// @notice In the case of a Cooler debt token change (eg USDS => USDC), the
    /// debt may be manually net settled from the old debt token (in the old cooler treasury borrower)
    /// to the new debt token (in the new cooler treasury borrower)
    /// @param debtTokenAmount The amount of debt to set in Treasury, in the debtToken.decimals() precision
    function setDebt(uint256 debtTokenAmount) external;

    /// @notice The token (USD based stablecoin) which Cooler users borrow and repay
    function debtToken() external view returns (IERC20);

    /// @notice Convert a debt amount in wad (18dp) into the decimals of the `debtToken`
    function convertToDebtTokenAmount(
        uint256 amountInWad
    ) external view returns (IERC20 dToken, uint256 dTokenAmount);

    /// @notice The decimal precision of the `amountInWad` used in borrow and repay functions.
    /// @dev A constant of 18
    function DECIMALS() external view returns (uint8);
}
