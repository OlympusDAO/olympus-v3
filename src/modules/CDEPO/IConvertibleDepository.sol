// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

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

    /// @notice Mint convertible deposit tokens to `account_` in exchange for the deposit token
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the caller is permissioned
    ///         - Validate that the CD token is supported
    ///         - Mint the corresponding amount of convertible deposit tokens to `account_`
    ///
    /// @param  cdToken_    The CD token to mint
    /// @param  account_    The address to mint the tokens to and pull the deposit token from
    /// @param  amount_     The amount of deposit token to transfer
    function mintFor(IConvertibleDepositERC20 cdToken_, address account_, uint256 amount_) external;

    /// @notice Burn convertible deposit tokens from `account_`
    /// @dev    The implementing function should perform the following:
    ///         - Validate that the caller is permissioned
    ///         - Validate that the convertible deposit token is supported
    ///         - Burns the corresponding amount of convertible deposit tokens from `account_`
    ///
    /// @param  cdToken_ The convertible deposit token to burn
    /// @param  account_ The address to burn the convertible deposit tokens from
    /// @param  amount_  The amount of convertible deposit tokens to burn
    function burnFrom(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external;

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
