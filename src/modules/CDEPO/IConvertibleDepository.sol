// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

/// @title  IConvertibleDepository
/// @notice Interface for the Olympus Convertible Depository module
interface IConvertibleDepository {
    // ========== ERRORS ========== //

    /// @notice Thrown when the caller provides invalid arguments
    error CDEPO_InvalidArgs(string reason);

    /// @notice Thrown when the depository has insufficient balance
    error CDEPO_InsufficientBalance();

    /// @notice Thrown when trying to interact with an unsupported token
    error CDEPO_UnsupportedToken();

    // ========== MINT/BURN ========== //

    /// @notice Mint convertible deposit tokens to the caller in exchange for the input token
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the input token is supported
    ///         - Transfer the input token from the caller to the contract
    ///         - Mint the corresponding amount of convertible deposit tokens to the caller
    ///         - Deposit the input token into the ERC4626 vault
    ///
    /// @param  inputToken_  The input token to deposit
    /// @param  amount_     The amount of input token to transfer
    function mint(IERC20 inputToken_, uint256 amount_) external;

    /// @notice Mint convertible deposit tokens to `account_` in exchange for the input token
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the input token is supported
    ///         - Transfer the input token from the caller to the contract
    ///         - Mint the corresponding amount of convertible deposit tokens to `account_`
    ///         - Deposit the input token into the ERC4626 vault
    ///
    /// @param  inputToken_ The input token to deposit
    /// @param  account_    The address to mint the tokens to and pull the input token from
    /// @param  amount_     The amount of input token to transfer
    function mintFor(IERC20 inputToken_, address account_, uint256 amount_) external;

    /// @notice Preview the amount of convertible deposit tokens that would be minted for a given amount of input token
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Computes the amount of convertible deposit tokens that would be minted for the given amount of input token
    ///         - Returns the computed amount
    ///
    /// @param  inputToken_ The input token to deposit
    /// @param  amount_     The amount of input token to transfer
    /// @return tokensOut   The amount of convertible deposit tokens that would be minted
    function previewMint(
        IERC20 inputToken_,
        uint256 amount_
    ) external view returns (uint256 tokensOut);

    /// @notice Burn convertible deposit tokens from the caller
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///
    /// @param  inputToken_ The input token to burn
    /// @param  amount_     The amount of convertible deposit tokens to burn
    function burn(IERC20 inputToken_, uint256 amount_) external;

    // ========== RECLAIM/REDEEM ========== //

    /// @notice Burn tokens from the caller and reclaim the input token
    ///         The amount of input token may not be 1:1 with the amount of
    ///         convertible deposit tokens, depending on the value of `reclaimRate`
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Withdraws the input token from the ERC4626 vault
    ///         - Transfers the input token to the caller
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///         - Marks the forfeited amount of the input token as yield
    ///
    /// @param  inputToken_ The input token to reclaim
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return tokensOut   The amount of input token that was reclaimed
    function reclaim(IERC20 inputToken_, uint256 amount_) external returns (uint256 tokensOut);

    /// @notice Burn tokens from `account_` and reclaim the input token
    ///         This function behaves the same as `reclaim`, but allows the caller to
    ///         specify the address to burn the tokens from and transfer the input token to.
    ///         The `account_` address must have approved the contract to spend the convertible deposit tokens.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Validates that the `account_` address has approved the contract to spend the convertible deposit tokens
    ///         - Withdraws the input token from the ERC4626 vault
    ///         - Transfers the input token to the `account_` address
    ///         - Burns the corresponding amount of convertible deposit tokens from the `account_` address
    ///         - Marks the forfeited amount of the input token as yield
    ///
    /// @param  inputToken_  The input token to reclaim
    /// @param  account_    The address to burn from and transfer to
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return tokensOut   The amount of input token that was reclaimed
    function reclaimFor(
        IERC20 inputToken_,
        address account_,
        uint256 amount_
    ) external returns (uint256 tokensOut);

    /// @notice Preview the amount of input token that would be reclaimed for a given amount of convertible deposit tokens
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Computes the amount of input token that would be returned for the given amount of convertible deposit tokens
    ///         - Returns the computed amount
    ///
    /// @param  inputToken_  The input token to reclaim
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return assetsOut   The amount of underlying asset that would be reclaimed
    function previewReclaim(
        IERC20 inputToken_,
        uint256 amount_
    ) external view returns (uint256 assetsOut);

    /// @notice Redeem convertible deposit tokens for the input token
    ///         The `account_` address must have approved the contract to spend the convertible deposit tokens.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Validates that the caller is permissioned
    ///         - Validates that the `account_` address has approved the contract to spend the convertible deposit tokens
    ///         - Burns the corresponding amount of convertible deposit tokens from the `account_` address
    ///         - Transfers the corresponding input token to the caller (not the `account_` address)
    ///
    /// @param  inputToken_ The input token to redeem
    /// @param  account_    The address to burn the convertible deposit tokens from
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return tokensOut   The amount of input token that was redeemed
    function redeemFor(
        IERC20 inputToken_,
        address account_,
        uint256 amount_
    ) external returns (uint256 tokensOut);

    /// @notice Preview the amount of input token that would be redeemed for a given amount of convertible deposit tokens
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the input token is supported
    ///         - Computes the amount of input token that would be returned for the given amount of convertible deposit tokens
    ///         - Returns the computed amount
    ///
    /// @param  inputToken_ The input token to redeem
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return tokensOut   The amount of input token that would be redeemed
    function previewRedeem(
        IERC20 inputToken_,
        uint256 amount_
    ) external view returns (uint256 tokensOut);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get all supported input tokens
    ///
    /// @return tokens  Array of supported token addresses
    function getTokens() external view returns (IERC20[] memory tokens);

    /// @notice Get the cdToken for an input token
    ///
    /// @param  inputToken_  The input token to check
    /// @return cdToken      The cdToken address, or address(0) if not supported
    function getConvertibleToken(
        IERC20 inputToken_
    ) external view returns (IConvertibleDepositERC20 cdToken);

    /// @notice Check if an input token is supported
    ///
    /// @param  inputToken_  The input token to check
    /// @return isSupported  True if the token is supported
    function isSupported(IERC20 inputToken_) external view returns (bool isSupported);

    /// @notice Get the reclaim rate for a token
    ///
    /// @param  inputToken_         The input token to check
    /// @return tokenReclaimRate    The reclaim rate for the token
    function reclaimRate(IERC20 inputToken_) external view returns (uint16 tokenReclaimRate);
}
