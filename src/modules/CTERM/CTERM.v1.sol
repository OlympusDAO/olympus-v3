// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

/// @title  CTERMv1
/// @notice This defines the interface for the CTERM module.
///         The objective of this module is to track the terms of a convertible deposit.
abstract contract CTERMv1 is Module, ERC721 {
    // ========== DATA STRUCTURES ========== //

    /// @notice Data structure for the terms of a convertible deposit
    ///
    /// @param  remainingDeposit Amount of reserve tokens remaining to be converted
    /// @param  conversionPrice  Price of the reserve token in USD
    /// @param  expiry           Timestamp when the term expires
    /// @param  wrapped          Whether the term is wrapped
    struct ConvertibleDepositTerm {
        uint256 remainingDeposit;
        uint256 conversionPrice;
        uint48 expiry;
        bool wrapped;
    }

    // ========== EVENTS ========== //

    /// @notice Emitted when a term is created
    event TermCreated(
        uint256 indexed termId,
        address indexed owner,
        uint256 remainingDeposit,
        uint256 conversionPrice,
        uint48 expiry,
        bool wrapped
    );

    /// @notice Emitted when a term is updated
    event TermUpdated(uint256 indexed termId, uint256 remainingDeposit);

    /// @notice Emitted when a term is split
    event TermSplit(
        uint256 indexed termId,
        uint256 newTermId,
        uint256 amount,
        address to,
        bool wrap
    );

    /// @notice Emitted when a term is wrapped
    event TermWrapped(uint256 indexed termId);

    /// @notice Emitted when a term is unwrapped
    event TermUnwrapped(uint256 indexed termId);

    // ========== STATE VARIABLES ========== //

    /// @notice The number of terms created
    uint256 public termCount;

    /// @notice Mapping of term records to an ID
    /// @dev    IDs are assigned sequentially starting from 0
    ///         Mapping entries should not be deleted, but can be overwritten
    mapping(uint256 => ConvertibleDepositTerm) internal _terms;

    /// @notice Mapping of user addresses to their term IDs
    mapping(address => uint256[]) internal _userTerms;

    // ========== ERRORS ========== //

    /// @notice Error thrown when the caller is not the owner of the term
    error CTERM_NotOwner(uint256 termId_);

    /// @notice Error thrown when an invalid term ID is provided
    error CTERM_InvalidTermId(uint256 id_);

    /// @notice Error thrown when a term has already been wrapped
    error CTERM_AlreadyWrapped(uint256 termId_);

    /// @notice Error thrown when a term has not been wrapped
    error CTERM_NotWrapped(uint256 termId_);

    /// @notice Error thrown when an invalid parameter is provided
    error CTERM_InvalidParams(string reason_);

    // ========== WRAPPING ========== //

    /// @notice Wraps a term into an ERC721 token
    /// @dev    This is useful if the term owner wants a tokenized representation of their term. It is functionally equivalent to the term itself.
    ///
    ///        The implementing function should do the following:
    ///        - Validate that the caller is the owner of the term
    ///        - Validate that the term is not already wrapped
    ///        - Mint an ERC721 token to the term owner
    ///
    /// @param  termId_ The ID of the term to wrap
    function wrap(uint256 termId_) external virtual;

    /// @notice Unwraps an ERC721 token into a term
    /// @dev    This is useful if the term owner wants to convert their token back into the term.
    ///
    ///         The implementing function should do the following:
    ///         - Validate that the caller is the owner of the term
    ///         - Validate that the term is already wrapped
    ///         - Burn the ERC721 token
    ///
    /// @param  termId_ The ID of the term to unwrap
    function unwrap(uint256 termId_) external virtual;

    // ========== TERM MANAGEMENT =========== //

    /// @notice Creates a new convertible deposit term
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is permissioned
    ///         - Validate that the owner is not the zero address
    ///         - Validate that the remaining deposit is greater than 0
    ///         - Validate that the conversion price is greater than 0
    ///         - Validate that the expiry is in the future
    ///         - Create the term record
    ///         - Wrap the term if requested
    ///
    /// @param  owner_              The address of the owner of the term
    /// @param  remainingDeposit_   The amount of reserve tokens remaining to be converted
    /// @param  conversionPrice_    The price of the reserve token in USD
    /// @param  expiry_             The timestamp when the term expires
    /// @param  wrap_               Whether the term should be wrapped
    /// @return termId             The ID of the new term
    function create(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) external virtual returns (uint256 termId);

    /// @notice Updates the remaining deposit of a term
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is permissioned
    ///         - Validate that the term ID is valid
    ///         - Update the remaining deposit of the term
    ///
    /// @param  termId_ The ID of the term to update
    /// @param  amount_ The new amount of the term
    function update(uint256 termId_, uint256 amount_) external virtual;

    /// @notice Splits the specified amount of the term into a new term
    ///         This is useful if the term owner wants to split their term into multiple smaller terms.
    /// @dev    The implementing function should do the following:
    ///         - Validate that the caller is the owner of the term
    ///         - Validate that the amount is greater than 0
    ///         - Validate that the amount is less than or equal to the remaining deposit
    ///         - Validate that `to_` is not the zero address
    ///         - Update the remaining deposit of the original term
    ///         - Create the new term record
    ///         - Wrap the new term if requested
    ///
    /// @param  termId_       The ID of the term to split
    /// @param  amount_       The amount of the term to split
    /// @param  to_           The address to split the term to
    /// @param  wrap_         Whether the new term should be wrapped
    /// @return newTermId     The ID of the new term
    function split(
        uint256 termId_,
        uint256 amount_,
        address to_,
        bool wrap_
    ) external virtual returns (uint256 newTermId);

    // ========== TERM INFORMATION ========== //

    /// @notice Get the IDs of all terms for a given user
    ///
    /// @param  user_       The address of the user
    /// @return termIds     An array of term IDs
    function getUserTermIds(address user_) external view virtual returns (uint256[] memory termIds);

    /// @notice Get the terms for a given ID
    ///
    /// @param  termId_     The ID of the term
    /// @return term        The terms for the given ID
    function getTerm(uint256 termId_) external view virtual returns (ConvertibleDepositTerm memory);
}
