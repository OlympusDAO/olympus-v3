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

    event ClaimedYield(address indexed asset, address indexed depositor, uint256 yield);

    event YieldFeeSet(uint16 yieldFee);

    event RateSnapshotTaken(address indexed vault, uint48 timestamp, uint256 rate);

    // ========== ERRORS ========== //

    error YDF_InvalidArgs(string reason_);

    error YDF_NotOwner(uint256 positionId_);

    error YDF_InvalidToken(address token_, uint8 periodMonths_);

    error YDF_Unsupported(uint256 positionId_);

    error YDF_NoRateSnapshot(address vault_, uint48 timestamp_);

    // ========== DATA STRUCTURES ========== //

    /// @notice Parameters for the {createPosition} function
    ///
    /// @param asset             The address of the asset
    /// @param periodMonths      The period of the deposit
    /// @param amount            The amount of asset to deposit
    /// @param wrapPosition      Whether the position should be wrapped
    /// @param wrapReceipt       Whether the receipt token should be wrapped
    struct CreatePositionParams {
        IERC20 asset;
        uint8 periodMonths;
        uint256 amount;
        bool wrapPosition;
        bool wrapReceipt;
    }

    // ========== MINT ========== //

    /// @notice Creates a position for a yield-bearing deposit
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the asset is supported
    ///         - Depositing the asset into the deposit manager and minting the receipt token
    ///         - Creating a new position in the DEPOS module
    ///
    /// @param  params_             The parameters for the position creation
    /// @return positionId          The ID of the new position
    /// @return receiptTokenId      The ID of the receipt token
    /// @return actualAmount        The quantity of receipt tokens minted to the depositor
    function createPosition(
        CreatePositionParams calldata params_
    ) external returns (uint256 positionId, uint256 receiptTokenId, uint256 actualAmount);

    /// @notice Deposits the given amount of the underlying asset in exchange for a receipt token. This function can be used to mint additional receipt tokens on a 1:1 basis, without creating a new position.
    ///
    /// @param  asset_              The address of the asset
    /// @param  periodMonths_       The period of the deposit
    /// @param  amount_             The amount of asset to deposit
    /// @param  wrapReceipt_        Whether the receipt token should be wrapped
    /// @return receiptTokenId      The ID of the receipt token
    /// @return actualAmount        The quantity of receipt tokens minted to the depositor
    function deposit(
        IERC20 asset_,
        uint8 periodMonths_,
        uint256 amount_,
        bool wrapReceipt_
    ) external returns (uint256 receiptTokenId, uint256 actualAmount);

    // ========== YIELD ========== //

    /// @notice Preview the amount of yield that would be claimed for the given positions
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that token in the position is a supported receipt token
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

    /// @notice Claims the yield for the given positions
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that token in the position is a supported receipt token
    ///         - Validating that all of the positions are valid
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @param  positionIds_    An array of position ids that will be claimed
    /// @return yield           The amount of yield that was claimed
    function claimYield(uint256[] memory positionIds_) external returns (uint256 yield);

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
