// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Config
/// @notice Opinionated configuration policy for Burner Loans markets stored in FLOAN.
contract BurnerLoansConfig is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    IBurnerLoansConfig,
    IVersioned
{
    // ========== CONSTANTS ========== //

    uint256 internal constant _BPS = BurnerLoansConstants.MAX_BPS;
    uint256 internal constant _WAD = 1e18;
    uint8 internal constant _MAX_TOKEN_DECIMALS = 36;

    // ========== DEPENDENCIES ========== //

    IERC20 internal immutable _OHM;
    IBurnerLoansLifecycle internal _FACILITY;

    // ========== MODULES ========== //

    IFLOANv1 internal _FLOAN;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys an unlinked Burner Loans configuration policy.
    /// @dev The facility is linked once after deployment through `setFacility`, which requires
    ///      active membership in this policy's Kernel.
    /// @param kernel_ Kernel that manages this policy and its module dependencies.
    /// @param ohm_ Debt token used by markets created through this policy.
    constructor(
        Kernel kernel_,
        IERC20 ohm_
    ) Policy(kernel_) ReEnablerGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD) {
        if (address(ohm_) == address(0)) revert BurnerLoans_ZeroAddress();
        _OHM = ohm_;
    }

    // ========== KERNEL FUNCTIONS ========== //

    /// @inheritdoc Policy
    /// @dev Reverts when FLOAN or ROLES is missing or uses an unsupported version.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("FLOAN");
        dependencies[1] = toKeycode("ROLES");

        _FLOAN = IFLOANv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 floanMajor, ) = Module(address(_FLOAN)).VERSION();
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (floanMajor != 1 || rolesMajor != 1) {
            revert BurnerLoans_InvalidModuleVersion();
        }
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode floan = toKeycode("FLOAN");
        requests = new Permissions[](6);
        requests[0] = Permissions({keycode: floan, funcSelector: IFLOANv1.createMarket.selector});
        requests[1] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketOriginationsEnabled.selector
        });
        requests[2] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketPrincipalCap.selector
        });
        requests[3] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketRiskConfig.selector
        });
        requests[4] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketBaseFee.selector
        });
        requests[5] = Permissions({
            keycode: floan,
            funcSelector: IFLOANv1.setMarketConfigData.selector
        });
    }

    /// @inheritdoc IBurnerLoansConfig
    function setFacility(address facility_) external givenDisabled onlyAdminRole {
        if (address(_FACILITY) != address(0)) revert BurnerLoansConfig_FacilityAlreadySet();
        _requireFacilityActive(facility_);
        _validateFacilityCompatibility(IBurnerLoansLifecycle(facility_));
        _FACILITY = IBurnerLoansLifecycle(facility_);
        emit FacilitySet(facility_);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansConfig
    function ohm() external view returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoansConfig
    function facility() external view returns (address) {
        return address(_FACILITY);
    }

    /// @inheritdoc IBurnerLoansConfig
    function inventory() external view returns (address) {
        return IBurnerLoansView(address(_FACILITY)).inventory();
    }

    /// @inheritdoc IBurnerLoansConfig
    function isAssetConfigured(address asset_) external view returns (bool) {
        return _isAssetConfigured(asset_);
    }

    /// @inheritdoc IBurnerLoansConfig
    function marketId(address asset_) external view returns (uint32) {
        return _marketId(asset_);
    }

    /// @inheritdoc IBurnerLoansConfig
    function getAssetConfig(address asset_) external view returns (AssetConfig memory) {
        return _getAssetConfig(_marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansConfig
    function getAssetFeeConfig(address asset_) external view returns (AssetFeeConfig memory) {
        return _getAssetFeeConfig(_marketId(asset_));
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance. Validates PRICE approval,
    ///      DepositManager support, ERC20 decimal scale, and risk bounds.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not have the admin role.
    ///      - `asset_` is zero.
    ///      - `asset_` is OHM.
    ///      - `asset_` is already configured.
    ///      - The asset's ERC20 decimals exceed the supported maximum.
    ///      - Risk, bps, maturity, or fee parameters violate configured bounds.
    ///      - PRICE does not approve the asset or returns a zero price.
    ///      - DepositManager does not configure the asset or BurnerLoans deposit period.
    ///      - DepositManager has not enabled the deposit period.
    /// @dev This function does not attempt a token transfer and therefore cannot detect conditional
    ///      or fee-on-transfer behavior. Governance must admit only exact-transfer collateral;
    ///      DepositManager enforces exact receipt when the asset first enters custody.
    /// @param asset_ Collateral asset to add.
    /// @param debtCapOhm_ Initial active debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk and term configuration.
    /// @param feeConfig_ Initial utilization fee curve.
    function addAsset(
        address asset_,
        uint128 debtCapOhm_,
        AssetRiskConfigInput calldata riskConfig_,
        AssetFeeConfig calldata feeConfig_
    ) external givenEnabled onlyAdminRole {
        if (_isAssetConfigured(asset_)) {
            revert BurnerLoans_AssetAlreadyConfigured(asset_);
        }
        AssetConfig memory assetConfig = _validateAndBuildAssetConfig(
            asset_,
            debtCapOhm_,
            riskConfig_
        );
        _validateFeeConfig(feeConfig_);

        _FLOAN.createMarket(
            IFLOANv1.MarketInput({
                collateralToken: asset_,
                debtToken: address(_OHM),
                manager: address(this),
                facility: address(_FACILITY),
                configId: BurnerLoansMarketConfig.CONFIG_ID,
                principalCap: debtCapOhm_,
                termLength: riskConfig_.termLength,
                maxMaturityHorizon: riskConfig_.maxMaturityHorizon,
                collateralFactorBps: riskConfig_.collateralFactorBps,
                minCollateralRatioBps: riskConfig_.minCollateralRatioBps,
                baseFeeBps: feeConfig_.baseFeeBps
            }),
            BurnerLoansMarketConfig.encode(assetConfig, feeConfig_)
        );

        emit AssetAdded(asset_, assetConfig);
        emit AssetFeeConfigSet(asset_, feeConfig_);
        emit AssetOriginationsSet(asset_, true);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Callable by admin or the config operator. Direct admin calls are effectively
    ///      timelocked by governance in the expected deployment.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither admin nor the config operator.
    ///      - `asset_` is not configured.
    ///      - `debtCapOhm_` is below current active debt for `asset_`.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New asset cap, in OHM decimals.
    function setAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) external givenEnabled onlyConfigOperatorOrAdmin {
        uint32 marketId_ = _validateAssetDebtCap(asset_, debtCapOhm_);

        _FLOAN.setMarketPrincipalCap(marketId_, debtCapOhm_);
        emit AssetDebtCapSet(asset_, debtCapOhm_);
    }

    /// @inheritdoc IBurnerLoansConfig
    function setGlobalDebtCap(uint128 debtCapOhm_) external givenEnabled onlyAdminRole {
        _inventory().setGlobalDebtCap(debtCapOhm_);
    }

    /// @dev Returns the Burner Loans Inventory contract currently bound by Burner Loans.
    function _inventory() internal view returns (IBurnerLoansInventory) {
        address inventory_ = IBurnerLoansView(address(_FACILITY)).inventory();
        if (inventory_ == address(0)) revert BurnerLoansConfig_InvalidInventory(inventory_);
        return IBurnerLoansInventory(inventory_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Callable directly by admin or by the configured config operator. In the expected
    ///      deployment, direct admin calls are already timelocked by OCG governance, while the
    ///      config operator is ConfigTimelock, through which burner_loans_admin callers queue the
    ///      transition.
    ///      Enabling revalidates PRICE and DepositManager dependencies. Disabling does not block
    ///      repayment, withdrawal, seizure, harvest, or safe cleanup while Burner Loans remains
    ///      globally enabled. Setting the current value performs no writes and emits no events.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither admin nor the configured config operator.
    ///      - `asset_` is not configured.
    ///      - When enabling, PRICE does not approve the asset or returns a zero price.
    ///      - When enabling, DepositManager does not configure and enable the asset period.
    /// @param asset_ Collateral asset to update.
    /// @param enabled_ Whether deposits, borrowing, and maturity extensions are enabled.
    function setAssetOriginationsEnabled(
        address asset_,
        bool enabled_
    ) external givenEnabled onlyConfigOperatorOrAdmin {
        (uint32 marketId_, AssetConfig memory currentConfig) = _requireAssetConfigured(asset_);
        if (currentConfig.originationsEnabled == enabled_) return;
        if (enabled_) _validateAssetDependencies(asset_);

        _FLOAN.setMarketOriginationsEnabled(marketId_, enabled_);
        emit AssetOriginationsSet(asset_, enabled_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Callable by admin or the config operator. The Burner Loans Config Timelock
    ///      may expose partial-update helpers, but this setter receives the full resulting curve.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither admin nor the config operator.
    ///      - `asset_` is not configured.
    ///      - Any fee component exceeds 100%.
    ///      - `kinkBps` is at or above 100%.
    ///      - `kinkBps` is zero while either slope is non-zero.
    ///      - The full-utilization fee rate exceeds 100%.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee curve.
    function setAssetFeeConfig(
        address asset_,
        AssetFeeConfig calldata config_
    ) external givenEnabled onlyConfigOperatorOrAdmin {
        _setAssetFeeConfig(asset_, config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Callable by admin or the config operator. Replaces all risk and term fields
    ///      while preserving admin-only fields such as enabled status, collateral decimals, and debt cap.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither admin nor the config operator.
    ///      - `asset_` is not configured.
    ///      - Collateral factor is zero or above 100%.
    ///      - Minimum collateral ratio is outside protocol bounds.
    ///      - Backing multiplier is outside protocol bounds.
    ///      - Keeper reward bps is above 100%.
    ///      - `termLength` is zero, above the protocol maximum, or not below `maxMaturityHorizon`.
    ///      - `maxMaturityHorizon` is above the protocol maximum.
    ///      - `maxKeeperReward` is above the protocol maximum.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete risk and term configuration.
    function setAssetRiskConfig(
        address asset_,
        AssetRiskConfigInput calldata config_
    ) external givenEnabled onlyConfigOperatorOrAdmin {
        _setAssetRiskConfig(asset_, config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if collateral factor, minimum collateral ratio, backing multiplier, keeper
    ///      reward bps, term length, max maturity horizon, or max keeper reward violates
    ///      BurnerLoans bounds.
    /// @param config_ Complete asset configuration to validate.
    function validateAssetRiskConfig(AssetRiskConfigInput calldata config_) external pure {
        _validateRiskConfig(config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if any bps component exceeds 100%, if kink configuration is invalid, or if
    ///      the full-utilization fee rate exceeds 100%.
    /// @param config_ Complete fee configuration to validate.
    function validateFeeConfig(AssetFeeConfig calldata config_) external pure {
        _validateFeeConfig(config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if `asset_` is not configured, `debtCapOhm_` is below current active
    ///      debt for `asset_`.
    /// @param asset_ Collateral asset to validate.
    /// @param debtCapOhm_ Proposed asset active debt cap, in OHM decimals.
    function validateAssetDebtCap(address asset_, uint128 debtCapOhm_) external view {
        _validateAssetDebtCap(asset_, debtCapOhm_);
    }

    // ========== CONFIGURATION HELPERS ========== //

    /// @notice Restricts a function to the configured config operator or admin.
    /// @dev Reverts with `BurnerLoansConfig_UnauthorizedConfigOperator` when the caller is neither
    ///      `configOperator` nor an admin.
    modifier onlyConfigOperatorOrAdmin() {
        _onlyConfigOperatorOrAdmin();
        _;
    }

    /// @notice Reverts unless the caller has admin or burner_loans_admin authority.
    /// @dev Reverts with `NotAuthorised` when the caller lacks both roles.
    function _onlyBurnerLoansAdminOrAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Reverts unless the caller is the configured config operator or admin.
    /// @dev Reverts with `BurnerLoansConfig_UnauthorizedConfigOperator` and the caller address
    ///      when the caller is neither `configOperator` nor an admin.
    function _onlyConfigOperatorOrAdmin() internal view {
        if (!_isConfigOperator(msg.sender) && !_isAdmin(msg.sender)) {
            revert BurnerLoansConfig_UnauthorizedConfigOperator(msg.sender);
        }
    }

    /// @inheritdoc ConfigOperatorSingleStep
    /// @dev Preserves the existing enabled-state check before admin-role authorization.
    function _authorizeSetConfigOperator() internal view override returns (bool authorized) {
        _requireEnabled();
        _requireRole(msg.sender, ADMIN_ROLE);
        return true;
    }

    /// @notice Validates the interface and token compatibility of a Burner Loans facility.
    ///      Reverts with `BurnerLoansConfig_InvalidFacility` when validation fails.
    /// @param facility_ Facility policy to validate.
    function _validateFacilityCompatibility(IBurnerLoansLifecycle facility_) internal view {
        bytes4[] memory interfaceIds = new bytes4[](2);
        interfaceIds[0] = type(IBurnerLoansLifecycle).interfaceId;
        interfaceIds[1] = type(IBurnerLoansView).interfaceId;
        if (
            !ERC165Checker.supportsAllInterfaces(address(facility_), interfaceIds) ||
            IBurnerLoansView(address(facility_)).ohm() != address(_OHM)
        ) {
            revert BurnerLoansConfig_InvalidFacility(address(facility_));
        }
    }

    /// @dev Reverts unless `facility_` is active in and reports this Kernel.
    function _requireFacilityActive(address facility_) internal view {
        if (!kernel.isPolicyActive(Policy(facility_)) || !_reportsKernel(facility_)) {
            revert BurnerLoansConfig_InvalidFacility(facility_);
        }
    }

    /// @dev Returns whether `policy_` reports this policy's Kernel.
    function _reportsKernel(address policy_) internal view returns (bool) {
        try Policy(policy_).kernel() returns (Kernel reportedKernel) {
            return address(reportedKernel) == address(kernel);
        } catch {
            return false;
        }
    }

    /// @notice Validates the complete Burner Loans Config relationship before activation.
    /// @dev Requires active Kernel membership and matching reverse links. Burner Loans Inventory
    ///      may be globally disabled because Config does not depend on its operational state.
    function _validateConfiguration() internal view {
        IBurnerLoansLifecycle facility_ = _FACILITY;
        address facilityAddress = address(facility_);
        _requireFacilityActive(facilityAddress);
        _validateFacilityCompatibility(facility_);
        IBurnerLoansView facilityView = IBurnerLoansView(facilityAddress);
        if (facilityView.configurator() != address(this)) {
            revert BurnerLoansConfig_InvalidFacility(facilityAddress);
        }

        address inventory_ = facilityView.inventory();
        if (
            inventory_ == address(0) ||
            !kernel.isPolicyActive(Policy(inventory_)) ||
            !_reportsKernel(inventory_) ||
            !ERC165Checker.supportsInterface(inventory_, type(IBurnerLoansInventory).interfaceId)
        ) revert BurnerLoansConfig_InvalidInventory(inventory_);
        IBurnerLoansInventory inventoryPolicy = IBurnerLoansInventory(inventory_);
        if (
            inventoryPolicy.ohm() != address(_OHM) ||
            inventoryPolicy.facility() != facilityAddress ||
            inventoryPolicy.configurator() != address(this)
        ) revert BurnerLoansConfig_InvalidInventory(inventory_);
    }

    /// @notice Authorizes a global re-enable transition.
    /// @dev Reverts with `NotAuthorised` unless the caller has admin or burner_loans_admin
    ///      authority.
    function _authorizeReEnable() internal view override {
        _onlyBurnerLoansAdminOrAdmin();
    }

    /// @notice Authorizes a grace-period update.
    /// @dev Reverts with `ROLESv1.ROLES_RequireRole(ADMIN_ROLE)` when the caller lacks the
    ///      admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Validates complete reverse links before enabling Burner Loans Config.
    function _beforeEnable(bytes calldata) internal view override {
        _validateConfiguration();
    }

    /// @dev Preserves the grace-period gate and revalidates links before re-enabling.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateConfiguration();
    }

    /// @notice Resolves and decodes the unique Burner Loans market for a collateral asset.
    /// @dev Reverts with `BurnerLoans_AssetNotConfigured` when no bound market exists, or
    ///      `BurnerLoans_AmbiguousMarket` when multiple bound markets exist for the pair.
    ///      Reverts with `BurnerLoans_IncompatibleMarketConfig` when the resolved market uses a
    ///      different schema, or `BurnerLoans_InvalidMarketConfigData` when its data length is
    ///      invalid.
    /// @param asset_ Collateral asset to look up.
    /// @return marketId_ FLOAN market identifier for the configured asset.
    /// @return config Decoded asset configuration.
    function _requireAssetConfigured(
        address asset_
    ) internal view returns (uint32 marketId_, AssetConfig memory config) {
        marketId_ = _marketId(asset_);
        config = _getAssetConfig(marketId_);
    }

    /// @notice Validates and stores the complete asset fee curve.
    /// @dev Reverts if `asset_` is not configured or if `config_` violates fee bounds.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete utilization fee curve.
    function _setAssetFeeConfig(address asset_, AssetFeeConfig memory config_) internal {
        uint32 marketId_ = _marketId(asset_);
        _validateFeeConfig(config_);
        BurnerLoansMarketConfig.Data memory marketData = _getMarketData(marketId_);
        marketData.kinkBps = config_.kinkBps;
        marketData.preKinkSlopeBps = config_.preKinkSlopeBps;
        marketData.postKinkSlopeBps = config_.postKinkSlopeBps;
        _FLOAN.setMarketBaseFee(marketId_, config_.baseFeeBps);
        _FLOAN.setMarketConfigData(marketId_, abi.encode(marketData));
        emit AssetFeeConfigSet(asset_, config_);
    }

    /// @notice Validates and stores risk and term fields while preserving admin-only fields.
    /// @dev Reverts if `asset_` is not configured or if `riskConfig_` violates risk, maturity,
    ///      or keeper reward bounds.
    /// @param asset_ Collateral asset to update.
    /// @param riskConfig_ Complete risk and term configuration.
    function _setAssetRiskConfig(address asset_, AssetRiskConfigInput memory riskConfig_) internal {
        _validateRiskConfig(riskConfig_);
        uint32 marketId_ = _marketId(asset_);
        BurnerLoansMarketConfig.Data memory marketData = _getMarketData(marketId_);
        marketData.backingMultiplierBps = riskConfig_.backingMultiplierBps;
        marketData.keeperRewardBps = riskConfig_.keeperRewardBps;
        marketData.maxKeeperReward = _toUint128(riskConfig_.maxKeeperReward);
        _FLOAN.setMarketRiskConfig(
            marketId_,
            riskConfig_.termLength,
            riskConfig_.maxMaturityHorizon,
            riskConfig_.collateralFactorBps,
            riskConfig_.minCollateralRatioBps
        );
        _FLOAN.setMarketConfigData(marketId_, abi.encode(marketData));
        emit AssetRiskConfigSet(asset_, riskConfig_);
    }

    /// @notice Builds the initial stored configuration for a new collateral asset.
    /// @dev Reads collateral decimals from the ERC20, sets the asset enabled, and validates the
    ///      risk config, PRICE support, and DepositManager support.
    /// @dev Reverts if:
    ///      - `asset_` is zero.
    ///      - `asset_` is OHM.
    ///      - The asset's ERC20 decimals exceed the supported maximum.
    ///      - `riskConfig_` violates risk, maturity, or keeper reward bounds.
    ///      - PRICE does not approve the asset or returns a zero price.
    ///      - DepositManager has not configured and enabled the Burner Loans deposit period.
    /// @param asset_ Collateral asset to add.
    /// @param debtCapOhm_ Initial asset active debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk and term configuration.
    /// @return assetConfig Initial stored configuration for `asset_`.
    function _validateAndBuildAssetConfig(
        address asset_,
        uint128 debtCapOhm_,
        AssetRiskConfigInput memory riskConfig_
    ) internal view returns (AssetConfig memory assetConfig) {
        if (asset_ == address(0)) revert BurnerLoans_ZeroAddress();
        if (asset_ == address(_OHM)) revert BurnerLoans_InvalidCollateralAsset(asset_);

        uint8 actualDecimals = IERC20(asset_).decimals();
        _validateTokenDecimals(actualDecimals);

        assetConfig = AssetConfig({
            originationsEnabled: true,
            collateralDecimals: actualDecimals,
            collateralFactorBps: riskConfig_.collateralFactorBps,
            minCollateralRatioBps: riskConfig_.minCollateralRatioBps,
            backingMultiplierBps: riskConfig_.backingMultiplierBps,
            keeperRewardBps: riskConfig_.keeperRewardBps,
            termLength: riskConfig_.termLength,
            maxMaturityHorizon: riskConfig_.maxMaturityHorizon,
            debtCap: debtCapOhm_,
            maxKeeperReward: riskConfig_.maxKeeperReward
        });

        _validateRiskConfig(riskConfig_);
        _validateAssetDependencies(asset_);
    }

    /// @notice Validates a risk-config input.
    /// @dev Reverts if collateral factor, minimum collateral ratio, backing multiplier, keeper
    ///      reward bps, term length, max maturity horizon, or max keeper reward violates
    ///      Burner Loans bounds.
    /// @param config_ Complete risk and term input to validate.
    function _validateRiskConfig(AssetRiskConfigInput memory config_) internal pure {
        _validateCollateralFactorBps(config_.collateralFactorBps);
        _validateMinCollateralRatioBps(config_.minCollateralRatioBps);
        _validateBackingMultiplierBps(config_.backingMultiplierBps);
        _validateBps(config_.keeperRewardBps);
        _validateMaturityConfig(config_.termLength, config_.maxMaturityHorizon);
        _validateMaxKeeperReward(config_.maxKeeperReward);
    }

    /// @notice Validates an asset collateral factor.
    /// @dev Reverts with `BurnerLoans_InvalidBps` if the factor is zero or exceeds the maximum
    ///      collateral factor.
    /// @param collateralFactorBps_ Collateral factor, in basis points.
    function _validateCollateralFactorBps(uint16 collateralFactorBps_) internal pure {
        if (
            collateralFactorBps_ == 0 ||
            collateralFactorBps_ > BurnerLoansConstants.MAX_COLLATERAL_FACTOR_BPS
        ) {
            revert BurnerLoans_InvalidBps(collateralFactorBps_);
        }
    }

    /// @notice Validates a minimum collateral ratio.
    /// @dev Reverts with `BurnerLoans_InvalidParam` if the ratio is below 100% or above the
    ///      maximum collateral ratio.
    /// @param minCollateralRatioBps_ Minimum collateral ratio, in basis points.
    function _validateMinCollateralRatioBps(uint16 minCollateralRatioBps_) internal pure {
        if (
            minCollateralRatioBps_ < _BPS ||
            minCollateralRatioBps_ > BurnerLoansConstants.MAX_COLLATERAL_RATIO_BPS
        ) {
            revert BurnerLoans_InvalidParam();
        }
    }

    /// @notice Validates a required backing multiplier.
    /// @dev Reverts with `BurnerLoans_InvalidParam` if the multiplier is below 100% or above the
    ///      maximum backing multiplier.
    /// @param backingMultiplierBps_ Backing multiplier, in basis points.
    function _validateBackingMultiplierBps(uint16 backingMultiplierBps_) internal pure {
        if (
            backingMultiplierBps_ < _BPS ||
            backingMultiplierBps_ > BurnerLoansConstants.MAX_BACKING_MULTIPLIER_BPS
        ) {
            revert BurnerLoans_InvalidParam();
        }
    }

    /// @notice Validates the fixed term and maximum maturity horizon.
    /// @dev Reverts with `BurnerLoans_InvalidParam` if the term is zero, exceeds the maximum
    ///      term length, is not below the horizon, or if the horizon exceeds its maximum.
    /// @param termLength_ Fixed extension term length, in seconds.
    /// @param maxMaturityHorizon_ Maximum maturity horizon, in seconds.
    function _validateMaturityConfig(uint48 termLength_, uint48 maxMaturityHorizon_) internal pure {
        if (
            termLength_ == 0 ||
            termLength_ > BurnerLoansConstants.MAX_TERM_LENGTH ||
            maxMaturityHorizon_ <= termLength_ ||
            maxMaturityHorizon_ > BurnerLoansConstants.MAX_MATURITY_HORIZON
        ) revert BurnerLoans_InvalidParam();
    }

    /// @notice Validates a complete utilization fee curve.
    /// @dev Reverts if any bps component exceeds 100%, if kink configuration is invalid, or if
    ///      the full-utilization fee rate exceeds the protocol fee cap.
    /// @param config_ Complete fee curve to validate.
    function _validateFeeConfig(AssetFeeConfig memory config_) internal pure {
        _validateBps(config_.baseFeeBps);
        _validateBps(config_.preKinkSlopeBps);
        _validateBps(config_.postKinkSlopeBps);
        if (config_.kinkBps == 0) {
            if (config_.preKinkSlopeBps != 0 || config_.postKinkSlopeBps != 0) {
                revert BurnerLoans_InvalidFeeConfig();
            }
        } else {
            if (config_.kinkBps >= _BPS) {
                revert BurnerLoans_InvalidFeeConfig();
            }
        }
        if (_feeRateWad(config_) > uint256(BurnerLoansConstants.FEE_CAP_BPS) * (_WAD / _BPS)) {
            revert BurnerLoans_InvalidFeeConfig();
        }
    }

    /// @notice Validates that a proposed cap is not below current active debt.
    /// @dev Reverts with `BurnerLoans_InvalidCap` if `cap_` is below `activeDebtOhm_`.
    /// @param cap_ Proposed cap, in OHM decimals.
    /// @param activeDebtOhm_ Current active debt to preserve, in OHM decimals.
    function _validateDebtCap(uint256 cap_, uint256 activeDebtOhm_) internal pure {
        if (cap_ < activeDebtOhm_) revert BurnerLoans_InvalidCap();
    }

    /// @notice Validates an asset active debt cap against live Burner Loans state.
    /// @dev Reverts with `BurnerLoans_AssetNotConfigured` if `asset_` is not configured.
    ///      Reverts with `BurnerLoans_InvalidCap` if `debtCapOhm_` is below current active
    ///      debt for `asset_`.
    /// @param asset_ Collateral asset to validate.
    /// @param debtCapOhm_ Proposed asset active debt cap, in OHM decimals.
    /// @return marketId_ Validated FLOAN market identifier for `asset_`.
    function _validateAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) internal view returns (uint32 marketId_) {
        marketId_ = _marketId(asset_);
        BurnerLoansMarketConfig.requireCompatibleConfig(marketId_, _FLOAN.getMarket(marketId_));
        _validateDebtCap(debtCapOhm_, _FLOAN.getMarketPrincipalDue(marketId_));
    }

    /// @notice Returns whether the bound facility has at least one market for an asset and OHM.
    /// @param asset_ Collateral asset to query.
    /// @return configured True when at least one matching FLOAN market exists.
    function _isAssetConfigured(address asset_) internal view returns (bool) {
        return BurnerLoansMarketConfig.hasMarket(_FLOAN, address(_FACILITY), asset_, address(_OHM));
    }

    /// @notice Resolves the unique FLOAN market for a collateral asset and OHM.
    /// @dev Reverts with `BurnerLoans_AssetNotConfigured` when no matching market exists and
    ///      `BurnerLoans_AmbiguousMarket` when more than one matching market exists.
    /// @param asset_ Collateral asset to resolve.
    /// @return marketId_ Unique matching FLOAN market identifier.
    function _marketId(address asset_) internal view returns (uint32 marketId_) {
        return BurnerLoansMarketConfig.marketId(_FLOAN, address(_FACILITY), asset_, address(_OHM));
    }

    /// @notice Decodes the Burner Loans asset configuration stored by a FLOAN market.
    /// @dev Reverts with `FLOAN_InvalidMarket` when `marketId_` does not exist and
    ///      validates the configuration schema and encoded data length before decoding.
    /// @param marketId_ FLOAN market identifier to read.
    /// @return config Decoded Burner Loans asset configuration.
    function _getAssetConfig(uint32 marketId_) internal view returns (AssetConfig memory config) {
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        return
            BurnerLoansMarketConfig.assetConfig(
                marketId_,
                market,
                _FLOAN.getMarketConfigData(marketId_)
            );
    }

    /// @notice Decodes the Burner Loans fee configuration stored by a FLOAN market.
    /// @dev Reverts with `FLOAN_InvalidMarket` when `marketId_` does not exist and
    ///      validates the configuration schema and encoded data length before decoding.
    /// @param marketId_ FLOAN market identifier to read.
    /// @return config Decoded Burner Loans fee configuration.
    function _getAssetFeeConfig(uint32 marketId_) internal view returns (AssetFeeConfig memory) {
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        return
            BurnerLoansMarketConfig.feeConfig(
                marketId_,
                market,
                _FLOAN.getMarketConfigData(marketId_)
            );
    }

    /// @notice Decodes the Burner Loans-specific data stored by a FLOAN market.
    /// @dev Reverts with `FLOAN_InvalidMarket` when `marketId_` does not exist and
    ///      validates the configuration schema and encoded data length before decoding.
    /// @param marketId_ FLOAN market identifier to read.
    /// @return data Decoded Burner Loans market data.
    function _getMarketData(
        uint32 marketId_
    ) internal view returns (BurnerLoansMarketConfig.Data memory) {
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        return
            BurnerLoansMarketConfig.decode(
                marketId_,
                market,
                _FLOAN.getMarketConfigData(marketId_)
            );
    }

    /// @notice Converts a value to the storage width used by FLOAN market configuration.
    /// @dev Reverts with `BurnerLoans_InvalidCap` when `value_` exceeds `uint128`.
    /// @param value_ Value to convert.
    /// @return result Value represented as `uint128`.
    function _toUint128(uint256 value_) internal pure returns (uint128 result) {
        result = uint128(value_);
        if (result != value_) revert BurnerLoans_InvalidCap();
    }

    /// @notice Validates the maximum keeper reward amount.
    /// @dev Reverts with `BurnerLoans_InvalidParam` if the reward exceeds the protocol maximum.
    /// @param maxKeeperReward_ Maximum keeper reward, in collateral token decimals.
    function _validateMaxKeeperReward(uint256 maxKeeperReward_) internal pure {
        if (maxKeeperReward_ > BurnerLoansConstants.MAX_KEEPER_REWARD) {
            revert BurnerLoans_InvalidParam();
        }
    }

    /// @notice Asks Burner Loans to validate its PRICE and custody dependencies for an asset.
    /// @dev Keeping dependency validation on Burner Loans prevents this configuration policy from
    ///      carrying a second, independently configured PRICE or Deposit Manager reference.
    /// @param asset_ Collateral asset to validate.
    function _validateAssetDependencies(address asset_) internal view {
        IBurnerLoansView(address(_FACILITY)).validateAssetDependencies(asset_);
    }

    /// @notice Validates token-native decimals used for ERC20 balances.
    /// @dev Input: token decimals. Output: none. Reverts above the configured safe token scale.
    /// @param decimals_ Token decimals reported by the ERC20.
    function _validateTokenDecimals(uint8 decimals_) internal pure {
        if (decimals_ > _MAX_TOKEN_DECIMALS) revert BurnerLoans_InvalidDecimals(decimals_);
    }

    /// @notice Reverts if a bps value exceeds 100%.
    /// @dev Reverts with `BurnerLoans_InvalidBps` when `bps_` is greater than 10,000.
    /// @param bps_ Basis-point value to validate.
    function _validateBps(uint256 bps_) internal pure {
        if (bps_ > BurnerLoansConstants.MAX_BPS) revert BurnerLoans_InvalidBps(bps_);
    }

    /// @notice Computes the full-utilization fee rate for validation.
    /// @dev The Burner Loans curve stores segment deltas, so the maximum rate is the base fee
    ///      plus both slopes.
    /// @param feeConfig_ Fee curve to evaluate.
    /// @return feeRateWad WAD-scaled fee rate.
    function _feeRateWad(
        AssetFeeConfig memory feeConfig_
    ) internal pure returns (uint256 feeRateWad) {
        return
            uint256(
                feeConfig_.baseFeeBps + feeConfig_.preKinkSlopeBps + feeConfig_.postKinkSlopeBps
            ) * (_WAD / _BPS);
    }

    // ========== VERSION ========== //

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ERC165 ========== //

    /// @notice ERC165 interface support.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansConfig).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
