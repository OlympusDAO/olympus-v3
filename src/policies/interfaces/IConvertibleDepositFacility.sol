// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/// @title  IConvertibleDepositFacility
/// @notice Interface for a contract that can perform functions related to convertible deposit tokens
interface IConvertibleDepositFacility {
    // ========== EVENTS ========== //

    event CreatedDeposit(address indexed user, uint256 indexed termId, uint256 amount);
    event ConvertedDeposit(address indexed user, uint256 depositAmount, uint256 convertedAmount);
    event RedeemedDeposit(address indexed user, uint256 redeemedAmount);
    event ReclaimedDeposit(address indexed user, uint256 reclaimedAmount, uint256 forfeitedAmount);

    event Activated();
    event Deactivated();

    // ========== ERRORS ========== //

    error CDF_InvalidArgs(string reason_);

    error CDF_NotOwner(uint256 positionId_);

    error CDF_PositionExpired(uint256 positionId_);

    error CDF_PositionNotExpired(uint256 positionId_);

    error CDF_InvalidAmount(uint256 positionId_, uint256 amount_);

    error CDF_InvalidToken(uint256 positionId_, address token_);

    error CDF_NotActive();

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @notice Creates a new convertible deposit position
    ///
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Depositing the reserve token into the CDEPO module and minting the convertible deposit token
    ///         - Creating a new term record in the CTERM module
    ///         - Pre-emptively increasing the OHM mint approval
    ///         - Emitting an event
    ///
    /// @param  account_            The address to create the position for
    /// @param  amount_             The amount of reserve token to deposit
    /// @param  conversionPrice_    The amount of convertible deposit tokens per OHM token
    /// @param  expiry_             The timestamp when the position expires
    /// @param  wrap_               Whether the position should be wrapped
    /// @return termId              The ID of the new term
    function create(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) external returns (uint256 termId);

    /// @notice Converts convertible deposit tokens to OHM before expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is CDEPO
    ///         - Validating that all of the positions are valid
    ///         - Validating that all of the positions have not expired
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
    ///         - Validating that all of the positions have not expired
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

    /// @notice Redeems convertible deposit tokens after expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is CDEPO
    ///         - Validating that all of the positions are valid
    ///         - Validating that all of the positions have expired
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
    ///         - Validating that all of the positions have expired
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

    /// @notice Reclaims convertible deposit tokens before expiry, after applying a discount
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is CDEPO
    ///         - Validating that all of the positions are valid
    ///         - Validating that all of the positions have expired
    ///         - Burning the convertible deposit tokens
    ///         - Transferring the reserve token to `account_`
    ///         - Emitting an event
    ///
    /// @param  positionIds_    An array of position ids that will be reclaimed
    /// @param  amounts_        An array of amounts of convertible deposit tokens to reclaim
    /// @return reclaimed       The amount of reserve token returned to the caller
    function reclaim(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 reclaimed);

    /// @notice Preview the amount of reserve token that would be reclaimed before expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that convertible deposit token in the position is CDEPO
    ///         - Validating that all of the positions are valid
    ///         - Validating that all of the positions have expired
    ///         - Returning the total amount of reserve token that would be redeemed
    ///
    /// @param  account_        The address to preview the reclaim for
    /// @param  positionIds_    An array of position ids that will be reclaimed
    /// @param  amounts_        An array of amounts of convertible deposit tokens to reclaim
    /// @return reclaimed       The amount of reserve token returned to the caller
    /// @return cdTokenSpender  The address that will spend the convertible deposit tokens. The caller must have approved this address to spend the total amount of CD tokens.
    function previewReclaim(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view returns (uint256 reclaimed, address cdTokenSpender);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice The address of token accepted by the facility
    function depositToken() external view returns (address);

    /// @notice The address of the convertible deposit token that is minted by the facility
    function convertibleDepositToken() external view returns (address);

    /// @notice The address of the token that is converted to by the facility
    function convertedToken() external view returns (address);
}
