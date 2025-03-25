// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

/// @title  CDPOSv1
/// @notice This defines the interface for the CDPOS module.
///         The objective of this module is to track the terms of a convertible deposit.
abstract contract CDPOSv1 is Module, ERC721 {
    // ========== DATA STRUCTURES ========== //

    /// @notice Data structure for the terms of a convertible deposit
    ///
    /// @param  owner                   Address of the owner of the position
    /// @param  convertibleDepositToken Address of the convertible deposit token
    /// @param  remainingDeposit        Amount of reserve tokens remaining to be converted
    /// @param  conversionPrice         The amount of convertible deposit tokens per OHM token
    /// @param  conversionExpiry        Timestamp when the deposit can no longer be converted
    /// @param  wrapped                 Whether the term is wrapped
    struct Position {
        address owner;
        address convertibleDepositToken;
        uint256 remainingDeposit;
        uint256 conversionPrice;
        uint48 conversionExpiry;
        bool wrapped;
    }

    // ========== EVENTS ========== //

    /// @notice Emitted when a position is created
    event PositionCreated(
        uint256 indexed positionId,
        address indexed owner,
        address indexed convertibleDepositToken,
        uint256 remainingDeposit,
        uint256 conversionPrice,
        uint48 conversionExpiry,
        bool wrapped
    );

    /// @notice Emitted when a position is updated
    event PositionUpdated(uint256 indexed positionId, uint256 remainingDeposit);

    /// @notice Emitted when a position is split
    event PositionSplit(
        uint256 indexed positionId,
        uint256 indexed newPositionId,
        address indexed convertibleDepositToken,
        uint256 amount,
        address to,
        bool wrap
    );

    /// @notice Emitted when a position is wrapped
    event PositionWrapped(uint256 indexed positionId);

    /// @notice Emitted when a position is unwrapped
    event PositionUnwrapped(uint256 indexed positionId);

    // ========== STATE VARIABLES ========== //

    /// @notice The number of positions created
    uint256 public positionCount;

    /// @notice Mapping of position records to an ID
    /// @dev    IDs are assigned sequentially starting from 0
    ///         Mapping entries should not be deleted, but can be overwritten
    mapping(uint256 => Position) internal _positions;

    /// @notice Mapping of user addresses to their position IDs
    mapping(address => uint256[]) internal _userPositions;

    // ========== ERRORS ========== //

    /// @notice Error thrown when the caller is not the owner of the position
    error CDPOS_NotOwner(uint256 positionId_);

    /// @notice Error thrown when an invalid position ID is provided
    error CDPOS_InvalidPositionId(uint256 id_);

    /// @notice Error thrown when a position has already been wrapped
    error CDPOS_AlreadyWrapped(uint256 positionId_);

    /// @notice Error thrown when a position has not been wrapped
    error CDPOS_NotWrapped(uint256 positionId_);

    /// @notice Error thrown when an invalid parameter is provided
    error CDPOS_InvalidParams(string reason_);

    // ========== WRAPPING ========== //

    /// @notice Wraps a position into an ERC721 token
    ///         This is useful if the position owner wants a tokenized representation of their position. It is functionally equivalent to the position itself.
    ///
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is the owner of the position
    ///         - Validate that the position is not already wrapped
    ///         - Mint an ERC721 token to the position owner
    ///
    /// @param  positionId_ The ID of the position to wrap
    function wrap(uint256 positionId_) external virtual;

    /// @notice Unwraps/burns an ERC721 position token
    ///         This is useful if the position owner wants to convert their token back into the position.
    ///
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is the owner of the position
    ///         - Validate that the position is already wrapped
    ///         - Burn the ERC721 token
    ///
    /// @param  positionId_ The ID of the position to unwrap
    function unwrap(uint256 positionId_) external virtual;

    // ========== POSITION MANAGEMENT =========== //

    /// @notice Creates a new convertible deposit position
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is permissioned
    ///         - Validate that the owner is not the zero address
    ///         - Validate that the convertible deposit token is not the zero address
    ///         - Validate that the remaining deposit is greater than 0
    ///         - Validate that the conversion price is greater than 0
    ///         - Validate that the conversion expiry is in the future
    ///         - Validate that the redemption expiry is after the conversion expiry
    ///         - Create the position record
    ///         - Wrap the position if requested
    ///
    /// @param  owner_                      The address of the owner of the position
    /// @param  convertibleDepositToken_    The address of the convertible deposit token
    /// @param  remainingDeposit_           The amount of reserve tokens remaining to be converted
    /// @param  conversionPrice_            The price of the reserve token in USD
    /// @param  conversionExpiry_           The timestamp when the position can no longer be converted
    /// @param  wrap_                       Whether the position should be wrapped
    /// @return positionId                  The ID of the new position
    function mint(
        address owner_,
        address convertibleDepositToken_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        bool wrap_
    ) external virtual returns (uint256 positionId);

    /// @notice Updates the remaining deposit of a position
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is permissioned
    ///         - Validate that the position ID is valid
    ///         - Update the remaining deposit of the position
    ///
    /// @param  positionId_ The ID of the position to update
    /// @param  amount_     The new amount of the position
    function update(uint256 positionId_, uint256 amount_) external virtual;

    /// @notice Splits the specified amount of the position into a new position
    ///         This is useful if the position owner wants to split their position into multiple smaller positions.
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is the owner of the position
    ///         - Validate that the amount is greater than 0
    ///         - Validate that the amount is less than or equal to the remaining deposit
    ///         - Validate that `to_` is not the zero address
    ///         - Update the remaining deposit of the original position
    ///         - Create the new position record
    ///         - Wrap the new position if requested
    ///
    /// @param  positionId_   The ID of the position to split
    /// @param  amount_       The amount of the position to split
    /// @param  to_           The address to split the position to
    /// @param  wrap_         Whether the new position should be wrapped
    /// @return newPositionId The ID of the new position
    function split(
        uint256 positionId_,
        uint256 amount_,
        address to_,
        bool wrap_
    ) external virtual returns (uint256 newPositionId);

    // ========== POSITION INFORMATION ========== //

    /// @notice Get the IDs of all positions for a given user
    ///
    /// @param  user_       The address of the user
    /// @return positionIds An array of position IDs
    function getUserPositionIds(
        address user_
    ) external view virtual returns (uint256[] memory positionIds);

    /// @notice Get the positions for a given ID
    ///
    /// @param  positionId_ The ID of the position
    /// @return position    The positions for the given ID
    function getPosition(uint256 positionId_) external view virtual returns (Position memory);

    /// @notice Check if a position is expired
    ///
    /// @param  positionId_ The ID of the position
    /// @return expired_    Whether the position is expired
    function isExpired(uint256 positionId_) external view virtual returns (bool);

    /// @notice Preview the amount of OHM that would be received for a given amount of convertible deposit tokens
    ///
    /// @param  positionId_ The ID of the position
    /// @param  amount_     The amount of convertible deposit tokens to convert
    /// @return ohmOut      The amount of OHM that would be received
    function previewConvert(
        uint256 positionId_,
        uint256 amount_
    ) external view virtual returns (uint256 ohmOut);
}
