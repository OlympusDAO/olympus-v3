// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Config Interface
/// @notice Opinionated administration surface for Burner Loans markets stored in FLOAN.
interface IBurnerLoansConfig is IBurnerLoans {
    /// @notice Thrown when the configured Burner Loans facility or its linkage is incompatible.
    /// @param facility_ The invalid facility address.
    error BurnerLoansConfig_InvalidFacility(address facility_);
    /// @notice Thrown when the linked Burner Loans Inventory contract is incompatible.
    error BurnerLoansConfig_InvalidInventory(address inventory_);
    /// @notice Thrown when a caller is neither the configured config operator nor an admin.
    /// @param caller_ Unauthorized caller address.
    error BurnerLoansConfig_UnauthorizedConfigOperator(address caller_);

    event FacilitySet(address indexed facility);
    event ConfigOperatorSet(address indexed configOperator);

    /// @notice Returns the OHM debt token configured for new markets.
    /// @return ohm_ OHM token address.
    function ohm() external view returns (address ohm_);

    /// @notice Returns the Burner Loans facility whose FLOAN markets this policy configures.
    /// @return facility_ Bound Burner Loans facility.
    function facility() external view returns (address facility_);

    /// @notice Sets the Burner Loans facility whose FLOAN markets this policy configures.
    /// @dev Callable only by OCG admin while Burner Loans Config is globally disabled. The
    ///      facility must be an active policy in this contract's Kernel.
    function setFacility(address facility_) external;

    /// @notice Returns Burner Loans' current Burner Loans Inventory contract.
    /// @return inventory_ Current Burner Loans Inventory resolved through the bound facility.
    function inventory() external view returns (address inventory_);

    /// @notice Returns the optional address allowed to execute delegated configuration changes.
    /// @return configOperator_ Config operator address, or zero when delegated access is revoked.
    function configOperator() external view returns (address configOperator_);

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

    /// @notice Updates the maximum active principal across the bound Burner Loans facility.
    /// @dev Restricted to OCG admin and forwarded to Burner Loans' current Burner Loans Inventory.
    function setGlobalDebtCap(uint128 debtCapOhm_) external;

    /// @notice Sets the optional address allowed to execute delegated configuration changes.
    /// @dev The config operator need not be a policy or implement a timelock. Setting zero revokes
    ///      delegated access.
    /// @param configOperator_ New config operator address.
    function setConfigOperator(address configOperator_) external;

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
