// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IConvertibleDepositFacility
/// @notice Interface for a contract that can perform functions related to convertible deposit (CD) tokens
interface IConvertibleDepositFacility {
    // ========== EVENTS ========== //

    event CreatedDeposit(
        address indexed asset,
        address indexed depositor,
        uint256 indexed positionId,
        uint8 periodMonths,
        uint256 depositAmount
    );

    event ConvertedDeposit(
        address indexed asset,
        address indexed depositor,
        uint8 periodMonths,
        uint256 depositAmount,
        uint256 convertedAmount
    );

    event ClaimedYield(address indexed asset, uint256 amount);

    // ========== ERRORS ========== //

    error CDF_InvalidArgs(string reason_);

    error CDF_NotOwner(uint256 positionId_);

    error CDF_PositionExpired(uint256 positionId_);

    error CDF_InvalidAmount(uint256 positionId_, uint256 amount_);

    error CDF_InvalidToken(uint256 positionId_, address token_, uint8 periodMonths_);

    error CDF_Unsupported(uint256 positionId_);

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @notice Creates a convertible deposit position
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the asset is supported
    ///         - Validating that the caller has the correct role
    ///         - Depositing the asset
    ///         - Minting the receipt token
    ///         - Creating a new position in the DEPOS module
    ///         - Emitting an event
    ///
    /// @param  asset_              The address of the asset
    /// @param  periodMonths_       The period of the deposit
    /// @param  account_            The address to create the position for
    /// @param  amount_             The amount of asset to deposit
    /// @param  conversionPrice_    The amount of converted tokens per asset token
    /// @param  wrapPosition_       Whether the position should be wrapped
    /// @param  wrapReceipt_        Whether the receipt token should be wrapped
    /// @return positionId          The ID of the new position
    function createPosition(
        IERC20 asset_,
        uint8 periodMonths_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_,
        bool wrapReceipt_
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

    /// @notice Converts receipt tokens to OHM before conversion expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that the token in the position is a supported receipt token
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has not passed
    ///         - Burning the receipt tokens
    ///         - Minting OHM to `account_`
    ///         - Transferring the deposit token to the treasury
    ///         - Emitting an event
    ///
    /// @param  positionIds_        An array of position ids that will be converted
    /// @param  amounts_            An array of amounts of receipt tokens to convert
    /// @param  wrappedReceipt_     Whether the receipt tokens to use are wrapped as ERC20s
    /// @return receiptTokenIn           The total amount of receipt tokens converted
    /// @return convertedTokenOut   The amount of OHM minted during conversion
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_,
        bool wrappedReceipt_
    ) external returns (uint256 receiptTokenIn, uint256 convertedTokenOut);

    /// @notice Preview the amount of receipt tokens and OHM that would be converted
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that token in the position is a supported receipt token
    ///         - Validating that all of the positions are valid
    ///         - Validating that the conversion expiry for all of the positions has not passed
    ///         - Returning the total amount of receipt tokens and OHM that would be converted
    ///
    /// @param  account_            The address to preview the conversion for
    /// @param  positionIds_        An array of position ids that will be converted
    /// @param  amounts_            An array of amounts of receipt tokens to convert
    /// @return receiptTokenIn      The total amount of receipt tokens converted
    /// @return convertedTokenOut   The amount of OHM minted during conversion
    function previewConvert(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view returns (uint256 receiptTokenIn, uint256 convertedTokenOut);

    // ========== YIELD ========== //

    /// @notice Preview the amount of yield that would be claimed for the given asset
    ///
    /// @param  asset_          The address of the asset
    /// @return assets          The amount of assets that would be claimed
    function previewClaimYield(IERC20 asset_) external view returns (uint256 assets);

    /// @notice Claim the yield accrued for the given asset
    ///
    /// @param  asset_          The address of the asset
    /// @return assets          The amount of assets that were claimed
    function claimYield(IERC20 asset_) external returns (uint256 assets);

    /// @notice Claim the yield accrued for all assets and deposit periods
    function claimAllYield() external;

    // ========== VIEW FUNCTIONS ========== //

    /// @notice The address of the token that is converted to by the facility
    function convertedToken() external view returns (address);
}
