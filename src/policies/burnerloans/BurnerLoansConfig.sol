// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {LoanToken} from "src/policies/burnerloans/libraries/LoanToken.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title Burner Loans Config
/// @notice Opinionated configuration policy for Burner Loans markets stored in FLOAN.
/// @dev FLOAN owns market terms and encoded Burner Loans parameters; this policy holds their write
///      authority. Core keeps the permanent asset-to-market registry and custody identity, so replacing
///      Config transfers market management without moving borrower positions or collateral.
contract BurnerLoansConfig is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    IBurnerLoansConfig,
    IBurnerLoansCoreBound,
    IVersioned
{
    // ========== DEPENDENCIES ========== //

    IERC20 internal immutable _OHM;
    IBurnerLoansCore internal immutable _CORE;

    // ========== MODULES ========== //

    IFLOANv1 internal _FLOAN;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys configuration permanently bound to an already-deployed Core.
    /// @dev Core need not be operational. Failed or malformed identity reads use InvalidCore.
    /// @param kernel_ Kernel that manages this policy and its module dependencies.
    /// @param core_ Permanent Core from which the principal-token identity is derived.
    /// @dev Reverts if:
    ///      - Core lacks required interfaces, reports another Kernel, or its OHM identity is invalid.
    constructor(
        Kernel kernel_,
        IBurnerLoansCore core_
    ) Policy(kernel_) ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD) {
        _OHM = IERC20(_readCoreOhm(core_));
        _CORE = core_;
    }

    // ========== KERNEL FUNCTIONS ========== //

    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    modifier onlyActive() {
        _requirePolicyActive();
        _;
    }

    /// @dev Reverts if:
    ///      - Core is executing a guarded settlement.
    ///
    /// @dev The Core settlement guard is checked before local lifecycle and authorization.
    modifier whenCoreNotSettling() {
        _CORE.requireNotReentrant();
        _;
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - FLOAN or ROLES is missing or uses an unsupported version.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("FLOAN");
        dependencies[1] = toKeycode("ROLES");

        _FLOAN = IFLOANv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        // FLOAN compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 floanMajor, ) = Module(address(_FLOAN)).VERSION();
        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (floanMajor != 1 || rolesMajor != 1) {
            revert IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion();
        }
    }

    /// @inheritdoc Policy
    /// @dev Declares only the listed module selectors; no dynamic permissions or token approvals.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode loan = toKeycode("FLOAN");
        requests = new Permissions[](6);
        requests[0] = Permissions(loan, IFLOANv1.createMarket.selector);
        requests[1] = Permissions(loan, IFLOANv1.setMarketOriginationsEnabled.selector);
        requests[2] = Permissions(loan, IFLOANv1.setMarketPrincipalCap.selector);
        requests[3] = Permissions(loan, IFLOANv1.setMarketRiskConfig.selector);
        requests[4] = Permissions(loan, IFLOANv1.setMarketBaseFee.selector);
        requests[5] = Permissions(loan, IFLOANv1.setMarketConfigData.selector);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reads without state changes; errors from dependency views propagate.
    function ohm() external view returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reads without state changes; errors from dependency views propagate.
    function facility() external view returns (address) {
        return address(_CORE);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - No facility is bound or the bound facility's inventory getter fails.
    function inventory() external view returns (address) {
        return _CORE.inventory();
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - The market lookup fails.
    function isAssetConfigured(address asset_) external view returns (bool) {
        return _isAssetConfigured(asset_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - No unique bound FLOAN market exists for the asset.
    function marketId(address asset_) external view returns (uint32) {
        return _marketId(asset_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - No unique bound market exists or its configuration schema is incompatible.
    function getAssetConfig(
        address asset_
    ) external view returns (IBurnerLoansCore.AssetConfig memory) {
        return _getAssetConfig(_marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - No unique bound market exists or its configuration schema is incompatible.
    function getAssetFeeConfig(
        address asset_
    ) public view returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        return _getAssetFeeConfig(_marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansCoreBound
    function core() external view override returns (address) {
        return address(_CORE);
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
    ///      - PRICE does not approve the asset.
    ///      - DepositManager does not configure the asset or BurnerLoans deposit period.
    ///      - DepositManager has not enabled the deposit period.
    /// @dev This function does not attempt a token transfer and therefore cannot detect conditional
    ///      or fee-on-transfer behavior. Governance must admit only exact-transfer collateral;
    ///      Burner Loans and DepositManager each enforce exact receipt at their respective custody
    ///      boundary.
    /// @param asset_ Collateral asset to add.
    /// @param debtCapOhm_ Initial active debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk and term configuration.
    /// @param feeConfig_ Initial utilization fee curve.
    /// @param withdrawAsShares_ Whether all DepositManager exits return ERC-4626 shares.
    function addAsset(
        address asset_,
        uint128 debtCapOhm_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata riskConfig_,
        IBurnerLoansRisk.AssetFeeConfig calldata feeConfig_,
        bool withdrawAsShares_
    ) external onlyActive givenEnabled onlyAdminRole {
        _requireCoreOperational();

        if (_isAssetConfigured(asset_)) {
            revert IBurnerLoansConfig.BurnerLoans_AssetAlreadyConfigured(asset_);
        }
        IBurnerLoansCore.AssetConfig memory assetConfig = _validateAndBuildAssetConfig(
            asset_,
            debtCapOhm_,
            riskConfig_,
            withdrawAsShares_
        );
        _validateFeeConfig(feeConfig_);

        _createMarket(asset_, assetConfig, feeConfig_);

        emit IBurnerLoansConfig.AssetAdded(asset_, assetConfig);
        emit IBurnerLoansConfig.AssetFeeConfigSet(asset_, feeConfig_);
        emit IBurnerLoansConfig.AssetOriginationsSet(asset_, true);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - Config is disabled/inactive or the caller lacks configuration authority.
    ///      - The market is unregistered, has invalid schema/data, or the cap is below principal.
    ///      - A changed cap lacks FLOAN permission/management authority, Core is settling, or the write fails.
    function setAssetDebtCap(
        address asset_,
        uint128 cap_
    ) external whenCoreNotSettling onlyActive givenEnabled onlyConfigOperatorOrAdmin {
        (uint32 id, IBurnerLoansCore.AssetConfig memory cfg) = _validateAssetDebtCap(asset_, cap_);
        if (cfg.debtCap == cap_) return;
        _FLOAN.setMarketPrincipalCap(id, cap_);
        emit AssetDebtCapSet(asset_, cap_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - Config is disabled or the caller is neither admin nor the selected config operator.
    ///      - Burner Loans rejects the new cached-price age.
    function setPriceCacheMaxAge(
        uint48 priceCacheMaxAge_
    ) external onlyActive givenEnabled onlyConfigOperatorOrAdmin {
        // Forwarding uses this Config's identity, so Risk must authorize Config independently.
        // Selecting Config as Core's controller does not grant authority over Risk's settings.
        IBurnerLoansRisk(_CORE.risk()).setPriceCacheMaxAge(priceCacheMaxAge_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - The caller is neither admin nor the selected config operator.
    ///      - Config is locally disabled or inactive in its Kernel.
    ///      - The facility rejects the rescue. The facility may be locally disabled.
    function rescue(
        address token_,
        address destination_
    ) external onlyActive givenEnabled onlyConfigOperatorOrAdmin {
        _CORE.rescue(token_, destination_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - Config is Kernel-inactive.
    ///      - Config is locally disabled.
    ///      - Core's recovery checks fail.
    ///
    /// @dev Permissionless; the quote does not authenticate its viewer or Config's forwarding authority.
    ///      Execution separately checks the actual caller and downstream forwarding authority.
    function previewRescue(address token_, address destination_) external view returns (uint256) {
        _requirePolicyActive();
        _requireEnabled();
        return _CORE.previewRescue(token_, destination_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - Config is disabled/inactive or the caller lacks configuration authority.
    ///      - The market schema/data is invalid, or enabling fails current price/custody support checks.
    ///      - A changed flag reaches a guarded Core settlement or a rejected FLOAN write.
    function setAssetOriginationsEnabled(
        address asset_,
        bool enabled_
    ) external whenCoreNotSettling onlyActive givenEnabled onlyConfigOperatorOrAdmin {
        (uint32 id, IBurnerLoansCore.AssetConfig memory cfg) = _requireAssetConfigured(asset_);
        if (cfg.originationsEnabled == enabled_) return;
        // Reopening needs working pricing and custody. Closing originations must remain possible
        // when one of those dependencies is unavailable, so only the enabling transition probes them.
        if (enabled_) _validateAssetDependencies(asset_);
        _FLOAN.setMarketOriginationsEnabled(id, enabled_);
        emit AssetOriginationsSet(asset_, enabled_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - Config is disabled/inactive or the caller lacks configuration authority.
    ///      - The market schema/data or requested DepositManager withdrawal mode is invalid.
    ///      - Core is settling or registry synchronization/module writes fail.
    function setAssetWithdrawAsShares(
        address asset_,
        bool shares_
    ) external whenCoreNotSettling onlyActive givenEnabled onlyConfigOperatorOrAdmin {
        (uint32 id, IBurnerLoansCore.AssetConfig memory cfg) = _requireAssetConfigured(asset_);
        if (cfg.withdrawAsShares == shares_) return;
        IAssetManagerV1_1(_CORE.depositManager()).validateAssetWithdrawAsShares(
            IERC20(asset_),
            shares_
        );
        LoanMarket.Data memory data = LoanMarket.decode(
            id,
            _FLOAN.getMarket(id),
            _FLOAN.getMarketConfigData(id)
        );
        data.withdrawAsShares = shares_;
        // Store the same output mode in FLOAN's configuration and Core's settlement registry.
        // The Core guard prevents a token callback from changing either halfway through settlement.
        _FLOAN.setMarketConfigData(id, abi.encode(data));
        _CORE.registerMarket(asset_, id, shares_);
        emit AssetWithdrawAsSharesSet(asset_, shares_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Callable by admin or the config operator. The Burner Loans Config Timelock
    ///      receives and validates the complete resulting curve; partial-update machinery is omitted.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither admin nor the config operator.
    ///      - `asset_` is not configured.
    ///      - Any fee component exceeds 100%.
    ///      - `kinkBps` is at or above 100%.
    ///      - `kinkBps` is zero while either slope is non-zero.
    ///      - The full-utilization fee rate exceeds 100%.
    ///      - A changed curve lacks FLOAN authority, Core is settling, or a module write fails.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee curve.
    function setAssetFeeConfig(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig calldata config_
    ) external whenCoreNotSettling onlyActive givenEnabled onlyConfigOperatorOrAdmin {
        (uint32 id, LoanMarket.Data memory data, bool changed) = _validateAssetFeeConfig(
            asset_,
            config_
        );
        if (!changed) return;
        data.kinkBps = config_.kinkBps;
        data.preKinkSlopeBps = config_.preKinkSlopeBps;
        data.postKinkSlopeBps = config_.postKinkSlopeBps;
        _FLOAN.setMarketBaseFee(id, config_.baseFeeBps);
        _FLOAN.setMarketConfigData(id, abi.encode(data));
        emit AssetFeeConfigSet(asset_, config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Callable by admin or the config operator. Replaces all risk and term fields
    ///      while preserving admin-only fields such as enabled status, collateral decimals, and debt
    ///      cap. Term changes do not rewrite active positions' maturities; current terms apply to new
    ///      debt episodes and extensions.
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither admin nor the config operator.
    ///      - `asset_` is not configured.
    ///      - Maximum LTV is zero or above 100%.
    ///      - Backing multiplier is outside protocol bounds.
    ///      - Keeper reward bps is above 100%.
    ///      - `termLength` is zero, above the protocol maximum, or not below `maxMaturityHorizon`.
    ///      - `maxMaturityHorizon` is above the protocol maximum.
    ///      - A changed configuration lacks FLOAN authority, Core is settling, or a module write fails.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete risk and term configuration.
    function setAssetRiskConfig(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata config_
    ) external whenCoreNotSettling onlyActive givenEnabled onlyConfigOperatorOrAdmin {
        (uint32 id, LoanMarket.Data memory data, bool changed) = _validateAssetRiskConfig(
            asset_,
            config_
        );
        if (!changed) return;
        data.backingMultiplierBps = config_.backingMultiplierBps;
        data.keeperRewardBps = config_.keeperRewardBps;
        data.maxKeeperReward = config_.maxKeeperReward;
        _FLOAN.setMarketRiskConfig(
            id,
            config_.termLength,
            config_.maxMaturityHorizon,
            config_.maxLtvBps
        );
        _FLOAN.setMarketConfigData(id, abi.encode(data));
        emit AssetRiskConfigSet(asset_, config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - Maximum LTV, backing multiplier, keeper reward bps, term length, or maturity horizon
    ///        violates Burner Loans bounds.
    ///      The `uint128` maximum-keeper-reward type enforces its storage bound.
    ///      - Config is disabled/inactive, the market schema/data is invalid, or changed-value authority is unavailable.
    /// @param asset_ Registered collateral market.
    /// @param config_ Complete proposed risk configuration.
    function validateAssetRiskConfig(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata config_
    ) external view onlyActive givenEnabled {
        _validateAssetRiskConfig(asset_, config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - Any bps component exceeds 100%, the kink configuration is invalid, or the
    ///        full-utilization fee rate exceeds 100%.
    ///      - Config is disabled/inactive, the market schema/data is invalid, or changed-value authority is unavailable.
    /// @param asset_ Registered collateral market.
    /// @param config_ Complete proposed fee configuration.
    function validateFeeConfig(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig calldata config_
    ) external view onlyActive givenEnabled {
        _validateAssetFeeConfig(asset_, config_);
    }

    /// @inheritdoc IBurnerLoansConfig
    /// @dev Reverts if:
    ///      - The asset is not configured.
    ///      - The proposed cap is below current active debt.
    /// @param asset_ Collateral asset to validate.
    /// @param debtCapOhm_ Proposed asset active debt cap, in OHM decimals.
    function validateAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) external view onlyActive givenEnabled {
        _validateAssetDebtCap(asset_, debtCapOhm_);
    }

    // ========== CONFIGURATION HELPERS ========== //

    /// @notice Restricts a function to the configured config operator or admin.
    /// @dev Reverts if:
    ///      - The caller is neither the selected config operator nor an admin.
    modifier onlyConfigOperatorOrAdmin() {
        _onlyConfigOperatorOrAdmin();
        _;
    }

    /// @notice Requires admin or burner_loans_admin authority.
    /// @dev Reverts if:
    ///      - The caller lacks admin and burner_loans_admin roles.
    function _onlyBurnerLoansAdminOrAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Requires the configured config operator or admin.
    /// @dev Reverts if:
    ///      - The caller is neither the selected config operator nor an admin.
    function _onlyConfigOperatorOrAdmin() internal view {
        if (!_isConfigOperator(msg.sender) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    /// @dev Kernel deactivation revokes rescue forwarding authority independently of local disablement.
    function _requirePolicyActive() internal view {
        if (!kernel.isPolicyActive(Policy(address(this))))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }

    /// @inheritdoc ConfigOperatorSingleStep
    /// @dev Reverts if:
    ///      - Config is disabled or the caller lacks the admin role.
    function _authorizeSetConfigOperator() internal view override returns (bool) {
        _requirePolicyActive();

        _requireEnabled();
        _requireRole(msg.sender, ADMIN_ROLE);
        return true;
    }

    /// @notice Validates the complete Burner Loans Config relationship before activation.
    /// @dev Reverts if:
    ///      - Config is Kernel-inactive.
    ///      - Core is inactive, incompatible or incorrectly bound.
    ///      - Core's selected config operator is not this Config.
    ///
    /// @dev Inventory has independent configuration authority and is not a direct dependency.
    function _validateConfiguration() internal view {
        _requirePolicyActive();
        _requireCoreOperational();
        if (_readCoreAddress(_CORE, IConfigOperator.configOperator.selector) != address(this)) {
            revert BurnerLoansConfig_InvalidCore(address(_CORE));
        }
    }

    /// @notice Authorizes a global re-enable transition.
    /// @dev Reverts if:
    ///      - The caller lacks admin and burner_loans_admin roles.
    function _authorizeReEnable() internal view override {
        _onlyBurnerLoansAdminOrAdmin();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override onlyActive {
        super.setGracePeriod(period_);
    }

    /// @dev The public setter applies activity and local enablement before authorization.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Reverts if:
    ///      - The Core facility linkage is inactive or incompatible.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _validateConfiguration();
    }

    /// @dev Reverts if:
    ///      - The re-enable grace period expired.
    ///      - The Core facility linkage is inactive or incompatible.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateConfiguration();
    }

    /// @notice Resolves and decodes the unique Burner Loans market for a collateral asset.
    /// @dev Reverts if:
    ///      - No unique bound market exists for the asset.
    ///      - Its configuration schema or encoded data length is invalid.
    /// @param asset_ Collateral asset to look up.
    /// @return marketId_ FLOAN market identifier for the configured asset.
    /// @return config Decoded asset configuration.
    function _requireAssetConfigured(
        address asset_
    ) internal view returns (uint32 marketId_, IBurnerLoansCore.AssetConfig memory config) {
        marketId_ = _marketId(asset_);
        config = _getAssetConfig(marketId_);
    }

    /// @notice Writes canonical market parameters and synchronizes Core registration.
    /// @dev Reverts if:
    ///      - FLOAN rejects the caller’s permissions, market authority or submitted configuration.
    ///      - Core rejects registration authority, incompatible market identity or settlement reentry.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param cfg_ Decoded canonical market configuration.
    /// @param fee_ Policy-approved collateral-denominated fee.
    function _createMarket(
        address asset_,
        IBurnerLoansCore.AssetConfig memory cfg_,
        IBurnerLoansRisk.AssetFeeConfig memory fee_
    ) private {
        // Standard risk/fee fields live in FLOAN's Market; Burner-specific fields use the tagged
        // data payload. Readers reconstruct one configuration through LoanMarket rather than a cache.
        LoanMarket.Data memory data = LoanMarket.Data(
            cfg_.withdrawAsShares,
            cfg_.maxKeeperReward,
            cfg_.backingMultiplierBps,
            cfg_.keeperRewardBps,
            fee_.kinkBps,
            fee_.preKinkSlopeBps,
            fee_.postKinkSlopeBps
        );
        uint32 id = _FLOAN.createMarket(
            IFLOANv1.MarketInput(
                asset_,
                address(_OHM),
                address(this),
                address(_CORE),
                LoanMarket.CONFIG_ID,
                cfg_.debtCap,
                cfg_.termLength,
                cfg_.maxMaturityHorizon,
                cfg_.maxLtvBps,
                fee_.baseFeeBps
            ),
            abi.encode(data)
        );
        // Registration makes the new market discoverable to actions and tasks. If Core rejects it,
        // creation of the FLOAN market is reverted in this same transaction.
        _CORE.registerMarket(asset_, id, cfg_.withdrawAsShares);
    }

    /// @notice Builds the initial stored configuration for a new collateral asset.
    /// @dev Reads collateral decimals from the ERC20, sets the asset enabled, and validates the
    ///      risk config, PRICE support, and DepositManager support.
    /// @dev Reverts if:
    ///      - `asset_` is zero.
    ///      - `asset_` is OHM.
    ///      - The asset's ERC20 decimals exceed the supported maximum.
    ///      - `riskConfig_` violates risk, maturity, or keeper reward bounds.
    ///      - PRICE does not approve the asset.
    ///      - DepositManager has not configured and enabled the Burner Loans deposit period.
    /// @param asset_ Collateral asset to add.
    /// @param debtCapOhm_ Initial asset active debt cap, in OHM decimals.
    /// @param riskConfig_ Initial risk and term configuration.
    /// @return assetConfig Initial stored configuration for `asset_`.
    /// @param withdrawAsShares_ Whether the selected output mode transfers shares instead of redeeming.
    function _validateAndBuildAssetConfig(
        address asset_,
        uint128 debtCapOhm_,
        IBurnerLoansRisk.AssetRiskConfigInput memory riskConfig_,
        bool withdrawAsShares_
    ) internal view returns (IBurnerLoansCore.AssetConfig memory assetConfig) {
        uint8 actualDecimals = _collateralDecimals(asset_);

        assetConfig = IBurnerLoansCore.AssetConfig({
            originationsEnabled: true,
            withdrawAsShares: withdrawAsShares_,
            collateralDecimals: actualDecimals,
            maxLtvBps: riskConfig_.maxLtvBps,
            backingMultiplierBps: riskConfig_.backingMultiplierBps,
            keeperRewardBps: riskConfig_.keeperRewardBps,
            termLength: riskConfig_.termLength,
            maxMaturityHorizon: riskConfig_.maxMaturityHorizon,
            debtCap: debtCapOhm_,
            maxKeeperReward: riskConfig_.maxKeeperReward
        });

        _validateRiskConfig(riskConfig_);
        _validateAssetDependencies(asset_);
        IAssetManagerV1_1(_CORE.depositManager()).validateAssetWithdrawAsShares(
            IERC20(asset_),
            withdrawAsShares_
        );
    }

    /// @notice Delegates numeric risk-parameter validation to selected Risk.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param config_ Canonical market or proposed parameter configuration.
    function _validateRiskConfig(
        IBurnerLoansRisk.AssetRiskConfigInput memory config_
    ) internal view {
        IBurnerLoansRisk(_CORE.risk()).validateRiskConfig(config_);
    }

    /// @notice Delegates fee-curve validation to selected Risk.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param config_ Canonical market or proposed parameter configuration.
    function _validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig memory config_) internal view {
        IBurnerLoansRisk(_CORE.risk()).validateFeeConfig(config_);
    }

    /// @notice Validates an asset active debt cap against live Burner Loans state.
    /// @dev Reverts if:
    ///      - The asset is not configured.
    ///      - The proposed cap is below current active debt.
    /// @param asset_ Collateral asset to validate.
    /// @param debtCapOhm_ Proposed asset active debt cap, in OHM decimals.
    /// @return marketId_ Validated FLOAN market identifier for `asset_`.
    /// @return config_ Existing canonical configuration used for unchanged-value comparison.
    function _validateAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) internal view returns (uint32 marketId_, IBurnerLoansCore.AssetConfig memory config_) {
        marketId_ = _marketId(asset_);
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        LoanMarket.requireCompatibleConfig(marketId_, market);
        if (debtCapOhm_ < _FLOAN.getMarketPrincipalDue(marketId_))
            revert IBurnerLoansErrors.BurnerLoans_InvalidCap();
        config_ = LoanMarket.assetConfig(marketId_, market, _FLOAN.getMarketConfigData(marketId_));
        if (config_.debtCap != debtCapOhm_)
            _requireMarketAuthority(
                marketId_,
                market.manager,
                IFLOANv1.setMarketPrincipalCap.selector
            );
    }

    /// @notice Returns whether the bound facility has at least one market for an asset and OHM.
    /// @param asset_ Collateral asset to query.
    /// @return bool configured True when at least one matching FLOAN market exists.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function _isAssetConfigured(address asset_) internal view returns (bool) {
        return _CORE.isAssetRegistered(asset_);
    }

    /// @notice Resolves the unique FLOAN market for a collateral asset and OHM.
    /// @dev Reverts if:
    ///      - No matching market exists or more than one market matches.
    /// @param asset_ Collateral asset to resolve.
    /// @return uint32 marketId_ Unique matching FLOAN market identifier.
    function _marketId(address asset_) internal view returns (uint32) {
        return _CORE.marketId(asset_);
    }

    /// @notice Decodes the Burner Loans asset configuration stored by a FLOAN market.
    /// @dev Reverts if:
    ///      - The market does not exist or its configuration schema or encoded data is invalid.
    /// @param marketId_ FLOAN market identifier to read.
    /// @return IBurnerLoansCore.AssetConfig Decoded Burner Loans asset configuration.
    function _getAssetConfig(
        uint32 marketId_
    ) internal view returns (IBurnerLoansCore.AssetConfig memory) {
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        return LoanMarket.assetConfig(marketId_, market, _FLOAN.getMarketConfigData(marketId_));
    }

    /// @notice Decodes the Burner Loans fee configuration stored by a FLOAN market.
    /// @dev Reverts if:
    ///      - The market does not exist or its configuration schema or encoded data is invalid.
    /// @param marketId_ FLOAN market identifier to read.
    /// @return IBurnerLoansRisk.AssetFeeConfig config Decoded Burner Loans fee configuration.
    function _getAssetFeeConfig(
        uint32 marketId_
    ) internal view returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        IFLOANv1.Market memory market = _FLOAN.getMarket(marketId_);
        return LoanMarket.feeConfig(marketId_, market, _FLOAN.getMarketConfigData(marketId_));
    }

    /// @notice Validates PRICE support through Risk and custody through Core's permanent DepositManager.
    /// @dev Config owns no independently selected pricing or custody dependency. Live prices are checked by actions.
    /// @param asset_ Collateral asset to validate.
    function _validateAssetDependencies(address asset_) internal view {
        IBurnerLoansRisk(_CORE.risk()).validatePriceSupport(asset_);
        IDepositManager manager = IDepositManager(_CORE.depositManager());
        if (!IEnabler(address(manager)).isEnabled())
            revert IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager(address(manager));
        if (!manager.getAssetConfiguration(IERC20(asset_)).isConfigured) {
            revert BurnerLoans_AssetNotRegisteredInDepositManager(asset_, address(manager));
        }
        IDepositManager.AssetPeriodStatus memory period = manager.isAssetPeriod(
            IERC20(asset_),
            LoanParameters._DEPOSIT_PERIOD,
            address(_CORE)
        );
        if (!period.isConfigured)
            revert BurnerLoans_AssetNotRegisteredInDepositManager(asset_, address(manager));
        if (!period.isEnabled)
            revert IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager(address(manager));
    }

    /// @notice Validates token-native decimals used for ERC20 balances.
    /// @dev Reverts if:
    ///      - Token decimals exceed the configured safe scale.
    ///      - The collateral identity or decimals response is invalid.
    /// @param asset_ Proposed collateral token.
    /// @return uint8 Supported native-token decimal precision.
    function _collateralDecimals(address asset_) private view returns (uint8) {
        if (asset_ == address(0) || asset_ == address(_OHM))
            revert BurnerLoans_InvalidCollateralAsset(asset_);
        (bool success, uint8 decimals) = LoanToken.readDecimals(asset_);
        if (!success) revert BurnerLoans_InvalidCollateralAsset(asset_);
        return decimals;
    }

    /// @notice Checks a proposed complete fee curve against its live market and Config's write authority.
    /// @dev Reverts if:
    ///      - Numerical fields, registration, schema/data or changed-value authority are invalid.
    /// @param asset_ Registered collateral asset.
    /// @param config_ Complete proposed fee curve.
    /// @return id Market identifier.
    /// @return data Existing packed product data to preserve when applying the update.
    /// @return changed Whether any fee field differs from canonical state.
    function _validateAssetFeeConfig(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig memory config_
    ) private view returns (uint32 id, LoanMarket.Data memory data, bool changed) {
        _validateFeeConfig(config_);
        id = _marketId(asset_);
        IFLOANv1.Market memory market = _FLOAN.getMarket(id);
        data = LoanMarket.decode(id, market, _FLOAN.getMarketConfigData(id));
        changed =
            market.baseFeeBps != config_.baseFeeBps ||
            data.kinkBps != config_.kinkBps ||
            data.preKinkSlopeBps != config_.preKinkSlopeBps ||
            data.postKinkSlopeBps != config_.postKinkSlopeBps;
        // Match setter no-op behavior: unchanged values need no downstream write authority.
        // A real update writes both FLOAN representations and must be permitted to change each.
        if (changed) {
            _requireMarketAuthority(id, market.manager, IFLOANv1.setMarketBaseFee.selector);
            _requireMarketAuthority(id, market.manager, IFLOANv1.setMarketConfigData.selector);
        }
    }

    /// @notice Checks a proposed complete risk configuration against its live market and Config's write authority.
    /// @dev Reverts if:
    ///      - Numerical fields, registration, schema/data or changed-value authority are invalid.
    /// @param asset_ Registered collateral asset.
    /// @param config_ Complete proposed risk and term configuration.
    /// @return id Market identifier.
    /// @return data Existing packed product data to preserve when applying the update.
    /// @return changed Whether any risk or term field differs from canonical state.
    function _validateAssetRiskConfig(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput memory config_
    ) private view returns (uint32 id, LoanMarket.Data memory data, bool changed) {
        _validateRiskConfig(config_);
        id = _marketId(asset_);
        IFLOANv1.Market memory market = _FLOAN.getMarket(id);
        data = LoanMarket.decode(id, market, _FLOAN.getMarketConfigData(id));
        changed =
            market.maxLtvBps != config_.maxLtvBps ||
            market.termLength != config_.termLength ||
            market.maxMaturityHorizon != config_.maxMaturityHorizon ||
            data.backingMultiplierBps != config_.backingMultiplierBps ||
            data.keeperRewardBps != config_.keeperRewardBps ||
            data.maxKeeperReward != config_.maxKeeperReward;
        if (changed) {
            _requireMarketAuthority(id, market.manager, IFLOANv1.setMarketRiskConfig.selector);
            _requireMarketAuthority(id, market.manager, IFLOANv1.setMarketConfigData.selector);
        }
    }

    /// @notice Preflights the authority FLOAN will check for a changed configuration value.
    /// @dev Reverts if:
    ///      - Config lacks the selector permission or is not the market manager, in FLOAN order.
    /// @param id_ Canonical market identifier.
    /// @param manager_ Manager from the market already read during validation.
    /// @param selector_ FLOAN mutation selector, never the public validator's selector.
    function _requireMarketAuthority(uint32 id_, address manager_, bytes4 selector_) private view {
        if (!kernel.modulePermissions(toKeycode("FLOAN"), Policy(address(this)), selector_))
            revert Module.Module_PolicyNotPermitted(address(this));
        if (manager_ != address(this)) revert IFLOANv1.FLOAN_NotManager(id_, address(this));
    }

    /// @notice Reads an address from a compatible Core getter.
    /// @dev Reverts if:
    ///      - The getter fails or contains noncanonical address bits.
    /// @param candidate_ Core whose identity is being checked.
    /// @param selector_ Required address getter.
    /// @return value Decoded address.
    function _readCoreAddress(
        IBurnerLoansCore candidate_,
        bytes4 selector_
    ) private view returns (address value) {
        bool success;
        (success, value) = SafeCallDecoder.safeReadAddress(address(candidate_), selector_);
        if (!success) revert BurnerLoansConfig_InvalidCore(address(candidate_));
    }

    /// @notice Validates permanent Core metadata without requiring it to be operational.
    /// @dev Reverts if:
    ///      - Required Core interfaces or metadata are invalid (InvalidCore).
    ///      - Core reports another Kernel (PolicyDependency_KernelMismatch).
    /// @param candidate_ Candidate Core.
    /// @return ohm_ Core's nonzero principal-token identity.
    function _readCoreOhm(IBurnerLoansCore candidate_) private view returns (address ohm_) {
        if (
            !ERC165Checker.supportsInterface(
                address(candidate_),
                type(IBurnerLoansCore).interfaceId
            ) ||
            !ERC165Checker.supportsInterface(address(candidate_), type(IEnabler).interfaceId) ||
            !ERC165Checker.supportsInterface(address(candidate_), type(IVersioned).interfaceId)
        ) revert BurnerLoansConfig_InvalidCore(address(candidate_));
        // Membership alone does not prove this binding: Kernel migration changes policy pointers
        // without clearing the old Kernel's activePolicies registry.
        PolicyDependency.requireSameKernel(address(candidate_), address(kernel));
        ohm_ = _readCoreAddress(candidate_, IBurnerLoansCore.ohm.selector);
        if (ohm_ == address(0)) revert BurnerLoansConfig_InvalidCore(address(candidate_));
    }

    /// @notice Requires the same compatible, active and enabled Core used during installation.
    /// @dev Reverts if:
    ///      - Core metadata is invalid or its OHM identity has changed.
    ///      - Core is inactive or disabled.
    function _requireCoreOperational() private view {
        if (_readCoreOhm(_CORE) != address(_OHM))
            revert BurnerLoansConfig_InvalidCore(address(_CORE));
        bool enabled = PolicyDependency.readEnabled(address(_CORE));
        if (!kernel.isPolicyActive(Policy(address(_CORE))) || !enabled)
            revert PolicyDependency.PolicyDependency_NotActive(address(_CORE));
    }

    // ========== VERSION ========== //

    /// @inheritdoc IVersioned
    /// @dev Reports this implementation's interface version; does not query dependencies or alter lifecycle.
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    // ========== ERC165 ========== //

    /// @notice ERC165 interface support.
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    /// @param interfaceId_ ERC-165 interface identifier.
    /// @return bool Whether the interface identifier is supported.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansConfig).interfaceId ||
            interfaceId_ == type(IBurnerLoansCoreBound).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @notice Rejects unused pause payloads; inactive Config may still be disabled.
    /// @dev Reverts if:
    ///      - The lifecycle data is nonempty.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @notice Checks grace overflow locally, preserving shared ReEnabler behavior.
    /// @dev Reverts if:
    ///      - There is uint48 overflow or an expired inclusive grace deadline.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
