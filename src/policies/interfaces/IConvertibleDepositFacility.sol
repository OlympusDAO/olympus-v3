// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

/// @title  IConvertibleDepositFacility
/// @notice Interface for a contract that can perform functions related to convertible deposit (CD) tokens
interface IConvertibleDepositFacility {
    // ========== EVENTS ========== //

    event CreatedDeposit(
        address indexed depositToken,
        address indexed user,
        uint256 indexed positionId,
        uint256 depositAmount
    );
    event ConvertedDeposit(
        address indexed depositToken,
        address indexed user,
        uint256 depositAmount,
        uint256 convertedAmount
    );

    // ========== ERRORS ========== //

    error CDF_InvalidArgs(string reason_);

    error CDF_NotOwner(uint256 positionId_);

    error CDF_PositionExpired(uint256 positionId_);

    error CDF_InvalidAmount(uint256 positionId_, uint256 amount_);

    error CDF_InvalidToken(uint256 positionId_, address token_);

    error CDF_Unsupported(uint256 positionId_);

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @notice Mints a position for a call option
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the CD token is supported
    ///         - Validating that the caller has the correct role
    ///         - Depositing the token into the CDEPO module and minting the CD token
    ///         - Creating a new position in the CDPOS module
    ///         - Emitting an event
    ///
    /// @param  cdToken_            The address of the CD token
    /// @param  account_            The address to create the position for
    /// @param  amount_             The amount of token to deposit
    /// @param  conversionPrice_    The amount of CD tokens per OHM token
    /// @param  wrap_               Whether the position should be wrapped
    /// @return positionId          The ID of the new position
    function mint(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrap_
    ) external returns (uint256 positionId);

    /// @notice Converts CD tokens to OHM before conversion expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that the token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has not passed
    ///         - Burning the CD tokens
    ///         - Minting OHM to `account_`
    ///         - Transferring the vault token to the treasury
    ///         - Emitting an event
    ///
    /// @param  positionIds_        An array of position ids that will be converted
    /// @param  amounts_            An array of amounts of CD tokens to convert
    /// @return cdTokenIn           The total amount of CD tokens converted
    /// @return convertedTokenOut   The amount of OHM minted during conversion
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 cdTokenIn, uint256 convertedTokenOut);

    /// @notice Preview the amount of CD tokens and OHM that would be converted
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has not passed
    ///         - Returning the total amount of CD tokens and OHM that would be converted
    ///
    /// @param  account_            The address to preview the conversion for
    /// @param  positionIds_        An array of position ids that will be converted
    /// @param  amounts_            An array of amounts of CD tokens to convert
    /// @return cdTokenIn           The total amount of CD tokens converted
    /// @return convertedTokenOut   The amount of OHM minted during conversion
    /// @return cdTokenSpender      The address that will spend the CD tokens. The caller must have approved this address to spend the total amount of CD tokens.
    function previewConvert(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view returns (uint256 cdTokenIn, uint256 convertedTokenOut, address cdTokenSpender);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice The addresses of deposit tokens accepted by the facility
    function getDepositTokens()
        external
        view
        returns (IConvertibleDepository.DepositToken[] memory);

    /// @notice The addresses of the CD tokens that are minted by the facility
    function getConvertibleDepositTokens()
        external
        view
        returns (IConvertibleDepositERC20[] memory);

    /// @notice The address of the token that is converted to by the facility
    function convertedToken() external view returns (address);
}
