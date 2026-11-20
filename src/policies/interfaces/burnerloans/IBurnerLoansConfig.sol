// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

/// @title Burner Loans Config Interface
/// @notice Opinionated administration surface for Burner Loans markets stored in FLOAN.
interface IBurnerLoansConfig {
    // ========== EVENTS ========== //

    /// @notice Emitted when Config creates and registers a collateral market.
    /// @param asset Collateral asset added to Burner Loans.
    /// @param config Initial collateral market configuration.
    event AssetAdded(address indexed asset, IBurnerLoansCore.AssetConfig config);

    /// @notice Emitted when an asset's active-principal cap changes.
    /// @param asset Collateral asset whose cap changed.
    /// @param debtCapOhm New debt cap, in OHM decimals.
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);

    /// @notice Emitted when an asset's risk and term configuration changes.
    /// @param asset Collateral asset whose configuration changed.
    /// @param config New risk and term configuration.
    event AssetRiskConfigSet(address indexed asset, IBurnerLoansRisk.AssetRiskConfigInput config);

    /// @notice Emitted when an asset's utilization fee curve changes.
    /// @param asset Collateral asset whose fee configuration changed.
    /// @param config New utilization fee configuration.
    event AssetFeeConfigSet(address indexed asset, IBurnerLoansRisk.AssetFeeConfig config);

    /// @notice Emitted when new originations are enabled or disabled for an asset.
    /// @param asset Collateral asset whose origination state changed.
    /// @param enabled Whether new originations are enabled.
    event AssetOriginationsSet(address indexed asset, bool enabled);

    /// @notice Emitted when an asset's custody output mode changes.
    /// @param asset Collateral asset whose output mode changed.
    /// @param withdrawAsShares Whether future custody exits return ERC-4626 shares.
    event AssetWithdrawAsSharesSet(address indexed asset, bool withdrawAsShares);

    // ========== ERRORS ========== //

    /// @notice A forwarding controller is no longer Config's selected operator.
    /// @param caller_ Unselected controller.
    error BurnerLoansConfig_UnauthorizedConfigOperator(address caller_);

    /// @notice The supplied collateral asset cannot be used by Burner Loans.
    /// @param asset Invalid collateral asset.
    error BurnerLoans_InvalidCollateralAsset(address asset);

    /// @notice The collateral asset is already registered by Burner Loans.
    /// @param asset Already-registered collateral asset.
    error BurnerLoans_AssetAlreadyConfigured(address asset);

    /// @notice The Core identity or required compatibility metadata is invalid.
    /// @param core_ Invalid Core candidate.
    error BurnerLoansConfig_InvalidCore(address core_);

    /// @notice The collateral asset or Core's deposit period is not registered in DepositManager.
    /// @param asset_ Collateral asset requiring registration.
    /// @param depositManager_ DepositManager whose registration is missing.
    error BurnerLoans_AssetNotRegisteredInDepositManager(address asset_, address depositManager_);

    // ========== FUNCTIONS ========== //

    /// @notice Forwards an unreserved token rescue to the facility.
    /// @param token_ Token to rescue.
    /// @param destination_ Rescue recipient.
    function rescue(address token_, address destination_) external;

    /// @notice Quotes Core's current direct token balance through this Config for any requester.
    /// @param token_ Token whose recoverable direct balance is quoted.
    /// @param destination_ Prospective recovery recipient.
    /// @return amount Current recoverable balance; a quote grants no execution authority.
    function previewRescue(
        address token_,
        address destination_
    ) external view returns (uint256 amount);

    /// @notice Returns the OHM debt token configured for new markets.
    /// @return ohm_ OHM token address.
    function ohm() external view returns (address ohm_);

    /// @notice Returns the Burner Loans facility whose FLOAN markets this policy configures.
    /// @return facility_ Bound Burner Loans facility.
    function facility() external view returns (address facility_);

    /// @notice Returns Burner Loans' current Burner Loans Inventory contract.
    /// @return inventory_ Current Burner Loans Inventory resolved through the bound facility.
    function inventory() external view returns (address inventory_);

    /// @notice Returns whether at least one bound FLOAN market exists for a collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return configured True when a matching market exists.
    function isAssetConfigured(address asset_) external view returns (bool configured);

    /// @notice Returns the configuration for a Burner Loans collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return config Decoded asset configuration.
    function getAssetConfig(
        address asset_
    ) external view returns (IBurnerLoansCore.AssetConfig memory config);

    /// @notice Returns the fee configuration for a Burner Loans collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return config Decoded utilization fee configuration.
    function getAssetFeeConfig(
        address asset_
    ) external view returns (IBurnerLoansRisk.AssetFeeConfig memory config);

    /// @notice Returns the unique bound FLOAN market identifier for a collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return marketId_ Unique FLOAN market identifier.
    function marketId(address asset_) external view returns (uint32 marketId_);

    /// @notice Validates a complete asset risk configuration against Burner Loans bounds.
    /// @param asset_ Registered collateral market to validate.
    /// @param config_ Complete proposed risk configuration.
    function validateAssetRiskConfig(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata config_
    ) external view;

    /// @notice Validates a complete fee curve.
    /// @param asset_ Registered collateral market to validate.
    /// @param config_ Complete proposed fee configuration.
    function validateFeeConfig(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig calldata config_
    ) external view;

    /// @notice Validates an asset debt cap against its current market principal.
    /// @param asset_ Collateral asset whose cap is being validated.
    /// @param debtCapOhm_ Proposed debt cap, in OHM decimals.
    function validateAssetDebtCap(address asset_, uint128 debtCapOhm_) external view;

    /// @notice Creates a Burner Loans FLOAN market for a collateral asset.
    /// @dev Callable only by OCG admin while Config is enabled.
    /// @param asset_ Collateral asset to configure.
    /// @param debtCapOhm_ Initial market debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk configuration.
    /// @param feeConfig_ Initial utilization fee configuration.
    /// @param withdrawAsShares_ Whether all DepositManager exits return ERC-4626 shares.
    function addAsset(
        address asset_,
        uint128 debtCapOhm_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata riskConfig_,
        IBurnerLoansRisk.AssetFeeConfig calldata feeConfig_,
        bool withdrawAsShares_
    ) external;

    /// @notice Updates a configured asset's debt cap.
    /// @dev Callable only by OCG admin or the config operator while Config is enabled.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New market debt cap, in OHM decimals.
    function setAssetDebtCap(address asset_, uint128 debtCapOhm_) external;

    /// @notice Sets the maximum age of cached prices used by Burner Loans.
    /// @dev Callable only by OCG admin or the configured config operator while Config and Burner
    ///      Loans are enabled. Every `uint48` value is valid.
    /// @param priceCacheMaxAge_ New maximum cached-price age, in seconds.
    function setPriceCacheMaxAge(uint48 priceCacheMaxAge_) external;

    /// @notice Enables or disables new originations for a configured asset.
    /// @dev Callable only by OCG admin or the config operator while Config is enabled.
    ///      Enabling also revalidates PRICE and custody
    ///      dependencies; disabling leaves servicing and yield claims available.
    /// @param asset_ Collateral asset to update.
    /// @param enabled_ Whether originations should be enabled.
    function setAssetOriginationsEnabled(address asset_, bool enabled_) external;

    /// @notice Selects whether future custody exits return vault shares or underlying assets.
    /// @param asset_ Collateral asset to update.
    /// @param withdrawAsShares_ Whether future custody exits return ERC-4626 shares.
    function setAssetWithdrawAsShares(address asset_, bool withdrawAsShares_) external;

    /// @notice Updates a configured asset's risk and term fields.
    /// @dev Callable only by OCG admin or the config operator while Config is enabled. A term or
    ///      horizon update does not rewrite active positions' maturities. Current values
    ///      apply when a new debt episode begins or an active position is extended.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete risk configuration.
    function setAssetRiskConfig(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata config_
    ) external;

    /// @notice Updates a configured asset's utilization fee curve.
    /// @dev Callable only by OCG admin or the config operator while Config is enabled.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee configuration.
    function setAssetFeeConfig(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig calldata config_
    ) external;
}
