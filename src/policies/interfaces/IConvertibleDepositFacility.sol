// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @title  IConvertibleDepositFacility
/// @notice Interface for a contract that can perform functions related to convertible deposit tokens
interface IConvertibleDepositFacility {
    // ========== EVENTS ========== //

    event CreatedDeposit(address indexed user, uint256 indexed termId, uint256 amount);
    event ConvertedDeposit(
        address indexed user,
        uint256 indexed termId,
        uint256 depositAmount,
        uint256 convertedAmount
    );
    event ReclaimedDeposit(
        address indexed user,
        uint256 indexed termId,
        uint256 depositAmount,
        uint256 reclaimedAmount
    );

    // ========== ERRORS ========== //

    error CDF_InvalidArgs(string reason_);

    error CDF_NotOwner(uint256 positionId_);

    error CDF_PositionExpired(uint256 positionId_);

    error CDF_PositionNotExpired(uint256 positionId_);

    error CDF_InvalidAmount(uint256 positionId_, uint256 amount_);

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
    /// @param  conversionPrice_    The price of the reserve token in USD
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
    ///         - Validating that all of the positions are valid
    ///         - Validating that all of the positions have not expired
    ///         - Burning the convertible deposit tokens
    ///         - Minting OHM to `account_`
    ///         - Transferring the sReserve token to the treasury
    ///         - Emitting an event
    ///
    /// @param  positionIds_        An array of position ids that will be converted
    /// @param  amounts_            An array of amounts of convertible deposit tokens to convert
    /// @return totalDeposit        The total amount of convertible deposit tokens converted
    /// @return converted           The amount of OHM minted during conversion
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 totalDeposit, uint256 converted);

    /// @notice Reclaims convertible deposit tokens after expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
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
}
