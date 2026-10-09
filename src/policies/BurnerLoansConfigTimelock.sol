// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {BurnerLoansDependencies} from "src/policies/libraries/BurnerLoansDependencies.sol";
import {BurnerLoansConfigTimelockLib} from "src/policies/libraries/BurnerLoansConfigTimelockLib.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock
/// @notice Timelock implementation for bounded Burner Loans Config updates.
/// @dev Burner Loans Config is the configurator of Burner Loans. This contract does not configure
///      Burner Loans directly; it may act as Burner Loans Config's config operator. Queue functions
///      validate that this policy and Burner Loans Config are active in their shared Kernel and
///      internally enabled, caller role, config-operator authorization, target asset, payload shape,
///      and resulting configuration at queue time. Execution repeats the policy activity,
///      enablement, and config-operator checks and verifies that the queued sub-action's expected
///      config pre-state still matches live Burner Loans Config state. Emergency cancellation requires
///      this timelock to be enabled and Kernel-active. Value invariants that can legitimately move
///      during the delay, such as active market debt, are rechecked by the Burner Loans Config
///      setter at execution rather than encoded into the pre-state hash.
contract BurnerLoansConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IBurnerLoansConfigTimelock,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @dev ABI-encoded byte length of an asset, fee config, and fee-field selection payload.
    uint256 internal constant _LEN_ADDRESS_FEE_CONFIG_SELECTION = 288;

    /// @dev ABI-encoded byte length of an asset, risk update, and risk-field selection payload.
    uint256 internal constant _LEN_ADDRESS_ASSET_RISK_CONFIG_SELECTION = 416;

    /// @dev ABI-encoded byte length of an address followed by one static value.
    uint256 internal constant _LEN_ADDRESS_UINT256 = 64;

    /// @dev ABI-encoded byte length of one static value.
    uint256 internal constant _LEN_UINT256 = 32;

    bytes32 internal constant _FEE_CONFIG_DOMAIN = keccak256("BURNER_LOANS_FEE_CONFIG");
    bytes32 internal constant _RISK_CONFIG_DOMAIN = keccak256("BURNER_LOANS_RISK_CONFIG");
    bytes32 internal constant _DEBT_CAP_DOMAIN = keccak256("BURNER_LOANS_DEBT_CAP");
    bytes32 internal constant _ASSET_ORIGINATIONS_DOMAIN =
        keccak256("BURNER_LOANS_ASSET_ORIGINATIONS");
    bytes32 internal constant _ASSET_WITHDRAW_AS_SHARES_DOMAIN =
        keccak256("BURNER_LOANS_ASSET_WITHDRAW_AS_SHARES");
    bytes32 internal constant _PRICE_CACHE_MAX_AGE_DOMAIN =
        keccak256("BURNER_LOANS_PRICE_CACHE_MAX_AGE");
    bytes32 internal constant _SEND_FEES_TO_DISTRIBUTOR_DOMAIN =
        keccak256("BURNER_LOANS_SEND_FEES_TO_DISTRIBUTOR");
    bytes32 internal constant _SEND_YIELD_TO_DISTRIBUTOR_DOMAIN =
        keccak256("BURNER_LOANS_SEND_YIELD_TO_DISTRIBUTOR");

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    // ========== STATE ========== //

    /// @notice Burner Loans Config policy for which this contract may act as config operator.
    IBurnerLoansConfig internal immutable _BURNER_LOANS_CONFIG;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys the Burner Loans config timelock.
    /// @dev Reverts if:
    ///      - `burnerLoansConfig_` is zero, does not advertise `IBurnerLoansConfig`,
    ///      `IConfigOperator`, and `IEnabler` support through ERC165, or belongs to a different
    ///      Kernel.
    /// @param kernel_ Kernel contract used by the policy.
    /// @param burnerLoansConfig_ Same-Kernel Burner Loans Config policy that receives updates.
    constructor(
        Kernel kernel_,
        IBurnerLoansConfig burnerLoansConfig_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD)
        ConfigTimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        if (address(burnerLoansConfig_) == address(0)) {
            revert BurnerLoansConfigTimelock_ZeroAddress();
        }
        address burnerLoansConfigAddress = address(burnerLoansConfig_);
        if (
            !ERC165Checker.supportsInterface(
                burnerLoansConfigAddress,
                type(IBurnerLoansConfig).interfaceId
            ) ||
            !ERC165Checker.supportsInterface(
                burnerLoansConfigAddress,
                type(IConfigOperator).interfaceId
            ) ||
            !ERC165Checker.supportsInterface(burnerLoansConfigAddress, type(IEnabler).interfaceId)
        ) {
            revert BurnerLoansConfigTimelock_InvalidBurnerLoans(address(burnerLoansConfig_));
        }
        address configKernel = address(Policy(address(burnerLoansConfig_)).kernel());
        if (configKernel != address(kernel_)) {
            revert BurnerLoansConfigTimelock_KernelMismatch(configKernel);
        }

        _BURNER_LOANS_CONFIG = burnerLoansConfig_;
    }

    // ========== POLICY SETUP ========== //

    /// @notice Configures module dependencies for the policy.
    /// @dev Reverts if:
    ///      - the installed ROLES module major version is not 1.
    /// @return dependencies Keycodes for required modules.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) {
            revert BurnerLoansConfigTimelock_InvalidModuleVersion();
        }
    }

    /// @notice Returns kernel permissions requested by the policy.
    /// @dev This policy does not request module permissions.
    /// @return requests Empty permission request array.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the Burner Loans Config policy targeted by this timelock.
    /// @return IBurnerLoansConfig The Burner Loans Config policy.
    function burnerLoans() external view override returns (IBurnerLoansConfig) {
        return _BURNER_LOANS_CONFIG;
    }

    // ========== QUEUE FUNCTIONS ========== //

    /// @notice Queues an asset fee-curve update.
    /// @dev Reverts if:
    ///      - The timelock or BurnerLoansConfig is Kernel-inactive or disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the configured config operator.
    ///      - `asset_` is not configured in Burner Loans Config.
    ///      - `selection_` selects no fields.
    ///      - Any unselected `config_` field is non-zero.
    ///      - The resulting fee curve violates Burner Loans Config fee bounds.
    ///      Execution later reverts if the asset is disabled, config pre-state changed, the
    ///      timelock or Burner Loans Config is Kernel-inactive or disabled, the config operator
    ///      changed, or the underlying Burner Loans Config setter rejects the resulting full fee
    ///      curve.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Partial fee curve update.
    /// @param selection_ Fields to apply from `config_`.
    /// @return actionId The queued action ID.
    function queueSetAssetFeeConfig(
        address asset_,
        IBurnerLoans.AssetFeeConfig calldata config_,
        FeeConfigUpdateSelection calldata selection_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetFeeConfig.selector,
                abi.encode(asset_, config_, selection_)
            );
    }

    /// @notice Queues an asset active debt cap update.
    /// @dev Reverts if:
    ///      - The timelock or BurnerLoansConfig is Kernel-inactive or disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the configured config operator.
    ///      - `asset_` is not configured in Burner Loans Config.
    ///      - `debtCapOhm_` is below current active debt for `asset_`.
    ///      Execution later reverts if the asset is disabled, config pre-state changed, the
    ///      timelock or Burner Loans Config is Kernel-inactive or disabled, the config operator
    ///      changed, or the Burner Loans Config setter rejects the cap against live active debt.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New active debt cap, in OHM decimals.
    /// @return actionId The queued action ID.
    function queueSetAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetDebtCap.selector,
                abi.encode(asset_, debtCapOhm_)
            );
    }

    /// @inheritdoc IBurnerLoansConfigTimelock
    function queueSetPriceCacheMaxAge(uint48 priceCacheMaxAge_) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setPriceCacheMaxAge.selector,
                abi.encode(priceCacheMaxAge_)
            );
    }

    /// @inheritdoc IBurnerLoansConfigTimelock
    function queueSetSendFeesToDistributor(bool enabled_) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setSendFeesToDistributor.selector,
                abi.encode(enabled_)
            );
    }

    /// @inheritdoc IBurnerLoansConfigTimelock
    function queueSetSendYieldToDistributor(bool enabled_) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setSendYieldToDistributor.selector,
                abi.encode(enabled_)
            );
    }

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @dev Reverts if:
    ///      - queue validation fails or another output-mode transition is already pending
    ///      for the asset. Originations transitions use an independent configuration key.
    function queueSetAssetWithdrawAsShares(
        address asset_,
        bool withdrawAsShares_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetWithdrawAsShares.selector,
                abi.encode(asset_, withdrawAsShares_)
            );
    }

    /// @notice Queues a partial asset risk-configuration update.
    /// @dev Reverts if:
    ///      - The timelock or BurnerLoansConfig is Kernel-inactive or disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the configured config operator.
    ///      - `asset_` is not configured in Burner Loans Config.
    ///      - `selection_` selects no fields.
    ///      - Any unselected `update_` field is non-zero.
    ///      - The resulting risk config violates Burner Loans Config bps or maturity bounds.
    ///      Execution later reverts if the asset is disabled, config pre-state changed, the
    ///      timelock or Burner Loans Config is Kernel-inactive or disabled, the config operator
    ///      changed, or the underlying Burner Loans Config setter rejects the resulting full risk
    ///      config.
    /// @param asset_ Collateral asset to update.
    /// @param update_ Partial risk and term update.
    /// @param selection_ Fields to apply from `update_`.
    /// @return actionId The queued action ID.
    function queueSetAssetRiskConfig(
        address asset_,
        AssetRiskConfigUpdate calldata update_,
        AssetRiskConfigUpdateSelection calldata selection_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetRiskConfig.selector,
                abi.encode(asset_, update_, selection_)
            );
    }

    /// @notice Queues a batch of Burner Loans configuration updates.
    /// @dev Reverts if:
    ///      - the timelock or BurnerLoansConfig is Kernel-inactive or disabled, or if any
    ///      sub-action fails the same validation as the typed queue helpers. These lifecycle checks
    ///      are enforced for every queue entrypoint through `_onSubActionQueued`. The batch is
    ///      stored and executed atomically in array order.
    /// @param actions_ Burner Loans configuration sub-actions.
    /// @return actionId The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @notice Validates queue-wide authorization and lifecycle requirements.
    function _validateConfigQueue(address caller_) internal view override {
        _requireEnabled();
        _requirePoliciesActive();
        _requireRiskConfigProposer(caller_);
        _requireAuthorizedConfigOperator();
        _requireBurnerLoansConfigEnabled();
    }

    /// @notice Validates one product sub-action before shared key acquisition.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        _validateQueuedBurnerLoansAction(action_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        bytes4 selector = action_.selector;
        bytes32 key;
        if (selector == IBurnerLoansConfig.setPriceCacheMaxAge.selector) {
            key = _priceCacheMaxAgeKey();
        } else if (selector == IBurnerLoansConfig.setSendFeesToDistributor.selector) {
            key = keccak256(abi.encode(_SEND_FEES_TO_DISTRIBUTOR_DOMAIN));
        } else if (selector == IBurnerLoansConfig.setSendYieldToDistributor.selector) {
            key = keccak256(abi.encode(_SEND_YIELD_TO_DISTRIBUTOR_DOMAIN));
        } else {
            key = _assetConfigKey(action_);
        }

        keys = new bytes32[](1);
        keys[0] = key;
    }

    /// @dev Derives the conflict key for an asset configuration action.
    function _assetConfigKey(
        ITimelockBatchQueue.BatchAction memory action_
    ) private pure returns (bytes32) {
        bytes4 selector = action_.selector;
        bytes32 domain;
        if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            domain = _FEE_CONFIG_DOMAIN;
        } else if (selector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
            domain = _RISK_CONFIG_DOMAIN;
        } else if (selector == IBurnerLoansConfig.setAssetDebtCap.selector) {
            domain = _DEBT_CAP_DOMAIN;
        } else if (selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector) {
            domain = _ASSET_ORIGINATIONS_DOMAIN;
        } else if (selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector) {
            domain = _ASSET_WITHDRAW_AS_SHARES_DOMAIN;
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }
        return keccak256(abi.encode(domain, abi.decode(action_.payload, (address))));
    }

    /// @notice Selects the configuration contract that owns the guarded domains.
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address destination) {
        return address(_BURNER_LOANS_CONFIG);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32 stateHash) {
        bytes4 selector = action_.selector;
        if (selector == IBurnerLoansConfig.setPriceCacheMaxAge.selector) {
            address maxAgeFacility = _BURNER_LOANS_CONFIG.facility();
            return
                keccak256(
                    abi.encode(maxAgeFacility, IBurnerLoansView(maxAgeFacility).priceCacheMaxAge())
                );
        }
        if (selector == IBurnerLoansConfig.setSendFeesToDistributor.selector) {
            IBurnerLoansView flagsFacility = _yieldFacility();
            return
                keccak256(
                    abi.encode(
                        address(flagsFacility),
                        flagsFacility.sendFeesToDistributor(),
                        flagsFacility.revenueDistributor()
                    )
                );
        }
        if (selector == IBurnerLoansConfig.setSendYieldToDistributor.selector) {
            IBurnerLoansView flagsFacility = _yieldFacility();
            return
                keccak256(
                    abi.encode(
                        address(flagsFacility),
                        flagsFacility.sendYieldToDistributor(),
                        flagsFacility.revenueDistributor()
                    )
                );
        }

        address asset = abi.decode(action_.payload, (address));
        address facility = _BURNER_LOANS_CONFIG.facility();
        if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            return
                keccak256(
                    abi.encode(facility, asset, _BURNER_LOANS_CONFIG.getAssetFeeConfig(asset))
                );
        }

        IBurnerLoans.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(asset);
        if (selector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
            return
                keccak256(
                    abi.encode(facility, asset, BurnerLoansConfigTimelockLib.toRiskConfig(config))
                );
        }
        if (selector == IBurnerLoansConfig.setAssetDebtCap.selector) {
            return keccak256(abi.encode(facility, asset, config.debtCap));
        }
        if (selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector) {
            return keccak256(abi.encode(facility, asset, config.originationsEnabled));
        }
        if (selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector) {
            return keccak256(abi.encode(facility, asset, config.withdrawAsShares));
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @inheritdoc TimelockBatchQueue
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireEnabled();
        _requireBurnerLoansConfigEnabled();
        _requirePoliciesActive();
        _requireAuthorizedConfigOperator();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Requires this timelock enabled and Kernel-active, plus the caller's emergency role.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireEnabled();
        _requireOwnPolicyActive();
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev The grace-period deadline is enforced by `ReEnablerGracePeriod` before re-enablement.
    ///      Reverts if:
    ///      - The caller lacks admin or burner_loans_admin authority (`NotAuthorised`).
    function _authorizeReEnable() internal view override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Authorizes a grace-period update.
    /// @dev Reverts if:
    ///      - The caller lacks admin authority (`ROLESv1.ROLES_RequireRole(ADMIN_ROLE)`).
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Revalidates the constructor-bound Config policy before operational enablement.
    function _beforeEnable(bytes calldata) internal view override {
        _requireBurnerLoansActive();
    }

    /// @dev Preserves the grace-period gate and revalidates Config before re-enabling.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireBurnerLoansActive();
    }

    /// @dev Reverts if:
    ///      - The constructor-bound Config is inactive in this policy's Kernel.
    function _requireBurnerLoansActive() internal view {
        address burnerLoansConfig_ = address(_BURNER_LOANS_CONFIG);
        if (!kernel.isPolicyActive(Policy(burnerLoansConfig_))) {
            revert BurnerLoansConfigTimelock_InvalidBurnerLoans(burnerLoansConfig_);
        }
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        BurnerLoansConfigTimelockLib.executeSubAction(_BURNER_LOANS_CONFIG, action_);
    }

    /// @inheritdoc TimelockBatchQueue
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY) {
            revert ITimelockBatchQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
        }
    }

    /// @inheritdoc TimelockBatchQueue
    function _executionWindow() internal pure override returns (uint48) {
        return EXECUTION_WINDOW;
    }

    // ========== VALIDATION ========== //

    /// @notice Validates a Burner Loans configuration sub-action before key acquisition.
    /// @dev Requires the configured target, a supported selector, the exact payload shape, and all
    ///      applicable asset and resulting-configuration invariants.
    /// @param action_ Burner Loans configuration sub-action to validate.
    function _validateQueuedBurnerLoansAction(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view {
        if (action_.target != address(_BURNER_LOANS_CONFIG)) {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
        }

        bytes4 actionSelector = action_.selector;

        if (
            actionSelector == IBurnerLoansConfig.setPriceCacheMaxAge.selector ||
            actionSelector == IBurnerLoansConfig.setSendFeesToDistributor.selector ||
            actionSelector == IBurnerLoansConfig.setSendYieldToDistributor.selector
        ) {
            _validateQueuedGlobalAction(action_);
            return;
        }

        if (_validateQueuedAssetAction(action_)) return;

        revert ITimelockBatchQueue_ActionInvalid(action_.target, actionSelector);
    }

    /// @dev Validates a global price-cache or distributor-flag update.
    function _validateQueuedGlobalAction(
        ITimelockBatchQueue.BatchAction memory action_
    ) private view {
        bytes4 selector = action_.selector;
        _requirePayloadLength(action_.target, action_.payload, _LEN_UINT256, selector);
        // Every supported payload is one ABI word. Decode it as uint256 so this shared validator
        // can apply selector-specific bounds without a typed ABI decode reverting first: uint48
        // for the cache age, or the canonical 0/1 range for either distributor flag.
        uint256 value = abi.decode(action_.payload, (uint256));
        uint256 maximum = selector == IBurnerLoansConfig.setPriceCacheMaxAge.selector
            ? type(uint48).max
            : 1;
        if (value > maximum) {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }
        // A false flag disables routing, or is a same-value no-op, so it never increases reliance
        // on the distributor. It remains valid with no selected distributor or after the selected
        // distributor becomes disabled or inactive. Only a false-to-true transition validates it.
        if (
            value == 1 &&
            (selector == IBurnerLoansConfig.setSendFeesToDistributor.selector ||
                selector == IBurnerLoansConfig.setSendYieldToDistributor.selector)
        ) {
            IBurnerLoansView facility = _yieldFacility();
            bool alreadyEnabled = selector == IBurnerLoansConfig.setSendFeesToDistributor.selector
                ? facility.sendFeesToDistributor()
                : facility.sendYieldToDistributor();
            if (alreadyEnabled) return;

            address distributor = facility.revenueDistributor();
            if (distributor == address(0)) {
                revert IBurnerLoans.BurnerLoans_RevenueDistributorRequired();
            }
            BurnerLoansDependencies.validateRevenueDistributor(kernel, distributor);
        }
    }

    /// @dev Validates an asset-scoped action and returns false for an unsupported selector.
    function _validateQueuedAssetAction(
        ITimelockBatchQueue.BatchAction memory action_
    ) private view returns (bool) {
        bytes4 actionSelector = action_.selector;
        if (actionSelector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            _requirePayloadLength(
                action_.target,
                action_.payload,
                _LEN_ADDRESS_FEE_CONFIG_SELECTION,
                actionSelector
            );
            (
                address feeAsset,
                IBurnerLoans.AssetFeeConfig memory feeConfig,
                FeeConfigUpdateSelection memory feeSelection
            ) = abi.decode(
                    action_.payload,
                    (address, IBurnerLoans.AssetFeeConfig, FeeConfigUpdateSelection)
                );
            IBurnerLoans.AssetFeeConfig memory config = _BURNER_LOANS_CONFIG.getAssetFeeConfig(
                feeAsset
            );
            config = BurnerLoansConfigTimelockLib.applyFeeConfigUpdate(
                config,
                feeConfig,
                feeSelection
            );
            _BURNER_LOANS_CONFIG.validateFeeConfig(config);
            return true;
        }

        if (actionSelector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
            _requirePayloadLength(
                action_.target,
                action_.payload,
                _LEN_ADDRESS_ASSET_RISK_CONFIG_SELECTION,
                actionSelector
            );
            (
                address asset,
                AssetRiskConfigUpdate memory update,
                AssetRiskConfigUpdateSelection memory selection
            ) = abi.decode(
                    action_.payload,
                    (address, AssetRiskConfigUpdate, AssetRiskConfigUpdateSelection)
                );
            IBurnerLoans.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(asset);
            config = BurnerLoansConfigTimelockLib.applyAssetRiskConfigUpdate(
                config,
                update,
                selection
            );
            _BURNER_LOANS_CONFIG.validateAssetRiskConfig(
                BurnerLoansConfigTimelockLib.toRiskConfig(config)
            );
            return true;
        }

        if (actionSelector == IBurnerLoansConfig.setAssetDebtCap.selector) {
            _requirePayloadLength(
                action_.target,
                action_.payload,
                _LEN_ADDRESS_UINT256,
                actionSelector
            );
            (address asset, uint128 debtCapOhm) = abi.decode(action_.payload, (address, uint128));
            _BURNER_LOANS_CONFIG.validateAssetDebtCap(asset, debtCapOhm);
            return true;
        }

        if (actionSelector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector) {
            _requirePayloadLength(
                action_.target,
                action_.payload,
                _LEN_ADDRESS_UINT256,
                actionSelector
            );
            (address asset, ) = abi.decode(action_.payload, (address, bool));
            _requireAssetConfigured(asset);
            return true;
        }

        if (actionSelector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector) {
            _requirePayloadLength(
                action_.target,
                action_.payload,
                _LEN_ADDRESS_UINT256,
                actionSelector
            );
            (address asset, bool withdrawAsShares) = abi.decode(action_.payload, (address, bool));
            _requireAssetConfigured(asset);
            _yieldFacility().validateAssetWithdrawAsShares(asset, withdrawAsShares);
            return true;
        }

        return false;
    }

    /// @notice Requires this timelock to remain the Config policy's authorized operator.
    /// @dev Reverts if:
    ///      - Config's selected operator is no longer this timelock.
    function _requireAuthorizedConfigOperator() internal view {
        if (IConfigOperator(address(_BURNER_LOANS_CONFIG)).configOperator() != address(this)) {
            revert IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator(address(this));
        }
    }

    /// @notice Validates that the controlled BurnerLoansConfig policy is enabled.
    /// @dev Reverts if:
    ///      - BurnerLoansConfig is disabled (`IEnabler.NotEnabled`).
    function _requireBurnerLoansConfigEnabled() internal view {
        if (!IEnabler(address(_BURNER_LOANS_CONFIG)).isEnabled()) revert IEnabler.NotEnabled();
    }

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    function _requireOwnPolicyActive() internal view {
        address timelock = address(this);
        if (!kernel.isPolicyActive(Policy(timelock))) {
            revert BurnerLoansConfigTimelock_PolicyInactive(timelock);
        }
    }

    /// @dev Both policies must retain Kernel membership for queueing and execution.
    function _requirePoliciesActive() internal view {
        _requireOwnPolicyActive();
        address config = address(_BURNER_LOANS_CONFIG);
        if (!kernel.isPolicyActive(Policy(config))) {
            revert BurnerLoansConfigTimelock_PolicyInactive(config);
        }
    }

    /// @notice Requires an action payload to match the ABI length for its selector.
    /// @dev Reverts if:
    ///      - The payload length differs from the selector's expected ABI length.
    function _requirePayloadLength(
        address target_,
        bytes memory payload_,
        uint256 expectedLength_,
        bytes4 selector_
    ) internal pure {
        if (payload_.length != expectedLength_) {
            revert ITimelockBatchQueue_ActionInvalid(target_, selector_);
        }
    }

    /// @notice Validates that an asset remains configured in Burner Loans Config.
    /// @dev Reverts if:
    ///      - The asset is not configured (`BurnerLoans_AssetNotConfigured`).
    /// @param asset_ Collateral asset to validate.
    function _requireAssetConfigured(address asset_) internal view {
        if (!_BURNER_LOANS_CONFIG.isAssetConfigured(asset_)) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
    }

    /// @notice Returns the facility view used for yield-routing validation and hashing.
    /// @dev The Config facility is immutable after initial binding.
    function _yieldFacility() internal view returns (IBurnerLoansView facility) {
        return IBurnerLoansView(_BURNER_LOANS_CONFIG.facility());
    }

    /// @notice Returns the local guard key for the facility-wide maximum cached-price age.
    function _priceCacheMaxAgeKey() internal pure returns (bytes32 key) {
        return keccak256(abi.encode(_PRICE_CACHE_MAX_AGE_DOMAIN));
    }

    /// @dev Reverts with NotAuthorised when the caller has neither accepted queue-proposer role.
    /// @param caller_ Account submitting the configuration action.
    function _requireRiskConfigProposer(address caller_) internal view {
        _requireAuthorized(
            !_hasRole(caller_, ADMIN_ROLE) && !_hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
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
    )
        public
        view
        override(EnablerV2, ReEnablerGracePeriod, ConfigTimelockBatchQueue)
        returns (bool)
    {
        return
            interfaceId_ == type(IBurnerLoansConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
