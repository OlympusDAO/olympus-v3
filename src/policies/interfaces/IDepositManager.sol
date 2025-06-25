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

    event DepositConfigured(
        uint256 indexed receiptTokenId,
        address indexed asset,
        uint8 depositPeriod
    );

    event DepositConfigurationEnabled(
        uint256 indexed receiptTokenId,
        address indexed asset,
        uint8 depositPeriod
    );

    event DepositConfigurationDisabled(
        uint256 indexed receiptTokenId,
        address indexed asset,
        uint8 depositPeriod
    );

    event ReclaimRateUpdated(address indexed asset, uint8 depositPeriod, uint16 reclaimRate);

    // ========== ERRORS ========== //

    error DepositManager_Insolvent(address asset, uint256 requiredAssets);

    error DepositManager_ZeroAddress();

    error DepositManager_OutOfBounds();

    error DepositManager_InvalidAsset();

    error DepositManager_InvalidConfiguration(address asset, uint8 depositPeriod);

    error DepositManager_ConfigurationExists(address asset, uint8 depositPeriod);

    error DepositManager_ConfigurationEnabled(address asset, uint8 depositPeriod);

    error DepositManager_ConfigurationDisabled(address asset, uint8 depositPeriod);

    // ========== STRUCTS ========== //

    /// @notice A deposit configuration, representing a deposit asset and period combination
    ///
    /// @param isEnabled       Whether the deposit configuration is enabled for new deposits
    /// @param depositPeriod   The deposit period, in months
    /// @param reclaimRate     The reclaim rate for the deposit (see the implementation contract for scale)
    /// @param asset           The underlying ERC20 asset
    struct DepositConfiguration {
        bool isEnabled;
        uint8 depositPeriod;
        uint16 reclaimRate;
        address asset;
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
    /// @return receiptTokenId  The ID of the receipt token
    /// @return actualAmount    The quantity of receipt tokens minted to the depositor
    function deposit(
        IERC20 asset_,
        uint8 depositPeriod_,
        address depositor_,
        uint256 amount_,
        bool shouldWrap_
    ) external returns (uint256 receiptTokenId, uint256 actualAmount);

    /// @notice Returns the maximum yield that can be claimed for an asset and operator pair
    ///
    /// @param  asset_        The address of the underlying asset
    /// @param  operator_     The address of the operator
    /// @return yieldAssets   The amount of yield that can be claimed
    function maxClaimYield(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 yieldAssets);

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
    /// @return actualAmount    The quantity of underlying assets transferred to the recipient
    function withdraw(
        IERC20 asset_,
        uint8 depositPeriod_,
        address depositor_,
        address recipient_,
        uint256 amount_,
        bool wrapped_
    ) external returns (uint256 actualAmount);

    /// @notice Returns the liabilities for an asset and operator pair
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  operator_       The address of the operator
    /// @return liabilities     The quantity of assets that the contract is custodying for the operator's depositors
    function getOperatorLiabilities(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 liabilities);

    // ========== DEPOSIT CONFIGURATIONS ========== //

    /// @notice Configures an asset to be deposited into a vault
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Configuring the asset
    ///         - Emitting an event
    ///
    /// @param  asset_  The address of the underlying asset
    /// @param  vault_  The address of the vault to use for the receipt token (or the zero address)
    function configureAssetVault(IERC20 asset_, IERC4626 vault_) external;

    /// @notice Adds a new deposit configuration
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Creating a new receipt token
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @param  reclaimRate_    The reclaim rate to set for the deposit
    /// @return receiptTokenId  The ID of the new receipt token
    function addDepositConfiguration(
        IERC20 asset_,
        uint8 depositPeriod_,
        uint16 reclaimRate_
    ) external returns (uint256 receiptTokenId);

    /// @notice Disables a deposit configuration, which prevents new deposits
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Disabling the deposit configuration
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    function disableDepositConfiguration(IERC20 asset_, uint8 depositPeriod_) external;

    /// @notice Enables a deposit configuration, which allows new deposits
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Enabling the deposit configuration
    ///         - Emitting an event
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    function enableDepositConfiguration(IERC20 asset_, uint8 depositPeriod_) external;

    /// @notice Returns the deposit configuration for an asset and period
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @return configuration   The deposit configuration
    function getDepositConfiguration(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external view returns (DepositConfiguration memory configuration);

    /// @notice Returns the deposit configuration from a receipt token ID
    ///
    /// @param  tokenId_        The ID of the receipt token
    /// @return configuration   The deposit configuration
    function getDepositConfiguration(
        uint256 tokenId_
    ) external view returns (DepositConfiguration memory configuration);

    /// @notice Returns whether a deposit asset and period combination are configured
    /// @dev    A deposit configuration that is disabled will not accept further deposits
    ///
    /// @param  asset_          The address of the underlying asset
    /// @param  depositPeriod_  The deposit period, in months
    /// @return isConfigured    Whether the deposit asset is configured
    /// @return isEnabled       Whether the deposit asset is enabled
    function isConfiguredDeposit(
        IERC20 asset_,
        uint8 depositPeriod_
    ) external view returns (bool isConfigured, bool isEnabled);

    /// @notice Returns the deposit configurations
    ///
    /// @return depositConfigurations   The deposit configurations
    function getDepositConfigurations()
        external
        view
        returns (DepositConfiguration[] memory depositConfigurations);

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

    /// @notice Returns the name of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return name        The name of the receipt token
    function getReceiptTokenName(uint256 tokenId_) external view returns (string memory);

    /// @notice Returns the symbol of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return symbol      The symbol of the receipt token
    function getReceiptTokenSymbol(uint256 tokenId_) external view returns (string memory);

    /// @notice Returns the decimals of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return decimals    The decimals of the receipt token
    function getReceiptTokenDecimals(uint256 tokenId_) external view returns (uint8);

    /// @notice Returns the owner of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return owner       The owner of the receipt token
    function getReceiptTokenOwner(uint256 tokenId_) external view returns (address);

    /// @notice Returns the asset of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return asset       The asset of the receipt token
    function getReceiptTokenAsset(uint256 tokenId_) external view returns (IERC20);

    /// @notice Returns the deposit period of a receipt token
    ///
    /// @param  tokenId_        The ID of the receipt token
    /// @return depositPeriod   The deposit period of the receipt token
    function getReceiptTokenDepositPeriod(
        uint256 tokenId_
    ) external view returns (uint8 depositPeriod);
}
