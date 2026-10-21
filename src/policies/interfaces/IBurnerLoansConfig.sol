// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Config Interface
/// @notice Opinionated administration surface for Burner Loans markets stored in FLOAN.
interface IBurnerLoansConfig {
    /// @notice Changes whether collateral fees flow to the stored distributor.
    /// @dev Admin or selected config operator, while Config is enabled.
    function setSendFeesToDistributor(bool enabled_) external;

    /// @notice Changes whether custody yield flows to the stored distributor.
    /// @dev Admin or selected config operator, while Config is enabled.
    function setSendYieldToDistributor(bool enabled_) external;

    /// @notice Forwards an unreserved token rescue to the facility.
    /// @param token_ Token to rescue.
    /// @param destination_ Rescue recipient.
    function rescue(address token_, address destination_) external;

    /// @notice Redirects an exact amount owed to one payout recipient.
    /// @param token_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Recipient of the rescued tokens.
    /// @param amount_ Exact positive amount, at most pendingPayout(token_, recipient_).
    function rescuePendingPayout(
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external;

    /// @notice The Config policy is not active in its Kernel.
    error BurnerLoansConfig_PolicyInactive();

    /// @notice Thrown when attempting to bind a facility after the initial facility was set.
    error BurnerLoansConfig_FacilityAlreadySet();

    /// @notice Thrown when the configured Burner Loans facility or its linkage is incompatible.
    /// @param facility_ The invalid facility address.
    error BurnerLoansConfig_InvalidFacility(address facility_);

    /// @notice Thrown when the linked Burner Loans Inventory contract is incompatible.
    /// @param inventory_ Invalid Burner Loans Inventory address.
    error BurnerLoansConfig_InvalidInventory(address inventory_);

    /// @notice Thrown when a caller is neither the configured config operator nor an admin.
    /// @param caller_ Unauthorized caller address.
    error BurnerLoansConfig_UnauthorizedConfigOperator(address caller_);

    /// @notice Emitted when this Config is permanently bound to its Burner Loans facility.
    /// @param facility Bound Burner Loans facility.
    event FacilitySet(address indexed facility);

    /// @notice Returns the OHM debt token configured for new markets.
    /// @return ohm_ OHM token address.
    function ohm() external view returns (address ohm_);

    /// @notice Returns the Burner Loans facility whose FLOAN markets this policy configures.
    /// @return facility_ Bound Burner Loans facility.
    function facility() external view returns (address facility_);

    /// @notice Initializes the Burner Loans facility whose FLOAN markets this policy configures.
    /// @dev Callable only once by OCG admin while Burner Loans Config is globally disabled. The
    ///      facility must be an active, compatible policy in this contract's Kernel.
    /// @dev Markets created through this Config store it as manager and `facility_` as facility.
    ///      Config resolves those markets through the facility, collateral, and debt-token tuple.
    ///      Rebinding would change that lookup without updating existing market authorities or the
    ///      DepositManager operator namespace keyed to the old facility. A replacement Burner Loans
    ///      stack must therefore deploy a fresh Config and facility pair.
    ///
    /// @param facility_ Burner Loans facility to bind for this Config's lifetime.
    function setFacility(address facility_) external;

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
    ) external view returns (IBurnerLoans.AssetConfig memory config);

    /// @notice Returns the fee configuration for a Burner Loans collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return config Decoded utilization fee configuration.
    function getAssetFeeConfig(
        address asset_
    ) external view returns (IBurnerLoans.AssetFeeConfig memory config);

    /// @notice Returns the unique bound FLOAN market identifier for a collateral asset.
    /// @param asset_ Collateral asset to query.
    /// @return marketId_ Unique FLOAN market identifier.
    function marketId(address asset_) external view returns (uint32 marketId_);

    /// @notice Validates a complete asset risk configuration against Burner Loans bounds.
    /// @param config_ Risk configuration to validate.
    function validateAssetRiskConfig(
        IBurnerLoans.AssetRiskConfigInput calldata config_
    ) external pure;

    /// @notice Validates a complete fee curve.
    /// @param config_ Fee configuration to validate.
    function validateFeeConfig(IBurnerLoans.AssetFeeConfig calldata config_) external pure;

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
        IBurnerLoans.AssetRiskConfigInput calldata riskConfig_,
        IBurnerLoans.AssetFeeConfig calldata feeConfig_,
        bool withdrawAsShares_
    ) external;

    /// @notice Updates a configured asset's debt cap.
    /// @dev Callable only by OCG admin or the config operator while Config is enabled.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New market debt cap, in OHM decimals.
    function setAssetDebtCap(address asset_, uint128 debtCapOhm_) external;

    /// @notice Updates the maximum active principal across the bound Burner Loans facility.
    /// @dev Restricted to OCG admin while Config is enabled and forwarded to Burner Loans' current
    ///      Inventory.
    /// @param debtCapOhm_ New facility-wide principal cap, in OHM decimals.
    function setGlobalDebtCap(uint128 debtCapOhm_) external;

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
        IBurnerLoans.AssetRiskConfigInput calldata config_
    ) external;

    /// @notice Updates a configured asset's utilization fee curve.
    /// @dev Callable only by OCG admin or the config operator while Config is enabled.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee configuration.
    function setAssetFeeConfig(
        address asset_,
        IBurnerLoans.AssetFeeConfig calldata config_
    ) external;
}
