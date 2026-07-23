// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Policy} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Burner Loans Config
/// @notice Shared storage, configuration, and timelock administration for Burner Loans.
abstract contract BurnerLoansConfig is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IBurnerLoans,
    IVersioned
{
    // ========== CONSTANTS ========== //

    uint256 internal constant _BPS = BurnerLoansConstants.MAX_BPS;
    uint256 internal constant _WAD = 1e18;
    uint8 internal constant _MAX_TOKEN_DECIMALS = 36;

    // ========== IMMUTABLES ========== //

    IERC20 internal immutable _OHM;
    uint8 internal immutable _OHM_DECIMALS;
    IDepositManager internal immutable _DEPOSIT_MANAGER;

    // ========== MODULES ========== //

    MINTRv1 internal _MINTR;
    IPRICEv2 internal _PRICE;
    TRSRYv1 internal _TRSRY;

    // ========== STATE ========== //

    uint256 public override globalDebtCapOhm;
    uint256 public override totalActiveDebtOhm;
    address public override configurator;
    address public override backingOracle;

    mapping(address asset => uint256 debtOhm) public override assetActiveDebtOhm;
    mapping(address asset => uint48 disabledAt) public override assetDisabledAt;
    mapping(address asset => bool configured) public override isAssetConfigured;
    mapping(address asset => AssetConfig config) internal _assetConfigs;
    mapping(address asset => AssetFeeConfig config) internal _assetFeeConfigs;
    mapping(address owner => mapping(address asset => Position position)) internal _positions;
    mapping(address asset => EnumerableSet.AddressSet borrowers) internal _activeBorrowersByAsset;
    address[] internal _configuredAssets;

    // ========== CONSTRUCTOR ========== //

    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) Policy(kernel_) ReEnablerGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD) {
        if (address(ohm_) == address(0) || address(depositManager_) == address(0)) {
            revert BurnerLoans_ZeroAddress();
        }
        if (
            !ERC165Checker.supportsInterface(
                address(depositManager_),
                type(IDepositManager).interfaceId
            )
        ) {
            revert BurnerLoans_InvalidDepositManager(address(depositManager_));
        }

        _OHM = ohm_;
        _OHM_DECIMALS = ohm_.decimals();
        _DEPOSIT_MANAGER = depositManager_;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Sets the oracle supplying canonical OHM backing.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not have the admin role.
    ///      - `backingOracle_` is zero.
    /// @param backingOracle_ New backing oracle address.
    function setBackingOracle(address backingOracle_) external givenEnabled onlyAdminRole {
        if (backingOracle_ == address(0)) revert BurnerLoans_ZeroAddress();

        backingOracle = backingOracle_;
        emit BackingOracleSet(backingOracle_);
    }

    /// @notice Sets the global active debt cap.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance.
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///      - `debtCapOhm_` is below current total active debt.
    ///      - `debtCapOhm_` is below any configured asset debt cap.
    /// @param debtCapOhm_ New global cap, in OHM decimals.
    function setGlobalDebtCap(uint256 debtCapOhm_) external onlyAdminRole {
        _validateDebtCap(debtCapOhm_, totalActiveDebtOhm);
        uint256 len = _configuredAssets.length;
        for (uint256 i; i < len; ++i) {
            if (_assetConfigs[_configuredAssets[i]].debtCap > debtCapOhm_) {
                revert BurnerLoans_InvalidCap();
            }
        }

        globalDebtCapOhm = debtCapOhm_;
        emit GlobalDebtCapSet(debtCapOhm_);
    }

    /// @notice Adds a whitelisted collateral asset.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance. Validates PRICE approval,
    ///      DepositManager support, ERC20 decimal scale, and risk bounds.
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///      - `asset_` is zero.
    ///      - `asset_` is already configured.
    ///      - The asset's ERC20 decimals exceed the supported maximum.
    ///      - `debtCapOhm_` is below current active debt for `asset_`.
    ///      - `debtCapOhm_` is above the global debt cap.
    ///      - Risk, bps, maturity, or fee parameters violate configured bounds.
    ///      - PRICE does not approve the asset or returns a zero price.
    ///      - DepositManager does not configure the asset or BurnerLoans deposit period.
    ///      - DepositManager has not enabled the deposit period.
    /// @param asset_ Collateral asset to add.
    /// @param debtCapOhm_ Initial active debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk and term configuration.
    /// @param feeConfig_ Initial utilization fee curve.
    function addAsset(
        address asset_,
        uint256 debtCapOhm_,
        AssetRiskConfigInput calldata riskConfig_,
        AssetFeeConfig calldata feeConfig_
    ) external onlyAdminRole {
        if (isAssetConfigured[asset_]) revert BurnerLoans_AssetAlreadyConfigured(asset_);
        AssetConfig memory assetConfig = _validateAndBuildAssetConfig(
            asset_,
            debtCapOhm_,
            riskConfig_
        );
        _validateFeeConfig(feeConfig_);

        isAssetConfigured[asset_] = true;
        _configuredAssets.push(asset_);
        _assetConfigs[asset_] = assetConfig;
        _assetFeeConfigs[asset_] = feeConfig_;

        emit AssetAdded(asset_, assetConfig);
        emit AssetFeeConfigSet(asset_, feeConfig_);
        emit AssetEnabled(asset_);
    }

    /// @notice Sets an asset's active debt cap.
    /// @dev Callable by admin or the configurator. Direct admin calls are effectively
    ///      timelocked by governance in the expected deployment.
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the configurator.
    ///      - `asset_` is not configured.
    ///      - `debtCapOhm_` is below current active debt for `asset_`.
    ///      - `debtCapOhm_` is above the global debt cap.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New asset cap, in OHM decimals.
    function setAssetDebtCap(address asset_, uint256 debtCapOhm_) external onlyConfiguratorOrAdmin {
        _requireAssetConfigured(asset_);
        _validateDebtCap(debtCapOhm_, assetActiveDebtOhm[asset_]);
        if (debtCapOhm_ > globalDebtCapOhm) revert BurnerLoans_InvalidCap();

        _assetConfigs[asset_].debtCap = debtCapOhm_;
        emit AssetDebtCapSet(asset_, debtCapOhm_);
    }

    /// @notice Sets the external config timelock executor.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance. The configurator can call
    ///      risk-parameter setters without holding admin.
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///      - `configurator_` is zero.
    /// @param configurator_ New configurator address.
    function setConfigurator(address configurator_) external onlyAdminRole {
        if (configurator_ == address(0)) revert BurnerLoans_ZeroAddress();

        configurator = configurator_;
        emit ConfiguratorSet(configurator_);
    }

    /// @notice Enables a configured asset for new borrows and extensions.
    /// @dev Admin-only. In the expected deployment, `admin` is the OCG timelock, so this
    ///      function is effectively timelocked by governance. Used for governance-level
    ///      enablement, including recovery after the re-enable grace period.
    /// @dev Reverts if:
    ///      - The caller does not have the admin role.
    ///      - `asset_` is not configured.
    ///      - PRICE does not approve the asset or returns a zero price.
    ///      - DepositManager does not configure and enable the asset period for BurnerLoans.
    /// @param asset_ Collateral asset to enable.
    function enableAsset(address asset_) external onlyAdminRole {
        AssetConfig storage config = _requireAssetConfigured(asset_);
        _validateAssetDependencies(asset_, true);

        config.enabled = true;
        assetDisabledAt[asset_] = 0;
        emit AssetEnabled(asset_);
    }

    /// @notice Immediately disables a configured asset for new borrows and extensions.
    /// @dev Emergency/admin-only. Does not block repayment, seizure, harvest, or safe cleanup.
    /// @dev Reverts if:
    ///      - The caller has neither emergency nor admin role.
    ///      - `asset_` is not configured.
    ///      - `asset_` is already disabled.
    /// @param asset_ Collateral asset to disable.
    function disableAsset(address asset_) external onlyEmergencyOrAdminRole {
        AssetConfig storage config = _requireAssetConfigured(asset_);
        if (!config.enabled) revert BurnerLoans_AssetNotEnabled(asset_);

        config.enabled = false;
        assetDisabledAt[asset_] = _getBlockTimestamp();
        emit AssetDisabled(asset_);
    }

    /// @notice Re-enables an asset shortly after an emergency disable.
    /// @dev Admin or burner_loans_admin only. Reverts after the grace period; governance must
    ///      then use `enableAsset`.
    /// @dev Reverts if:
    ///      - The caller has neither admin nor burner_loans_admin role.
    ///      - `asset_` is not configured.
    ///      - `asset_` is already enabled.
    ///      - The asset was not disabled or the re-enable grace period has elapsed.
    ///      - PRICE does not approve the asset or returns a zero price.
    ///      - DepositManager does not configure and enable the asset period for BurnerLoans.
    /// @param asset_ Collateral asset to re-enable.
    function reEnableAsset(address asset_) external {
        _onlyBurnerLoansAdminOrAdmin();

        AssetConfig storage config = _requireAssetConfigured(asset_);
        if (config.enabled) revert BurnerLoans_AssetAlreadyEnabled(asset_);

        uint48 disabledAt = assetDisabledAt[asset_];
        uint48 deadline = disabledAt + gracePeriod;
        if (disabledAt == 0 || _getBlockTimestamp() > deadline) {
            revert BurnerLoans_AssetReenableExpired(asset_, deadline);
        }

        _validateAssetDependencies(asset_, true);
        config.enabled = true;
        assetDisabledAt[asset_] = 0;
        emit AssetReenabled(asset_);
        emit AssetEnabled(asset_);
    }

    /// @notice Sets the complete asset fee curve.
    /// @dev Callable by admin or the configurator. The Burner Loans Config Timelock
    ///      may expose partial-update helpers, but this setter receives the full resulting curve.
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the configurator.
    ///      - `asset_` is not configured.
    ///      - Any fee component exceeds 100%.
    ///      - `kinkBps` is at or above 100%.
    ///      - `kinkBps` is zero while `postKinkSlopeBps` is non-zero.
    ///      - The full-utilization fee rate exceeds 100%.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee curve.
    function setAssetFeeConfig(
        address asset_,
        AssetFeeConfig calldata config_
    ) external onlyConfiguratorOrAdmin {
        _setAssetFeeConfig(asset_, config_);
    }

    /// @notice Sets asset risk and term fields.
    /// @dev Callable by admin or the configurator. Replaces all risk and term fields
    ///      while preserving admin-only fields such as enabled status, collateral decimals, and debt cap.
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the configurator.
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
    ) external onlyConfiguratorOrAdmin {
        _setAssetRiskConfig(asset_, config_);
    }

    /// @notice Validates a complete asset risk configuration.
    /// @dev Reverts if collateral factor, minimum collateral ratio, backing multiplier, keeper
    ///      reward bps, term length, max maturity horizon, or max keeper reward violates
    ///      BurnerLoans bounds.
    /// @param config_ Complete asset configuration to validate.
    function validateAssetRiskConfig(AssetConfig calldata config_) external pure {
        _validateRiskConfig(config_);
    }

    /// @notice Validates a complete utilization fee configuration.
    /// @dev Reverts if any bps component exceeds 100%, if kink configuration is invalid, or if
    ///      the full-utilization fee rate exceeds 100%.
    /// @param config_ Complete fee configuration to validate.
    function validateFeeConfig(AssetFeeConfig calldata config_) external pure {
        _validateFeeConfig(config_);
    }

    // ========== CONFIGURATION HELPERS ========== //

    modifier onlyConfiguratorOrAdmin() {
        _onlyConfiguratorOrAdmin();
        _;
    }

    function _onlyBurnerLoansAdminOrAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    function _onlyConfiguratorOrAdmin() internal view {
        if (msg.sender != configurator && !_isAdmin(msg.sender)) {
            revert BurnerLoans_UnauthorizedConfigurator(msg.sender);
        }
    }

    function _authorizeReEnable() internal view override {
        _onlyBurnerLoansAdminOrAdmin();
    }

    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    function _requireAssetConfigured(
        address asset_
    ) internal view returns (AssetConfig storage config) {
        if (!isAssetConfigured[asset_]) revert BurnerLoans_AssetNotConfigured(asset_);
        return _assetConfigs[asset_];
    }

    function _requireAssetEnabled(
        address asset_
    ) internal view returns (AssetConfig storage config) {
        config = _requireAssetConfigured(asset_);
        if (!config.enabled) revert BurnerLoans_AssetNotEnabled(asset_);
    }

    function _setAssetFeeConfig(address asset_, AssetFeeConfig memory config_) internal {
        _requireAssetConfigured(asset_);
        _validateFeeConfig(config_);
        _assetFeeConfigs[asset_] = config_;
        emit AssetFeeConfigSet(asset_, config_);
    }

    function _setAssetRiskConfig(address asset_, AssetRiskConfigInput memory riskConfig_) internal {
        _validateRiskConfig(riskConfig_);
        AssetConfig storage storedConfig = _requireAssetConfigured(asset_);
        AssetConfig memory config = storedConfig;
        config.collateralFactorBps = riskConfig_.collateralFactorBps;
        config.minCollateralRatioBps = riskConfig_.minCollateralRatioBps;
        config.backingMultiplierBps = riskConfig_.backingMultiplierBps;
        config.keeperRewardBps = riskConfig_.keeperRewardBps;
        config.termLength = riskConfig_.termLength;
        config.maxMaturityHorizon = riskConfig_.maxMaturityHorizon;
        config.maxKeeperReward = riskConfig_.maxKeeperReward;
        _assetConfigs[asset_] = config;
        emit AssetRiskConfigSet(asset_, riskConfig_);
    }

    function _validateAndBuildAssetConfig(
        address asset_,
        uint256 debtCapOhm_,
        AssetRiskConfigInput memory riskConfig_
    ) internal view returns (AssetConfig memory assetConfig) {
        if (asset_ == address(0)) revert BurnerLoans_ZeroAddress();

        uint8 actualDecimals = IERC20(asset_).decimals();
        _validateTokenDecimals(actualDecimals);

        assetConfig = AssetConfig({
            enabled: true,
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

        _validateDebtCap(debtCapOhm_, assetActiveDebtOhm[asset_]);
        if (debtCapOhm_ > globalDebtCapOhm) revert BurnerLoans_InvalidCap();
        _validateRiskConfig(assetConfig);
        _validateAssetDependencies(asset_, true);
    }

    function _validateRiskConfig(AssetConfig memory config_) internal pure {
        _validateCollateralFactorBps(config_.collateralFactorBps);
        _validateMinCollateralRatioBps(config_.minCollateralRatioBps);
        _validateBackingMultiplierBps(config_.backingMultiplierBps);
        _validateBps(config_.keeperRewardBps);
        _validateMaturityConfig(config_.termLength, config_.maxMaturityHorizon);
        _validateMaxKeeperReward(config_.maxKeeperReward);
    }

    function _validateRiskConfig(AssetRiskConfigInput memory config_) internal pure {
        _validateCollateralFactorBps(config_.collateralFactorBps);
        _validateMinCollateralRatioBps(config_.minCollateralRatioBps);
        _validateBackingMultiplierBps(config_.backingMultiplierBps);
        _validateBps(config_.keeperRewardBps);
        _validateMaturityConfig(config_.termLength, config_.maxMaturityHorizon);
        _validateMaxKeeperReward(config_.maxKeeperReward);
    }

    function _validateCollateralFactorBps(uint16 collateralFactorBps_) internal pure {
        if (
            collateralFactorBps_ == 0 ||
            collateralFactorBps_ > BurnerLoansConstants.MAX_COLLATERAL_FACTOR_BPS
        ) {
            revert BurnerLoans_InvalidBps(collateralFactorBps_);
        }
    }

    function _validateMinCollateralRatioBps(uint16 minCollateralRatioBps_) internal pure {
        if (
            minCollateralRatioBps_ < _BPS ||
            minCollateralRatioBps_ > BurnerLoansConstants.MAX_COLLATERAL_RATIO_BPS
        ) revert BurnerLoans_InvalidParam();
    }

    function _validateBackingMultiplierBps(uint16 backingMultiplierBps_) internal pure {
        if (
            backingMultiplierBps_ < _BPS ||
            backingMultiplierBps_ > BurnerLoansConstants.MAX_BACKING_MULTIPLIER_BPS
        ) revert BurnerLoans_InvalidParam();
    }

    function _validateMaturityConfig(uint48 termLength_, uint48 maxMaturityHorizon_) internal pure {
        if (
            termLength_ == 0 ||
            termLength_ > BurnerLoansConstants.MAX_TERM_LENGTH ||
            maxMaturityHorizon_ <= termLength_ ||
            maxMaturityHorizon_ > BurnerLoansConstants.MAX_MATURITY_HORIZON
        ) revert BurnerLoans_InvalidParam();
    }

    function _validateFeeConfig(AssetFeeConfig memory config_) internal pure {
        _validateBps(config_.baseFeeBps);
        _validateBps(config_.preKinkSlopeBps);
        _validateBps(config_.postKinkSlopeBps);
        if (config_.kinkBps == 0) {
            if (config_.postKinkSlopeBps != 0) revert BurnerLoans_InvalidFeeConfig();
        } else {
            if (config_.kinkBps >= _BPS) {
                revert BurnerLoans_InvalidFeeConfig();
            }
        }
        if (_feeRateWad(_WAD, config_) > uint256(BurnerLoansConstants.FEE_CAP_BPS) * (_WAD / _BPS))
            revert BurnerLoans_InvalidFeeConfig();
    }

    function _validateDebtCap(uint256 cap_, uint256 activeDebtOhm_) internal pure {
        if (cap_ < activeDebtOhm_) revert BurnerLoans_InvalidCap();
    }

    function _validateMaxKeeperReward(uint256 maxKeeperReward_) internal pure {
        if (maxKeeperReward_ > BurnerLoansConstants.MAX_KEEPER_REWARD) {
            revert BurnerLoans_InvalidParam();
        }
    }

    function _validateAssetDependencies(address asset_, bool requirePeriodEnabled_) internal view {
        if (!_PRICE.isAssetApproved(asset_)) revert BurnerLoans_InvalidPrice();
        if (_PRICE.getPrice(asset_) == 0) revert BurnerLoans_InvalidPrice();

        IDepositManager.AssetConfiguration memory assetConfiguration = _DEPOSIT_MANAGER
            .getAssetConfiguration(IERC20(asset_));
        if (!assetConfiguration.isConfigured) {
            revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }

        IDepositManager.AssetPeriodStatus memory assetPeriod = _DEPOSIT_MANAGER.isAssetPeriod(
            IERC20(asset_),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(this)
        );
        if (!assetPeriod.isConfigured || (requirePeriodEnabled_ && !assetPeriod.isEnabled)) {
            revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }
    }

    /// @notice Validates token-native decimals used for ERC20 balances.
    /// @dev Input: token decimals. Output: none. Reverts above the configured safe token scale.
    function _validateTokenDecimals(uint8 decimals_) internal pure {
        if (decimals_ > _MAX_TOKEN_DECIMALS) revert BurnerLoans_InvalidDecimals(decimals_);
    }

    /// @notice Reverts if a bps value exceeds 100%.
    function _validateBps(uint256 bps_) internal pure {
        if (bps_ > BurnerLoansConstants.MAX_BPS) revert BurnerLoans_InvalidBps(bps_);
    }

    function _feeRateWad(
        uint256 utilizationWad_,
        AssetFeeConfig memory feeConfig_
    ) internal pure virtual returns (uint256);

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
            interfaceId_ == type(IBurnerLoans).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
