// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

/// @title  CDEPOv1
/// @notice This is a base contract for a custodial convertible deposit token. It is designed to be used in conjunction with an ERC4626 vault.
abstract contract CDEPOv1 is Module, ERC20 {
    // ========== EVENTS ========== //

    /// @notice Emitted when the reclaim rate is updated
    event ReclaimRateUpdated(uint16 newReclaimRate);

    /// @notice Emitted when the yield is swept
    event YieldSwept(address indexed receiver, uint256 reserveAmount, uint256 sReserveAmount);

    /// @notice Emitted when the caller borrows the underlying asset
    event DebtIncurred(address indexed borrower, uint256 amount);

    /// @notice Emitted when the caller repays a borrowed amount of the underlying asset
    event DebtRepaid(address indexed borrower, uint256 amount);

    /// @notice Emitted when the debt is reduced for a borrower
    event DebtReduced(address indexed borrower, uint256 amount);

    // ========== ERRORS ========== //

    /// @notice Thrown when the caller provides invalid arguments
    error CDEPO_InvalidArgs(string reason);

    /// @notice Thrown when the depository has insufficient balance
    error CDEPO_InsufficientBalance();

    // ========== CONSTANTS ========== //

    /// @notice Equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== STATE VARIABLES ========== //

    /// @notice The reclaim rate of the convertible deposit token
    /// @dev    A reclaim rate of 99e2 (99%) means that for every 100 convertible deposit tokens burned, 99 underlying asset tokens are returned
    uint16 internal _reclaimRate;

    /// @notice The total amount of vault shares in the contract
    uint256 public totalShares;

    // ========== MINT/BURN ========== //

    /// @notice Mint tokens to the caller in exchange for the underlying asset
    /// @dev    The implementing function should perform the following:
    ///         - Transfers the underlying asset from the caller to the contract
    ///         - Mints the corresponding amount of convertible deposit tokens to the caller
    ///         - Deposits the underlying asset into the ERC4626 vault
    ///         - Emits a `Transfer` event
    ///
    /// @param  amount_   The amount of underlying asset to transfer
    function mint(uint256 amount_) external virtual;

    /// @notice Mint tokens to `account_` in exchange for the underlying asset
    ///         This function behaves the same as `mint`, but allows the caller to
    ///         specify the address to mint the tokens to and pull the asset from.
    ///         The `account_` address must have approved the contract to spend the underlying asset.
    /// @dev    The implementing function should perform the following:
    ///         - Transfers the underlying asset from the `account_` address to the contract
    ///         - Mints the corresponding amount of convertible deposit tokens to the `account_` address
    ///         - Deposits the underlying asset into the ERC4626 vault
    ///         - Emits a `Transfer` event
    ///
    /// @param  account_    The address to mint the tokens to and pull the asset from
    /// @param  amount_     The amount of asset to transfer
    function mintFor(address account_, uint256 amount_) external virtual;

    /// @notice Preview the amount of convertible deposit tokens that would be minted for a given amount of underlying asset
    /// @dev    The implementing function should perform the following:
    ///         - Computes the amount of convertible deposit tokens that would be minted for the given amount of underlying asset
    ///         - Returns the computed amount
    ///
    /// @param  amount_   The amount of underlying asset to transfer
    /// @return tokensOut The amount of convertible deposit tokens that would be minted
    function previewMint(uint256 amount_) external view virtual returns (uint256 tokensOut);

    /// @notice Burn tokens from the caller
    /// @dev    The implementing function should perform the following:
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///
    /// @param  amount_   The amount of convertible deposit tokens to burn
    function burn(uint256 amount_) external virtual;

    // ========== RECLAIM/REDEEM ========== //

    /// @notice Burn tokens from the caller and reclaim the underlying asset
    ///         The amount of underlying asset may not be 1:1 with the amount of
    ///         convertible deposit tokens, depending on the value of `burnRate`
    /// @dev    The implementing function should perform the following:
    ///         - Withdraws the underlying asset from the ERC4626 vault
    ///         - Transfers the underlying asset to the caller
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///         - Marks the forfeited amount of the underlying asset as yield
    ///
    /// @param  amount_   The amount of convertible deposit tokens to burn
    /// @return tokensOut The amount of underlying asset that was reclaimed
    function reclaim(uint256 amount_) external virtual returns (uint256 tokensOut);

    /// @notice Burn tokens from `account_` and reclaim the underlying asset
    ///         This function behaves the same as `reclaim`, but allows the caller to
    ///         specify the address to burn the tokens from and transfer the underlying
    ///         asset to.
    ///         The `account_` address must have approved the contract to spend the convertible deposit tokens.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the `account_` address has approved the contract to spend the convertible deposit tokens
    ///         - Withdraws the underlying asset from the ERC4626 vault
    ///         - Transfers the underlying asset to the `account_` address
    ///         - Burns the corresponding amount of convertible deposit tokens from the `account_` address
    ///         - Marks the forfeited amount of the underlying asset as yield
    ///
    /// @param  account_    The address to burn the convertible deposit tokens from and transfer the underlying asset to
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return tokensOut   The amount of underlying asset that was reclaimed
    function reclaimFor(
        address account_,
        uint256 amount_
    ) external virtual returns (uint256 tokensOut);

    /// @notice Preview the amount of underlying asset that would be reclaimed for a given amount of convertible deposit tokens
    /// @dev    The implementing function should perform the following:
    ///         - Computes the amount of underlying asset that would be returned for the given amount of convertible deposit tokens
    ///         - Returns the computed amount
    ///
    /// @param  amount_   The amount of convertible deposit tokens to burn
    /// @return assetsOut The amount of underlying asset that would be reclaimed
    function previewReclaim(uint256 amount_) external view virtual returns (uint256 assetsOut);

    /// @notice Redeem convertible deposit tokens for the underlying asset
    ///         This differs from the reclaim function, in that it is an admin-level and permissioned function that does not apply the burn rate.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the caller is permissioned
    ///         - Transfers the corresponding underlying assets to the caller
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///
    /// @param  amount_   The amount of convertible deposit tokens to burn
    /// @return tokensOut The amount of underlying assets that were transferred to the caller
    function redeem(uint256 amount_) external virtual returns (uint256 tokensOut);

    /// @notice Redeem convertible deposit tokens for the underlying asset
    ///         This differs from the redeem function, in that it allows the caller to specify the address to burn the convertible deposit tokens from.
    ///         The `account_` address must have approved the contract to spend the convertible deposit tokens.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the caller is permissioned
    ///         - Validates that the `account_` address has approved the contract to spend the convertible deposit tokens
    ///         - Burns the corresponding amount of convertible deposit tokens from the `account_` address
    ///         - Transfers the corresponding underlying assets to the caller (not the `account_` address)
    ///
    /// @param  account_    The address to burn the convertible deposit tokens from
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return tokensOut   The amount of underlying assets that were transferred to the caller
    function redeemFor(
        address account_,
        uint256 amount_
    ) external virtual returns (uint256 tokensOut);

    /// @notice Preview the amount of underlying asset that would be redeemed for a given amount of convertible deposit tokens
    /// @dev    The implementing function should perform the following:
    ///         - Computes the amount of underlying asset that would be returned for the given amount of convertible deposit tokens
    ///         - Returns the computed amount
    ///
    /// @param  amount_   The amount of convertible deposit tokens to burn
    /// @return tokensOut The amount of underlying asset that would be redeemed
    function previewRedeem(uint256 amount_) external view virtual returns (uint256 tokensOut);

    // ========== LENDING ========== //

    /// @notice Allows the permissioned caller to borrow the underlying asset
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the caller is permissioned
    ///         - Transfers the underlying asset from the contract to the caller
    ///         - Emits a `DebtIncurred` event
    ///
    /// @param  amount_   The amount of underlying asset to borrow
    function incurDebt(uint256 amount_) external virtual;

    /// @notice Allows the permissioned caller to repay an amount of the underlying asset
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the caller is permissioned
    ///         - Transfers the underlying asset from the caller to the contract
    ///         - Emits a `DebtRepaid` event
    ///
    /// @param  amount_         The amount of underlying asset to repay
    /// @return repaidAmount    The amount of underlying asset that was repaid
    function repayDebt(uint256 amount_) external virtual returns (uint256 repaidAmount);

    /// @notice Allows the permissioned caller to reduce the debt of a borrower
    ///         This can be used to forgive debt, e.g. in the case of a liquidation.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the caller is permissioned
    ///         - Updates the debt of the borrower
    ///         - Emits a `DebtSet` event
    ///
    /// @param  amount_         The amount of underlying asset to reduce the debt by
    /// @return borrowedAmount  The updated amount of underlying asset that has been borrowed by the given address
    function reduceDebt(uint256 amount_) external virtual returns (uint256 borrowedAmount);

    /// @notice Returns the amount of underlying asset that has been borrowed by the given address
    ///
    /// @param  borrower_       The address to check the borrowed amount for
    /// @return borrowedAmount  The amount of underlying asset that has been borrowed by the given address
    function debt(address borrower_) external view virtual returns (uint256 borrowedAmount);

    // ========== YIELD MANAGER ========== //

    /// @notice Claim the yield accrued on the reserve token
    /// @dev    The implementing function should perform the following:
    ///         - Validating that the caller has the correct role
    ///         - Withdrawing the yield from the sReserve token
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @param  to_         The address to sweep the yield to
    /// @return yieldReserve  The amount of reserve token that was swept
    /// @return yieldSReserve The amount of sReserve token that was swept
    function sweepYield(
        address to_
    ) external virtual returns (uint256 yieldReserve, uint256 yieldSReserve);

    /// @notice Preview the amount of yield that would be swept
    ///
    /// @return yieldReserve  The amount of reserve token that would be swept
    /// @return yieldSReserve The amount of sReserve token that would be swept
    function previewSweepYield()
        external
        view
        virtual
        returns (uint256 yieldReserve, uint256 yieldSReserve);

    // ========== ADMIN ========== //

    /// @notice Set the reclaim rate of the convertible deposit token
    /// @dev    The implementing function should perform the following:
    ///         - Validating that the caller has the correct role
    ///         - Validating that the new rate is within bounds
    ///         - Setting the new reclaim rate
    ///         - Emitting an event
    ///
    /// @param  newReclaimRate_    The new reclaim rate
    function setReclaimRate(uint16 newReclaimRate_) external virtual;

    // ========== STATE VARIABLES ========== //

    /// @notice The ERC4626 vault that holds the underlying asset
    function VAULT() external view virtual returns (ERC4626);

    /// @notice The underlying ERC20 asset
    function ASSET() external view virtual returns (ERC20);

    /// @notice The reclaim rate of the convertible deposit token
    /// @dev    A reclaim rate of 99e2 (99%) means that for every 100 convertible deposit tokens burned, 99 underlying asset tokens are returned
    function reclaimRate() external view virtual returns (uint16);
}
