// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Deposit Manager Config Timelock
/// @notice Timelocked configuration operator for mutable Deposit Manager settings.
/// @dev Structural registration remains admin-only on Deposit Manager. This policy may only call
///      the mutable configuration functions accepted by its action validator. Queue and execution
///      require both policies to remain active in their shared Kernel and internally enabled;
///      emergency cancellation remains available while either policy is inactive.
contract DepositManagerConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IDepositManagerConfigTimelock,
    IVersioned
{
    // ========== CONSTANTS ========== //

    uint256 internal constant _LEN_ASSET_VALUE = 64;
    uint256 internal constant _LEN_ASSET_PERIOD = 96;

    bytes32 internal constant _ASSET_LIMITS_DOMAIN = keccak256("DEPOSIT_MANAGER_ASSET_LIMITS");
    bytes32 internal constant _ASSET_PERIOD_DOMAIN = keccak256("DEPOSIT_MANAGER_ASSET_PERIOD");
    bytes32 internal constant _ASSET_SHARE_WITHDRAWAL_DOMAIN =
        keccak256("DEPOSIT_MANAGER_ASSET_SHARE_WITHDRAWAL");

    uint32 internal constant _REENABLE_GRACE_PERIOD = 7 days;

    /// @inheritdoc IDepositManagerConfigTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc IDepositManagerConfigTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc IDepositManagerConfigTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    // ========== STATE ========== //

    IDepositManager internal immutable _DEPOSIT_MANAGER;

    // ========== INITIALIZATION ========== //

    /// @dev Validates the target's interfaces and Kernel before storing it.
    constructor(
        Kernel kernel_,
        IDepositManager depositManager_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(_REENABLE_GRACE_PERIOD)
        ConfigTimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        address target = address(depositManager_);
        if (target == address(0)) revert DepositManagerConfigTimelock_ZeroAddress();
        if (
            !ERC165Checker.supportsInterface(target, type(IDepositManager).interfaceId) ||
            !ERC165Checker.supportsInterface(target, type(IDepositManagerV1_1).interfaceId) ||
            !ERC165Checker.supportsInterface(target, type(IAssetManagerV1_1).interfaceId) ||
            !ERC165Checker.supportsInterface(target, type(IConfigOperator).interfaceId) ||
            !ERC165Checker.supportsInterface(target, type(IEnabler).interfaceId)
        ) {
            revert DepositManagerConfigTimelock_InvalidDepositManager(target);
        }

        address targetKernel = address(Policy(target).kernel());
        if (targetKernel != address(kernel_)) {
            revert DepositManagerConfigTimelock_KernelMismatch(targetKernel);
        }

        _DEPOSIT_MANAGER = depositManager_;
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        /// Reason: every ROLES v1 minor is compatible; only the major version is relevant.
        /// forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert DepositManagerConfigTimelock_InvalidModuleVersion();
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IDepositManagerConfigTimelock
    function depositManager() external view returns (IDepositManager manager_) {
        return _DEPOSIT_MANAGER;
    }

    // ========== QUEUE FUNCTIONS ========== //

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if either policy is Kernel-inactive or disabled, this contract is not the
    ///      target's current config operator, the caller has neither `admin` nor
    ///      `deposit_manager_admin`, the asset is not configured, the cap is below the current
    ///      minimum, or the asset's limits key is pending.
    function queueSetAssetDepositCap(
        IERC20 asset_,
        uint256 depositCap_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.setAssetDepositCap.selector,
                abi.encode(asset_, depositCap_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if either policy is Kernel-inactive or disabled, this contract is not the
    ///      target's current config operator, the caller has neither `admin` nor
    ///      `deposit_manager_admin`, the asset is not configured, the minimum exceeds the current
    ///      cap, or the asset's limits key is pending.
    function queueSetAssetMinimumDeposit(
        IERC20 asset_,
        uint256 minimumDeposit_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.setAssetMinimumDeposit.selector,
                abi.encode(asset_, minimumDeposit_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if either policy is Kernel-inactive or disabled, this contract is not the
    ///      target's current config operator, the caller has neither `admin` nor
    ///      `deposit_manager_admin`, the requested requirement is invalid for the configured
    ///      custody route, or the asset's withdrawal-requirement key is pending.
    function queueSetAssetShareWithdrawalRequired(
        IERC20 asset_,
        bool required_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
                abi.encode(asset_, required_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if either policy is Kernel-inactive or disabled, this contract is not the
    ///      target's current config operator, the caller has neither `admin` nor
    ///      `deposit_manager_admin`, the asset period is absent or already enabled, or the
    ///      asset-period key is pending.
    function queueEnableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.enableAssetPeriod.selector,
                abi.encode(asset_, depositPeriod_, operator_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if either policy is Kernel-inactive or disabled, this contract is not the
    ///      target's current config operator, the caller has neither `admin` nor
    ///      `deposit_manager_admin`, the asset period is absent or already disabled, or the
    ///      asset-period key is pending.
    function queueDisableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.disableAssetPeriod.selector,
                abi.encode(asset_, depositPeriod_, operator_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if queue-wide authorization or lifecycle validation fails, the batch is empty
    ///      or too large, or any sub-action has an unsupported target, selector, payload, current
    ///      state, or already-pending configuration key. The complete queue operation is atomic.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    // ========== CONFIG TIMELOCK HOOKS ========== //

    /// @inheritdoc ConfigTimelockBatchQueue
    function _validateConfigQueue(address caller_) internal view override {
        _requireEnabled();
        _requirePoliciesActive();
        if (!_hasRole(caller_, ADMIN_ROLE) && !_hasRole(caller_, DEPOSIT_MANAGER_ADMIN_ROLE)) {
            revert ROLESv1.ROLES_RequireRole(DEPOSIT_MANAGER_ADMIN_ROLE);
        }
        _requireAuthorizedConfigOperator();
        _requireDepositManagerEnabled();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    // Reason: keeping the bounded five-selector validator together makes its accepted action
    // surface auditable and avoids single-use dispatch helpers.
    // forge-lint: disable-next-line(cyclomatic-complexity)
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        if (action_.target != address(_DEPOSIT_MANAGER)) _revertInvalidAction(action_);

        bytes4 selector = action_.selector;
        if (_isAssetLimitsSelector(selector)) {
            _requirePayloadLength(action_, _LEN_ASSET_VALUE);
            (IERC20 asset, uint256 value) = abi.decode(action_.payload, (IERC20, uint256));
            IAssetManager.AssetConfiguration memory configuration = _DEPOSIT_MANAGER
                .getAssetConfiguration(asset);
            if (!configuration.isConfigured) revert IAssetManager.AssetManager_NotConfigured();

            uint256 depositCap = selector == IDepositManager.setAssetDepositCap.selector
                ? value
                : configuration.depositCap;
            uint256 minimumDeposit = selector == IDepositManager.setAssetMinimumDeposit.selector
                ? value
                : configuration.minimumDeposit;
            if (minimumDeposit > depositCap) {
                revert IAssetManager.AssetManager_MinimumDepositExceedsDepositCap(
                    address(asset),
                    minimumDeposit,
                    depositCap
                );
            }
            return;
        }

        if (selector == IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector) {
            _requirePayloadLength(action_, _LEN_ASSET_VALUE);
            (IERC20 asset, bool required) = abi.decode(action_.payload, (IERC20, bool));
            IAssetManagerV1_1(address(_DEPOSIT_MANAGER)).validateAssetShareWithdrawalRequired(
                asset,
                required
            );
            return;
        }

        if (_isAssetPeriodSelector(selector)) {
            _requirePayloadLength(action_, _LEN_ASSET_PERIOD);
            (IERC20 asset, uint8 period, address operator) = abi.decode(
                action_.payload,
                (IERC20, uint8, address)
            );
            IDepositManager.AssetPeriodStatus memory status = _DEPOSIT_MANAGER.isAssetPeriod(
                asset,
                period,
                operator
            );
            if (!status.isConfigured) {
                revert IDepositManager.DepositManager_InvalidAssetPeriod(
                    address(asset),
                    period,
                    operator
                );
            }
            if (selector == IDepositManager.enableAssetPeriod.selector && status.isEnabled) {
                revert IDepositManager.DepositManager_AssetPeriodEnabled(
                    address(asset),
                    period,
                    operator
                );
            }
            if (selector == IDepositManager.disableAssetPeriod.selector && !status.isEnabled) {
                revert IDepositManager.DepositManager_AssetPeriodDisabled(
                    address(asset),
                    period,
                    operator
                );
            }
            return;
        }

        _revertInvalidAction(action_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address destination) {
        return address(_DEPOSIT_MANAGER);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        if (_isAssetLimitsSelector(action_.selector)) {
            (address limitsAsset, ) = abi.decode(action_.payload, (address, uint256));
            keys[0] = keccak256(abi.encode(_ASSET_LIMITS_DOMAIN, limitsAsset));
            return keys;
        }
        if (action_.selector == IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector) {
            (address asset, ) = abi.decode(action_.payload, (address, bool));
            keys[0] = keccak256(abi.encode(_ASSET_SHARE_WITHDRAWAL_DOMAIN, asset));
            return keys;
        }
        (address periodAsset, uint8 period, address operator) = abi.decode(
            action_.payload,
            (address, uint8, address)
        );
        keys[0] = keccak256(abi.encode(_ASSET_PERIOD_DOMAIN, periodAsset, period, operator));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32 stateHash) {
        if (_isAssetLimitsSelector(action_.selector)) {
            (IERC20 limitsAsset, ) = abi.decode(action_.payload, (IERC20, uint256));
            IAssetManager.AssetConfiguration memory configuration = _DEPOSIT_MANAGER
                .getAssetConfiguration(limitsAsset);
            return
                keccak256(
                    abi.encode(
                        configuration.isConfigured,
                        configuration.depositCap,
                        configuration.minimumDeposit
                    )
                );
        }

        if (action_.selector == IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector) {
            (IERC20 asset, ) = abi.decode(action_.payload, (IERC20, bool));
            IAssetManager.AssetConfiguration memory configuration = _DEPOSIT_MANAGER
                .getAssetConfiguration(asset);
            bool required = IAssetManagerV1_1(address(_DEPOSIT_MANAGER))
                .isAssetShareWithdrawalRequired(asset);
            return keccak256(abi.encode(configuration.isConfigured, required));
        }
        (IERC20 periodAsset, uint8 period, address operator) = abi.decode(
            action_.payload,
            (IERC20, uint8, address)
        );
        IDepositManager.AssetPeriodStatus memory status = _DEPOSIT_MANAGER.isAssetPeriod(
            periodAsset,
            period,
            operator
        );
        return keccak256(abi.encode(status.isConfigured, status.isEnabled));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        bytes4 selector = action_.selector;
        if (selector == IDepositManager.setAssetDepositCap.selector) {
            (IERC20 asset, uint256 value) = abi.decode(action_.payload, (IERC20, uint256));
            _DEPOSIT_MANAGER.setAssetDepositCap(asset, value);
        } else if (selector == IDepositManager.setAssetMinimumDeposit.selector) {
            (IERC20 asset, uint256 value) = abi.decode(action_.payload, (IERC20, uint256));
            _DEPOSIT_MANAGER.setAssetMinimumDeposit(asset, value);
        } else if (selector == IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector) {
            (IERC20 asset, bool required) = abi.decode(action_.payload, (IERC20, bool));
            IDepositManagerV1_1(address(_DEPOSIT_MANAGER)).setAssetShareWithdrawalRequired(
                asset,
                required
            );
        } else if (_isAssetPeriodSelector(selector)) {
            (IERC20 asset, uint8 period, address operator) = abi.decode(
                action_.payload,
                (IERC20, uint8, address)
            );
            if (selector == IDepositManager.enableAssetPeriod.selector) {
                _DEPOSIT_MANAGER.enableAssetPeriod(asset, period, operator);
            } else {
                _DEPOSIT_MANAGER.disableAssetPeriod(asset, period, operator);
            }
        } else {
            _revertInvalidAction(action_);
        }
    }

    // ========== TIMELOCK LIFECYCLE ========== //

    /// @inheritdoc TimelockBatchQueue
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireEnabled();
        _requireDepositManagerEnabled();
        _requirePoliciesActive();
        _requireAuthorizedConfigOperator();
    }

    /// @inheritdoc TimelockBatchQueue
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Authorizes bounded re-enablement by governance or `deposit_manager_admin`.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(
            !_isAdmin(msg.sender) && !_hasRole(msg.sender, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
    }

    /// @inheritdoc ReEnablerGracePeriod
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc EnablerV2
    function _beforeEnable(bytes calldata) internal view override {
        _requireDepositManagerActive();
    }

    /// @inheritdoc ReEnablerGracePeriod
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireDepositManagerActive();
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

    // ========== HELPERS ========== //

    function _requireAuthorizedConfigOperator() internal view {
        if (IConfigOperator(address(_DEPOSIT_MANAGER)).configOperator() != address(this)) {
            revert IConfigOperator.ConfigOperator_Unauthorized(address(this));
        }
    }

    function _requireDepositManagerEnabled() internal view {
        if (!IEnabler(address(_DEPOSIT_MANAGER)).isEnabled()) revert IEnabler.NotEnabled();
    }

    function _requireDepositManagerActive() internal view {
        if (!kernel.isPolicyActive(Policy(address(_DEPOSIT_MANAGER)))) {
            revert DepositManagerConfigTimelock_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }
    }

    function _requirePoliciesActive() internal view {
        address timelock = address(this);
        if (!kernel.isPolicyActive(Policy(timelock))) {
            revert DepositManagerConfigTimelock_PolicyInactive(timelock);
        }

        address manager = address(_DEPOSIT_MANAGER);
        if (!kernel.isPolicyActive(Policy(manager))) {
            revert DepositManagerConfigTimelock_PolicyInactive(manager);
        }
    }

    function _requirePayloadLength(
        ITimelockBatchQueue.BatchAction memory action_,
        uint256 expected_
    ) internal pure {
        if (action_.payload.length != expected_) _revertInvalidAction(action_);
    }

    /// @notice Returns whether a selector updates either field in an asset's limits configuration.
    function _isAssetLimitsSelector(bytes4 selector_) internal pure returns (bool) {
        return
            selector_ == IDepositManager.setAssetDepositCap.selector ||
            selector_ == IDepositManager.setAssetMinimumDeposit.selector;
    }

    /// @notice Returns whether a selector changes an existing asset period's enabled state.
    function _isAssetPeriodSelector(bytes4 selector_) internal pure returns (bool) {
        return
            selector_ == IDepositManager.enableAssetPeriod.selector ||
            selector_ == IDepositManager.disableAssetPeriod.selector;
    }

    function _revertInvalidAction(ITimelockBatchQueue.BatchAction memory action_) internal pure {
        revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
    }

    // ========== VERSION / ERC-165 ========== //

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @notice ERC-165 interface support.
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(EnablerV2, ReEnablerGracePeriod, ConfigTimelockBatchQueue)
        returns (bool)
    {
        return
            interfaceId_ == type(IDepositManagerConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
