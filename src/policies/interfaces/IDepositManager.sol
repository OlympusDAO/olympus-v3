// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

/// @title Deposit Manager
/// @notice Defines an interface for a policy that manages deposits on behalf of other contracts. It is meant to be used by the facilities, and is not an end-user policy.
interface IDepositManager {
    // ========== EVENTS ========== //

    event ClaimedYield(
        address indexed asset,
        address indexed depositor,
        address indexed operator,
        uint256 amount
    );

    event ReceiptTokenConfigured(
        uint256 indexed receiptTokenId,
        address indexed asset,
        uint8 depositPeriod
    );

    event ReclaimRateUpdated(address indexed asset, uint8 depositPeriod, uint16 reclaimRate);

    // ========== ERRORS ========== //

    error DepositManager_Insolvent(address asset, uint256 sharesRequired, uint256 sharesDeposited);

    error DepositManager_ZeroAmount();

    error DepositManager_OutOfBounds();

    error DepositManager_AssetNotConfigured(address asset, uint8 depositPeriod);

    // ========== STRUCTS ========== //

    struct DepositConfiguration {
        IERC20 asset;
        uint8 depositPeriod;
        uint16 reclaimRate;
    }

    // ========== DEPOSIT/WITHDRAW FUNCTIONS ========== //

    /// @notice Deposits the given amount of the underlying asset in exchange for a receipt token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the underlying asset from the depositor to the contract
    ///         - Minting the receipt token to the depositor
    ///         - Updating the amount of deposited funds
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  depositor_      The depositor
    /// @param  amount_         The amount to deposit
    /// @param  shouldWrap_     Whether the receipt token should be wrapped
    /// @return shares          The number of vault shares equivalent to the deposited amount
    function deposit(
        IERC20 asset_,
        uint8 depositPeriod_,
        address depositor_,
        uint256 amount_,
        bool shouldWrap_
    ) external returns (uint256 shares);

    /// @notice Claims the yield from the underlying asset
    ///         This does not burn receipt tokens, but should reduce the amount of shares the caller has in the vault.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the underlying asset from the contract to the recipient
    ///         - Updating the amount of deposited funds
    ///         - Checking solvency
    ///
    /// @param  asset_        The address of the underlying asset
    /// @param  recipient_    The recipient of the claimed yield
    /// @param  amount_       The amount to claim yield for
    function claimYield(IERC20 asset_, address recipient_, uint256 amount_) external;

    /// @notice Withdraws the given amount of the underlying asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Burning the receipt token
    ///         - Transferring the underlying asset from the contract to the recipient
    ///         - Updating the amount of deposited funds
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  depositor_      The depositor that is holding the receipt tokens
    /// @param  recipient_      The recipient of the withdrawn asset
    /// @param  amount_         The amount to withdraw
    /// @param  wrapped_        Whether the receipt token is wrapped
    /// @return shares          The number of vault shares equivalent to the withdrawn amount
    function withdraw(
        IERC20 asset_,
        uint8 depositPeriod_,
        address depositor_,
        address recipient_,
        uint256 amount_,
        bool wrapped_
    ) external returns (uint256 shares);

    // ========== TOKEN FUNCTIONS ========== //

    /// @notice Configures a new deposit asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Creating a new receipt token
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  vault_          The address of the vault to use for the receipt token (or the zero address)
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  reclaimRate_    The reclaim rate to set for the deposit
    /// @return receiptTokenId  The ID of the new receipt token
    function configureDeposit(
        IERC20 asset_,
        IERC4626 vault_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) external returns (uint256 receiptTokenId);

    /// @notice Returns whether a deposit asset and period are supported
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @return isConfigured    Whether the deposit asset is configured
    function isDepositAsset(IERC20 asset_, uint8 depositPeriod_) external view returns (bool);

    /// @notice Returns the deposit assets
    ///
    /// @return depositAssets   The deposit assets
    function getDepositAssets() external view returns (DepositConfiguration[] memory depositAssets);

    /// @notice Returns the asset and deposit period from a receipt token ID
    ///
    /// @param  tokenId_        The ID of the receipt token
    /// @return asset           The address of the underlying asset (or the zero address)
    /// @return depositPeriod   The deposit period, in months (or 0)
    function getAssetFromTokenId(
        uint256 tokenId_
    ) external view returns (IERC20 asset, uint8 depositPeriod);

    // ========== RECLAIM RATE ========== //

    /// @notice Sets the reclaim rate for a deposit
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the reclaim rate for the deposit
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  reclaimRate_    The reclaim rate to set
    function setDepositReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) external;

    /// @notice Returns the reclaim rate for a deposit
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @return reclaimRate     The reclaim rate for the deposit
    function getDepositReclaimRate(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external view returns (uint16 reclaimRate);

    // ========== RECEIPT TOKEN FUNCTIONS ========== //

    /// @notice Returns the ID of the receipt token for a deposit asset
    /// @dev    The ID returned is not a guarantee that the asset is configured. {isDepositAsset} should be used for that purpose.
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @return receiptTokenId  The ID of the receipt token
    function getReceiptTokenId(IERC20 asset_, uint8 depositPeriod_) external view returns (uint256);
}
