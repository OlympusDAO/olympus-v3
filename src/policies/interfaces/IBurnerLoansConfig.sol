// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Config Interface
/// @notice Opinionated administration surface for Burner Loans markets stored in FLOAN.
interface IBurnerLoansConfig is IBurnerLoans {
    /// @notice Thrown when the configured Burner Loans facility is not an active compatible policy.
    /// @param facility_ The invalid facility address.
    error BurnerLoansConfig_InvalidFacility(address facility_);

    /// @notice Returns the OHM debt token configured for new markets.
    /// @return ohm_ OHM token address.
    function ohm() external view returns (address ohm_);

    /// @notice Returns the DepositManager used to validate collateral support.
    /// @return depositManager_ DepositManager address.
    function depositManager() external view returns (address depositManager_);

    /// @notice Returns the Burner Loans facility whose FLOAN markets this policy configures.
    /// @return facility_ Bound Burner Loans facility.
    function facility() external view returns (address facility_);

    /// @notice Returns the policy allowed to execute timelocked configuration changes.
    /// @return configurator_ Configurator policy address.
    function configurator() external view returns (address configurator_);

    /// @notice Returns whether at least one bound FLOAN market exists for a collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return configured True when a matching market exists.
    function isAssetConfigured(address asset_) external view returns (bool configured);

    /// @notice Returns the configuration for a Burner Loans collateral asset.
    /// @dev Reverts when no unique bound market exists or its configuration schema is not Burner Loans.
    /// @param asset_ Collateral asset to query.
    /// @return config Decoded asset configuration.
    function getAssetConfig(address asset_) external view returns (AssetConfig memory config);

    /// @notice Returns the fee configuration for a Burner Loans collateral asset.
    /// @dev Reverts when no unique bound market exists or its configuration schema is not Burner Loans.
    /// @param asset_ Collateral asset to query.
    /// @return config Decoded utilization fee configuration.
    function getAssetFeeConfig(address asset_) external view returns (AssetFeeConfig memory config);

    /// @notice Returns the unique bound FLOAN market identifier for a collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return marketId_ Unique FLOAN market identifier.
    function marketId(address asset_) external view returns (uint32 marketId_);

    /// @notice Validates a complete asset risk configuration against Burner Loans bounds.
    /// @param config_ Risk configuration to validate.
    function validateAssetRiskConfig(AssetRiskConfigInput calldata config_) external pure;

    /// @notice Validates a complete fee curve.
    /// @dev A zero kink is valid only when both slope fields are zero.
    /// @param config_ Fee configuration to validate.
    function validateFeeConfig(AssetFeeConfig calldata config_) external pure;

    /// @notice Validates an asset debt cap against its current market principal.
    /// @param asset_ Collateral asset whose cap is being validated.
    /// @param debtCapOhm_ Proposed debt cap, in OHM decimals.
    function validateAssetDebtCap(address asset_, uint128 debtCapOhm_) external view;

    /// @notice Rotates a FLOAN market to a new active Burner Loans facility.
    /// @param marketId_ FLOAN market identifier.
    /// @param facility_ New facility policy address.
    function setMarketFacility(uint32 marketId_, address facility_) external;

    /// @notice Creates a Burner Loans FLOAN market for a collateral asset.
    /// @param asset_ Collateral asset to configure.
    /// @param debtCapOhm_ Initial market debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk configuration.
    /// @param feeConfig_ Initial utilization fee configuration.
    function addAsset(
        address asset_,
        uint128 debtCapOhm_,
        AssetRiskConfigInput calldata riskConfig_,
        AssetFeeConfig calldata feeConfig_
    ) external;

    /// @notice Updates a configured asset's debt cap.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New market debt cap, in OHM decimals.
    function setAssetDebtCap(address asset_, uint128 debtCapOhm_) external;

    /// @notice Sets the policy allowed to execute timelocked configuration changes.
    /// @param configurator_ New configurator policy address.
    function setConfigurator(address configurator_) external;

    /// @notice Enables or disables new originations for a configured asset.
    /// @param asset_ Collateral asset to update.
    /// @param enabled_ Whether originations should be enabled.
    function setAssetOriginationsEnabled(address asset_, bool enabled_) external;

    /// @notice Updates a configured asset's risk and term fields.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete risk configuration.
    function setAssetRiskConfig(address asset_, AssetRiskConfigInput calldata config_) external;

    /// @notice Updates a configured asset's utilization fee curve.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee configuration.
    function setAssetFeeConfig(address asset_, AssetFeeConfig calldata config_) external;
}
