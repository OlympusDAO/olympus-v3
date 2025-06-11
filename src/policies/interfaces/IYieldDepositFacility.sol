// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @title IYieldDepositFacility
/// @notice Interface for the Yield Facility that can be used to mint yield-bearing deposits
interface IYieldDepositFacility {
    // ========== EVENTS ========== //

    event CreatedDeposit(
        address indexed asset,
        address indexed depositor,
        uint256 indexed positionId,
        uint8 periodMonths,
        uint256 depositAmount
    );

    event YieldClaimed(address indexed asset, address indexed depositor, uint256 yield);

    event YieldFeeSet(uint16 yieldFee);

    event RateSnapshotTaken(address indexed vault, uint48 timestamp, uint256 rate);

    // ========== ERRORS ========== //

    error YDF_InvalidArgs(string reason_);

    error YDF_NotOwner(uint256 positionId_);

    error YDF_InvalidToken(address token_, uint8 periodMonths_);

    error YDF_Unsupported(uint256 positionId_);

    error YDF_NoSnapshotAvailable(address token, uint48 timestamp);

    // ========== MINT ========== //

    /// @notice Creates a position for a yield-bearing deposit
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the asset is supported
    ///         - Depositing the asset into the deposit manager and minting the receipt token
    ///         - Creating a new position in the CDPOS module
    ///
    /// @param  asset_              The address of the asset
    /// @param  periodMonths_       The period of the deposit
    /// @param  amount_             The amount of token to deposit
    /// @param  wrapPosition_       Whether the position should be wrapped
    /// @param  wrapReceipt_        Whether the receipt token should be wrapped
    /// @return positionId          The ID of the new position
    function createPosition(
        IERC20 asset_,
        uint8 periodMonths_,
        uint256 amount_,
        bool wrapPosition_,
        bool wrapReceipt_
    ) external returns (uint256 positionId);

    // ========== YIELD ========== //

    /// @notice Preview the amount of yield that would be claimed for the given positions
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Returning the total amount of yield that would be claimed
    ///
    /// @param  account_        The address to preview the yield for
    /// @param  positionIds_    An array of position ids that will be claimed
    /// @return yield           The amount of yield that would be claimed
    /// @return asset           The address of the asset that will be received
    function previewClaimYield(
        address account_,
        uint256[] memory positionIds_
    ) external view returns (uint256 yield, IERC20 asset);

    /// @notice Preview the amount of yield that would be claimed for the given positions with timestamp hints
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Using the provided timestamp hints if valid
    ///         - Returning the total amount of yield that would be claimed
    ///
    /// @param  account_        The address to preview the yield for
    /// @param  positionIds_    An array of position ids that will be claimed
    /// @param  timestampHints_ An array of timestamp hints for each position
    /// @return yield           The amount of yield that would be claimed
    /// @return asset           The address of the asset that will be received
    function previewClaimYield(
        address account_,
        uint256[] memory positionIds_,
        uint48[] memory timestampHints_
    ) external view returns (uint256 yield, IERC20 asset);

    /// @notice Claims the yield for the given positions
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Burning the CD tokens
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @param  positionIds_    An array of position ids that will be claimed
    /// @return yield           The amount of yield that was claimed
    function claimYield(uint256[] memory positionIds_) external returns (uint256 yield);

    /// @notice Claims the yield for the given positions with timestamp hints
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Using the provided timestamp hints if valid
    ///         - Burning the CD tokens
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @param  positionIds_    An array of position ids that will be claimed
    /// @param  timestampHints_ An array of timestamp hints for each position
    /// @return yield           The amount of yield that was claimed
    function claimYield(
        uint256[] memory positionIds_,
        uint48[] memory timestampHints_
    ) external returns (uint256 yield);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Sets the percentage of yield that will be taken as a fee
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the yield fee
    ///
    /// @param  yieldFee_       The percentage of yield that will be taken as a fee, in terms of 100e2
    function setYieldFee(uint16 yieldFee_) external;

    /// @notice Returns the percentage of yield that will be taken as a fee
    ///
    /// @return yieldFee The percentage of yield that will be taken as a fee, in terms of 100e2
    function getYieldFee() external view returns (uint16 yieldFee);
}
