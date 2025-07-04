// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

/// @title  IConvertibleDepository
/// @notice Interface for the Olympus Convertible Depository module
interface IConvertibleDepository {
    // ========== DATA STRUCTURES ========== //

    /// @notice A struct representing a deposit token and its supported periods
    ///
    /// @param token    Deposit token
    /// @param periods  Supported periods
    struct DepositToken {
        IERC20 token;
        uint8[] periods;
    }

    // ========== ERRORS ========== //

    /// @notice Thrown when the caller provides invalid arguments
    error CDEPO_InvalidArgs(string reason);

    /// @notice Thrown when the depository has insufficient balance
    error CDEPO_InsufficientBalance();

    /// @notice Thrown when trying to interact with an unsupported token
    error CDEPO_UnsupportedToken();

    // ========== MINT/BURN ========== //

    /// @notice Mint convertible deposit tokens to the caller in exchange for the deposit token
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the CD token is supported
    ///         - Transfer the deposit token from the caller to the contract
    ///         - Mint the corresponding amount of convertible deposit tokens to the caller
    ///         - Deposit the deposit token into the ERC4626 vault
    ///
    /// @param  cdToken_    The CD token to mint
    /// @param  amount_     The amount of deposit token to transfer
    function mint(IConvertibleDepositERC20 cdToken_, uint256 amount_) external;

    /// @notice Mint convertible deposit tokens to `account_` in exchange for the deposit token
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the CD token is supported
    ///         - Transfer the deposit token from the caller to the contract
    ///         - Mint the corresponding amount of convertible deposit tokens to `account_`
    ///         - Deposit the deposit token into the ERC4626 vault
    ///
    /// @param  cdToken_    The CD token to mint
    /// @param  account_    The address to mint the tokens to and pull the deposit token from
    /// @param  amount_     The amount of deposit token to transfer
    function mintFor(IConvertibleDepositERC20 cdToken_, address account_, uint256 amount_) external;

    /// @notice Preview the amount of convertible deposit tokens that would be minted for a given amount of deposit token
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the CD token is supported
    ///         - Computes the amount of convertible deposit tokens that would be minted for the given amount of deposit token
    ///         - Returns the computed amount
    ///
    /// @param  cdToken_    The CD token to mint
    /// @param  amount_     The amount of deposit token to transfer
    /// @return tokensOut   The amount of convertible deposit tokens that would be minted
    function previewMint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view returns (uint256 tokensOut);

    /// @notice Burn convertible deposit tokens from the caller
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the convertible deposit token is supported
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///
    /// @param  cdToken_ The convertible deposit token to burn
    /// @param  amount_  The amount of convertible deposit tokens to burn
    function burn(IConvertibleDepositERC20 cdToken_, uint256 amount_) external;

    // ========== RECLAIM/REDEEM ========== //

    /// @notice Burn convertible deposit tokens from the caller and reclaim the deposit token
    ///         The amount of deposit token returned may not be 1:1 with the amount of
    ///         convertible deposit tokens, depending on the value of `reclaimRate`
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the convertible deposit token is supported
    ///         - Withdraws the deposit token from the ERC4626 vault
    ///         - Transfers the deposit token to the caller
    ///         - Burns the corresponding amount of convertible deposit tokens from the caller
    ///         - Marks the forfeited amount of the deposit token as yield
    ///
    /// @param  cdToken_    The convertible deposit token to reclaim
    /// @param  amount_     The amount of convertible deposit tokens to reclaim
    /// @return tokensOut   The amount of deposit token that was reclaimed
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 tokensOut);

    /// @notice Burn convertible deposit tokens from `account_` and reclaim the deposit token
    ///         This function behaves the same as `reclaim`, but allows the caller to
    ///         specify the address to reclaim the convertible deposit tokens from and transfer the deposit token to.
    ///         The `account_` address must have approved the contract to spend the convertible deposit tokens.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the convertible deposit token is supported
    ///         - Validates that the `account_` address has approved the contract to spend the convertible deposit tokens
    ///         - Withdraws the deposit token from the ERC4626 vault
    ///         - Transfers the deposit token to the `account_` address
    ///         - Burns the corresponding amount of convertible deposit tokens from the `account_` address
    ///         - Marks the forfeited amount of the deposit token as yield
    ///
    /// @param  cdToken_    The convertible deposit token to reclaim
    /// @param  account_    The address to burn the convertible deposit tokens from and transfer the deposit token to
    /// @param  amount_     The amount of convertible deposit tokens to reclaim
    /// @return tokensOut   The amount of deposit token that was reclaimed
    function reclaimFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external returns (uint256 tokensOut);

    /// @notice Preview the amount of deposit token that would be reclaimed for a given amount of convertible deposit tokens
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the convertible deposit token is supported
    ///         - Computes the amount of deposit token that would be returned for the given amount of convertible deposit tokens
    ///         - Returns the computed amount
    ///
    /// @param  cdToken_  The convertible deposit token to reclaim
    /// @param  amount_   The amount of convertible deposit tokens to reclaim
    /// @return assetsOut The amount of deposit token that would be reclaimed
    function previewReclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view returns (uint256 assetsOut);

    /// @notice Redeem convertible deposit tokens for the deposit token
    ///         The `account_` address must have approved the contract to spend the convertible deposit tokens.
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the convertible deposit token is supported
    ///         - Validates that the caller is permissioned
    ///         - Validates that the `account_` address has approved the contract to spend the convertible deposit tokens
    ///         - Burns the corresponding amount of convertible deposit tokens from the `account_` address
    ///         - Transfers the corresponding deposit token to the caller (not the `account_` address)
    ///
    /// @param  cdToken_    The convertible deposit token to redeem
    /// @param  account_    The address to burn the convertible deposit tokens from and transfer the deposit token to
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return tokensOut   The amount of deposit token that was redeemed
    function redeemFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external returns (uint256 tokensOut);

    /// @notice Preview the amount of deposit token that would be redeemed for a given amount of convertible deposit tokens
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the convertible deposit token is supported
    ///         - Computes the amount of deposit token that would be returned for the given amount of convertible deposit tokens
    ///         - Returns the computed amount
    ///
    /// @param  cdToken_    The convertible deposit token to redeem
    /// @param  amount_     The amount of convertible deposit tokens to redeem
    /// @return tokensOut   The amount of deposit token that would be redeemed
    function previewRedeem(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view returns (uint256 tokensOut);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get all supported deposit tokens
    ///
    /// @return tokens  Array of supported token addresses and periods
    function getDepositTokens() external view returns (DepositToken[] memory tokens);

    /// @notice Get all supported deposit periods
    ///
    /// @return periods  Array of supported period months, or an empty array if no periods are supported
    function getDepositTokenPeriods(
        address depositToken_
    ) external view returns (uint8[] memory periods);

    /// @notice Get all supported convertible deposit tokens
    ///
    /// @return tokens  Array of supported token addresses
    function getConvertibleDepositTokens()
        external
        view
        returns (IConvertibleDepositERC20[] memory tokens);

    /// @notice Get the deposit token for a cdToken
    ///
    /// @param  cdToken_        The cdToken to check
    /// @return depositToken    The deposit token address, or address(0) if not supported
    function getDepositToken(address cdToken_) external view returns (IERC20 depositToken);

    /// @notice Get the convertible deposit token for a deposit token and period
    ///
    /// @param  depositToken_   The deposit token to check
    /// @param  periodMonths_   The period (months) to check
    /// @return cdToken         The convertible deposit token address, or address(0) if not supported
    function getConvertibleDepositToken(
        address depositToken_,
        uint8 periodMonths_
    ) external view returns (IConvertibleDepositERC20 cdToken);

    /// @notice Check if `depositToken_` is a supported deposit token for a given period
    ///
    /// @param  depositToken_  The deposit token to check
    /// @param  periodMonths_  The period (months) to check
    /// @return result         True if the token is a supported deposit token for the given period
    function isDepositToken(
        address depositToken_,
        uint8 periodMonths_
    ) external view returns (bool result);

    /// @notice Check if `cdToken_` is a supported convertible deposit token
    ///
    /// @param  cdToken_  The convertible deposit token to check
    /// @return result    True if the token is a supported convertible deposit token
    function isConvertibleDepositToken(address cdToken_) external view returns (bool result);

    /// @notice Get the reclaim rate for a convertible deposit token
    ///
    /// @param  cdToken_            The convertible deposit token to check
    /// @return tokenReclaimRate    The reclaim rate for the convertible deposit token
    function reclaimRate(address cdToken_) external view returns (uint16 tokenReclaimRate);
}
