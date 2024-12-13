// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Kernel, Module} from "src/Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

/// @title Convertible Deposit Token
abstract contract CDEPOv1 is Module, ERC20 {
    // ========== CONSTANTS ========== //

    /// @notice Equivalent to 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // // ========== CONSTRUCTOR ========== //

    // constructor(address kernel_, address erc4626Vault_) Module(Kernel(kernel_)) {
    //     // Store the vault and asset
    //     vault = ERC4626(erc4626Vault_);
    //     asset = ERC20(vault.asset());

    //     // Set the name and symbol
    //     name = string.concat("cd", asset.symbol());
    //     symbol = string.concat("cd", asset.symbol());
    //     decimals = asset.decimals();

    //     // Set the initial chain id and domain separator (see solmate/tokens/ERC20.sol)
    //     INITIAL_CHAIN_ID = block.chainid;
    //     INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    // }

    // ========== ERC20 OVERRIDES ========== //

    /// @notice Mint tokens to the caller in exchange for the underlying asset
    /// @dev    The implementing function should perform the following:
    ///         - Transfers the underlying asset from the caller to the contract
    ///         - Mints the corresponding amount of convertible deposit tokens to the caller
    ///         - Deposits the underlying asset into the ERC4626 vault
    ///         - Emits a `Transfer` event
    ///
    /// @param  amount_   The amount of underlying asset to transfer
    function mint(uint256 amount_) external virtual;

    /// @notice Mint tokens to `to_` in exchange for the underlying asset
    /// @dev    This function behaves the same as `mint`, but allows the caller to
    ///         specify the address to mint the tokens to and pull the underlying
    ///         asset from.
    ///
    /// @param  to_       The address to mint the tokens to
    /// @param  amount_   The amount of underlying asset to transfer
    function mintTo(address to_, uint256 amount_) external virtual;

    /// @notice Preview the amount of convertible deposit tokens that would be minted for a given amount of underlying asset
    /// @dev    The implementing function should perform the following:
    ///         - Computes the amount of convertible deposit tokens that would be minted for the given amount of underlying asset
    ///         - Returns the computed amount
    ///
    /// @param  amount_   The amount of underlying asset to transfer
    /// @return tokensOut The amount of convertible deposit tokens that would be minted
    function previewMint(uint256 amount_) external view virtual returns (uint256 tokensOut);

    /// @notice Burn tokens from the caller and return the underlying asset
    ///         The amount of underlying asset may not be 1:1 with the amount of
    ///         convertible deposit tokens, depending on the value of `burnRate`
    /// @dev    The implementing function should perform the following:
    ///         - Withdraws the underlying asset from the ERC4626 vault
    ///         - Transfers the underlying asset to the caller
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///         - Marks the forfeited amount of the underlying asset as yield
    ///         - Emits a `Transfer` event
    ///
    /// @param  amount_   The amount of convertible deposit tokens to burn
    function burn(uint256 amount_) external virtual;

    /// @notice Burn tokens from `from_` and return the underlying asset
    /// @dev    This function behaves the same as `burn`, but allows the caller to
    ///         specify the address to burn the tokens from and transfer the underlying
    ///         asset to.
    ///
    /// @param  from_     The address to burn the tokens from
    /// @param  amount_   The amount of convertible deposit tokens to burn
    function burnFrom(address from_, uint256 amount_) external virtual;

    /// @notice Preview the amount of underlying asset that would be returned for a given amount of convertible deposit tokens
    /// @dev    The implementing function should perform the following:
    ///         - Computes the amount of underlying asset that would be returned for the given amount of convertible deposit tokens
    ///         - Returns the computed amount
    ///
    /// @param  amount_   The amount of convertible deposit tokens to burn
    /// @return assetsOut The amount of underlying asset that would be returned
    function previewBurn(uint256 amount_) external view virtual returns (uint256 assetsOut);

    // ========== YIELD MANAGER ========== //

    /// @notice Claim the yield accrued on the reserve token
    /// @dev    The implementing function should perform the following:
    ///         - Validating that the caller has the correct role
    ///         - Withdrawing the yield from the sReserve token
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @return yieldReserve  The amount of reserve token that was swept
    /// @return yieldSReserve The amount of sReserve token that was swept
    function sweepYield() external virtual returns (uint256 yieldReserve, uint256 yieldSReserve);

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

    /// @notice Set the burn rate of the convertible deposit token
    /// @dev    The implementing function should perform the following:
    ///         - Validating that the caller has the correct role
    ///         - Validating that the new rate is within bounds
    ///         - Setting the new burn rate
    ///         - Emitting an event
    ///
    /// @param  newBurnRate_    The new burn rate
    function setBurnRate(uint256 newBurnRate_) external virtual;

    // ========== STATE VARIABLES ========== //

    /// @notice The ERC4626 vault that holds the underlying asset
    function getVault() external view virtual returns (address);

    /// @notice The underlying asset
    function getAsset() external view virtual returns (address);

    /// @notice The burn rate of the convertible deposit token
    /// @dev    A burn rate of 99e2 (99%) means that for every 100 convertible deposit tokens burned, 99 underlying asset tokens are returned
    function burnRate() external view virtual returns (uint16);
}
