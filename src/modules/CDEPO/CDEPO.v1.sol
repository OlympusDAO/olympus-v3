// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {IConvertibleDepository} from "./IConvertibleDepository.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "./IConvertibleDepositERC20.sol";

/// @title  CDEPOv1
/// @notice This is a base contract for a custodial convertible deposit token. It is designed to be used in conjunction with an ERC4626 vault.
/// @dev    This abstract contract contains admin- and protocol-related functions. For user-facing functions, see {IConvertibleDepository}.
abstract contract CDEPOv1 is Module, IConvertibleDepository {
    // ========== EVENTS ========== //

    /// @notice Emitted when the reclaim rate is updated
    event ReclaimRateUpdated(address indexed cdToken, uint16 newReclaimRate);

    /// @notice Emitted when the caller borrows the underlying asset
    event DebtIncurred(address indexed vaultToken, address indexed borrower, uint256 amount);

    /// @notice Emitted when the caller repays a borrowed amount of the underlying asset
    event DebtRepaid(address indexed vaultToken, address indexed borrower, uint256 amount);

    /// @notice Emitted when the debt is reduced for a borrower
    event DebtReduced(address indexed vaultToken, address indexed borrower, uint256 amount);

    /// @notice Emitted when a new token is supported
    event TokenCreated(address indexed depositToken, uint8 periodMonths, address indexed cdToken);

    /// @notice Emitted when the underlying asset is withdrawn
    event TokenWithdrawn(address indexed token, address indexed recipient, uint256 amount);

    // ========== CONSTANTS ========== //

    /// @notice Equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== LENDING FUNCTIONS ========== //

    /// @notice Allows the permissioned caller to borrow the vault asset
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the vault token's underlying asset is supported
    ///         - Validates that the caller is permissioned
    ///         - Transfers the vault asset from the contract to the caller
    ///         - Emits a `DebtIncurred` event
    ///
    /// @param  vaultToken_ The vault token to borrow
    /// @param  amount_     The amount of vault asset to borrow
    function incurDebt(IERC4626 vaultToken_, uint256 amount_) external virtual;

    /// @notice Allows the permissioned caller to repay an amount of the vault asset
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the vault token's underlying asset is supported
    ///         - Validates that the caller is permissioned
    ///         - Transfers the vault asset from the caller to the contract
    ///         - Emits a `DebtRepaid` event
    ///
    /// @param  vaultToken_     The vault token to repay
    /// @param  amount_         The amount of vault asset to repay
    /// @return repaidAmount    The amount of vault asset that was repaid
    function repayDebt(IERC4626 vaultToken_, uint256 amount_) external virtual returns (uint256);

    /// @notice Allows the permissioned caller to reduce the debt of a borrower
    ///         This can be used to forgive debt, e.g. in the case of a liquidation.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the vault token's underlying asset is supported
    ///         - Validates that the caller is permissioned
    ///         - Updates the debt of the borrower
    ///         - Emits a `DebtReduced` event
    ///
    /// @param  vaultToken_ The vault token to reduce debt for
    /// @param  amount_     The amount to reduce the debt by
    /// @return debtAmount  The remaining debt amount
    function reduceDebt(IERC4626 vaultToken_, uint256 amount_) external virtual returns (uint256);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get the debt amount for a vault token and borrower
    ///
    /// @param  vaultToken_ The vault token to get debt for
    /// @param  borrower_   The borrower to get debt for
    /// @return debt        The amount of debt owed
    function getDebt(
        IERC4626 vaultToken_,
        address borrower_
    ) external view virtual returns (uint256);

    /// @notice Get the list of supported vault tokens
    ///
    /// @return vaultTokens The list of supported vault tokens
    function getVaultTokens() external view virtual returns (IERC4626[] memory vaultTokens);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Set the reclaim rate for a convertible deposit token
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the convertible deposit token is supported
    ///         - Validating that the caller has the correct role
    ///         - Validating that the new rate is within bounds
    ///         - Setting the new reclaim rate
    ///         - Emitting an event
    ///
    /// @param  cdToken_        The convertible deposit token to set rate for
    /// @param  newReclaimRate_ The new reclaim rate
    function setReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 newReclaimRate_
    ) external virtual;

    /// @notice Create support for a new deposit token based on its vault
    ///
    /// @param  vault_          The ERC4626 vault for the deposit token
    /// @param  periodMonths_   The period of the deposit token (months)
    /// @param  reclaimRate_    The initial reclaim rate
    /// @return cdToken         The address of the deployed cdToken
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external virtual returns (IConvertibleDepositERC20 cdToken);

    /// @notice Withdraws the underlying asset for the given CD token
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the CD token is supported
    ///         - Validates that the caller is permissioned
    ///         - Transfers the token from the contract to the caller
    ///         - Emits a `TokenWithdrawn` event
    ///
    /// @param  cdToken_      The CD token to withdraw the underlying asset for
    /// @param  amount_       The amount of underlying asset to withdraw
    function withdraw(IConvertibleDepositERC20 cdToken_, uint256 amount_) external virtual;
}
