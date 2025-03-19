// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

/// @title  IConvertibleDepositFacility
/// @notice Interface for a contract that can perform functions related to convertible deposit tokens
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
    event RedeemedDeposit(
        address indexed depositToken,
        address indexed user,
        uint256 redeemedAmount
    );
    event ReclaimedDeposit(
        address indexed depositToken,
        address indexed user,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    // ========== ERRORS ========== //

    error CDF_InvalidArgs(string reason_);

    error CDF_NotOwner(uint256 positionId_);

    error CDF_PositionExpired(uint256 positionId_);

    error CDF_PositionNotExpired(uint256 positionId_);

    error CDF_InvalidAmount(uint256 positionId_, uint256 amount_);

    error CDF_InvalidToken(uint256 positionId_, address token_);

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @notice Mints a new convertible deposit position
    ///
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the deposit token is supported
    ///         - Validating that the caller has the correct role
    ///         - Depositing the reserve token into the CDEPO module and minting the convertible deposit token
    ///         - Creating a new term record in the CTERM module
    ///         - Pre-emptively increasing the OHM mint approval
    ///         - Emitting an event
    ///
    /// @param  cdToken_            The address of the CD token
    /// @param  account_            The address to create the position for
    /// @param  amount_             The amount of reserve token to deposit
    /// @param  conversionPrice_    The amount of convertible deposit tokens per OHM token
    /// @param  conversionExpiry_   The timestamp when the position can no longer be converted
    /// @param  redemptionExpiry_   The timestamp when the position can no longer be redeemed
    /// @param  wrap_               Whether the position should be wrapped
    /// @return termId              The ID of the new term
    function mint(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        uint48 redemptionExpiry_,
        bool wrap_
    ) external returns (uint256 termId);

    /// @notice Converts convertible deposit tokens to OHM before conversion expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is a CD token
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has not passed
    ///         - Burning the convertible deposit tokens
    ///         - Minting OHM to `account_`
    ///         - Transferring the sReserve token to the treasury
    ///         - Emitting an event
    ///
    /// @param  positionIds_        An array of position ids that will be converted
    /// @param  amounts_            An array of amounts of convertible deposit tokens to convert
    /// @return cdTokenIn           The total amount of convertible deposit tokens converted
    /// @return convertedTokenOut   The amount of OHM minted during conversion
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 cdTokenIn, uint256 convertedTokenOut);

    /// @notice Preview the amount of convertible deposit tokens and OHM that would be converted
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is CDEPO
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has not passed
    ///         - Returning the total amount of convertible deposit tokens and OHM that would be converted
    ///
    /// @param  account_            The address to preview the conversion for
    /// @param  positionIds_        An array of position ids that will be converted
    /// @param  amounts_            An array of amounts of convertible deposit tokens to convert
    /// @return cdTokenIn           The total amount of convertible deposit tokens converted
    /// @return convertedTokenOut   The amount of OHM minted during conversion
    /// @return cdTokenSpender      The address that will spend the convertible deposit tokens. The caller must have approved this address to spend the total amount of CD tokens.
    function previewConvert(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view returns (uint256 cdTokenIn, uint256 convertedTokenOut, address cdTokenSpender);

    /// @notice Redeems convertible deposit tokens after conversion expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is CDEPO
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has passed
    ///         - Validating that the redemption expiry for all of the positions has not passed
    ///         - Burning the convertible deposit tokens
    ///         - Transferring the reserve token to `account_`
    ///         - Emitting an event
    ///
    /// @param  positionIds_    An array of position ids that will be redeemed
    /// @param  amounts_        An array of amounts of convertible deposit tokens to redeem
    /// @return redeemed        The amount of reserve token returned to the caller
    function redeem(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 redeemed);

    /// @notice Preview the amount of reserve token that would be redeemed after expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is CDEPO
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has passed
    ///         - Validating that the redemption expiry for all of the positions has not passed
    ///         - Returning the total amount of reserve token that would be redeemed
    ///
    /// @param  account_        The address to preview the redeem for
    /// @param  positionIds_    An array of position ids that will be redeemed
    /// @param  amounts_        An array of amounts of convertible deposit tokens to redeem
    /// @return redeemed        The amount of reserve token returned to the caller
    /// @return cdTokenSpender  The address that will spend the convertible deposit tokens. The caller must have approved this address to spend the total amount of CD tokens.
    function previewRedeem(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view returns (uint256 redeemed, address cdTokenSpender);

    /// @notice Reclaims convertible deposit tokens, after applying a discount
    ///         Convertible deposit tokens can be reclaimed at any time.
    ///         The caller is not required to have a position in the facility.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Burning the convertible deposit tokens
    ///         - Transferring the reserve token to `account_`
    ///         - Emitting an event
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  amount_         The amount of convertible deposit tokens to reclaim
    /// @return reclaimed       The amount of reserve token returned to the caller
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 reclaimed);

    /// @notice Preview the amount of reserve token that would be reclaimed
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Returning the total amount of reserve token that would be reclaimed
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  amount_         The amount of convertible deposit tokens to reclaim
    /// @return reclaimed       The amount of reserve token returned to the caller
    /// @return cdTokenSpender  The address that will spend the convertible deposit tokens. The caller must have approved this address to spend the total amount of CD tokens.
    function previewReclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view returns (uint256 reclaimed, address cdTokenSpender);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Creates a new convertible deposit token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Creating a new convertible deposit token
    ///         - Emitting an event
    ///
    /// @param  vault_          The address of the vault to use for the convertible deposit token
    /// @param  reclaimRate_    The reclaim rate to set for the convertible deposit token
    /// @return cdToken         The address of the new convertible deposit token
    function create(
        IERC4626 vault_,
        uint16 reclaimRate_
    ) external returns (IConvertibleDepositERC20 cdToken);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice The address of token accepted by the facility
    function depositToken() external view returns (address);

    /// @notice The address of the convertible deposit token that is minted by the facility
    function convertibleDepositToken() external view returns (address);

    /// @notice The address of the token that is converted to by the facility
    function convertedToken() external view returns (address);
}
