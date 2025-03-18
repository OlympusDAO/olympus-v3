// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {IConvertibleDepository} from "./IConvertibleDepository.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "./IConvertibleDepositERC20.sol";

/// @title  CDEPOv1
/// @notice This is a base contract for a custodial convertible deposit token. It is designed to be used in conjunction with an ERC4626 vault.
abstract contract CDEPOv1 is Module, IConvertibleDepository {
    // ========== EVENTS ========== //

    /// @notice Emitted when the reclaim rate is updated
    event ReclaimRateUpdated(address indexed inputToken, uint16 newReclaimRate);

    /// @notice Emitted when the yield is swept
    event YieldSwept(
        address indexed inputToken,
        address indexed receiver,
        uint256 reserveAmount,
        uint256 sReserveAmount
    );

    /// @notice Emitted when the caller borrows the underlying asset
    event DebtIncurred(address indexed inputToken, address indexed borrower, uint256 amount);

    /// @notice Emitted when the caller repays a borrowed amount of the underlying asset
    event DebtRepaid(address indexed inputToken, address indexed borrower, uint256 amount);

    /// @notice Emitted when the debt is reduced for a borrower
    event DebtReduced(address indexed inputToken, address indexed borrower, uint256 amount);

    /// @notice Emitted when a new token is supported
    event TokenAdded(address indexed inputToken, address indexed cdToken);

    // ========== CONSTANTS ========== //

    /// @notice Equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== LENDING FUNCTIONS ========== //

    /// @notice Allows the permissioned caller to borrow the vault asset
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Validates that the caller is permissioned
    ///         - Transfers the vault asset from the contract to the caller
    ///         - Emits a `DebtIncurred` event
    ///
    /// @param  inputToken_  The input token to borrow
    /// @param  amount_     The amount of vault asset to borrow
    function incurDebt(IERC20 inputToken_, uint256 amount_) external virtual;

    /// @notice Allows the permissioned caller to repay an amount of the vault asset
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Validates that the caller is permissioned
    ///         - Transfers the vault asset from the caller to the contract
    ///         - Emits a `DebtRepaid` event
    ///
    /// @param  inputToken_  The input token to repay
    /// @param  amount_     The amount of vault asset to repay
    /// @return repaidAmount The amount of vault asset that was repaid
    function repayDebt(IERC20 inputToken_, uint256 amount_) external virtual returns (uint256);

    /// @notice Allows the permissioned caller to reduce the debt of a borrower
    ///         This can be used to forgive debt, e.g. in the case of a liquidation.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Validates that the caller is permissioned
    ///         - Updates the debt of the borrower
    ///         - Emits a `DebtReduced` event
    ///
    /// @param  inputToken_  The input token to reduce debt for
    /// @param  amount_     The amount to reduce the debt by
    /// @return debtAmount  The remaining debt amount
    function reduceDebt(IERC20 inputToken_, uint256 amount_) external virtual returns (uint256);

    // ========== YIELD MANAGEMENT ========== //

    /// @notice Claim the yield accrued on all supported tokens
    function sweepAllYield(address to_) external virtual;

    /// @notice Claim the yield accrued on the input token
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Validates that the caller is permissioned
    ///         - Withdrawing the yield from the sReserve token
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @param  inputToken_     The input token to sweep yield for
    /// @param  to_             The address to sweep the yield to
    /// @return yieldReserve    The amount of reserve token swept
    /// @return yieldSReserve   The amount of sReserve token swept
    function sweepYield(
        IERC20 inputToken_,
        address to_
    ) external virtual returns (uint256, uint256);

    /// @notice Preview the amount of yield that would be swept
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Computes the amount of yield that would be swept
    ///         - Returns the computed amount
    ///
    /// @param  inputToken_  The input token to check
    /// @return yieldReserve  The amount of reserve token that would be swept
    /// @return yieldSReserve The amount of sReserve token that would be swept
    function previewSweepYield(
        IERC20 inputToken_
    ) external view virtual returns (uint256 yieldReserve, uint256 yieldSReserve);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get the debt amount for a token and borrower
    function debt(IERC20 inputToken_, address borrower_) external view virtual returns (uint256);

    /// @notice Get the amount of vault shares managed by the contract
    ///
    /// @param  inputToken_  The input token to get vault shares for
    /// @return shares       The amount of vault shares managed by the contract
    function getVaultShares(IERC20 inputToken_) external view virtual returns (uint256 shares);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Set the reclaim rate for a token
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the input token is supported
    ///         - Validating that the caller has the correct role
    ///         - Validating that the new rate is within bounds
    ///         - Setting the new reclaim rate
    ///         - Emitting an event
    ///
    /// @param  inputToken_      The input token to set rate for
    /// @param  newReclaimRate_  The new reclaim rate
    function setReclaimRate(IERC20 inputToken_, uint16 newReclaimRate_) external virtual;

    /// @notice Create support for a new input token based on its vault
    /// @param  vault_          The ERC4626 vault for the input token
    /// @param  reclaimRate_    The initial reclaim rate
    /// @return cdToken         The address of the deployed cdToken
    function create(
        IERC4626 vault_,
        uint16 reclaimRate_
    ) external virtual returns (IConvertibleDepositERC20 cdToken);
}
