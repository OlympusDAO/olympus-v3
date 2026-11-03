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
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE, DEPOSIT_OPERATOR_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @title Deposit Manager Config Timelock
/// @notice Timelocked configuration operator for mutable Deposit Manager settings, including
///         timelocked creation of new asset-period routes.
/// @dev Asset and operator registration remain admin-only on Deposit Manager. This policy may only
///      call the configuration functions accepted by its action validator. Queue and execution
///      require both policies active in their shared Kernel and this timelock enabled. Rescue
///      permits a locally disabled manager; ordinary configuration requires it enabled.
///      Emergency cancellation requires this timelock active but ignores manager readiness.
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
    bytes32 internal constant _RESCUE_DOMAIN = keccak256("DEPOSIT_MANAGER_RESCUE");

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

        PolicyDependency.requireSameKernel(target, address(kernel_));

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

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    modifier onlyActive() {
        _requireOwnPolicyActive();
        _;
    }

    /// @dev Reverts if:
    ///      - The caller holds neither accepted queue-proposer role.
    modifier onlyProposerRole() {
        _requireProposerRole(msg.sender);
        _;
    }

    /// @dev Reverts if:
    ///      - The caller holds neither accepted queue-proposer role (NotAuthorised).
    /// @param caller_ Actual caller whose governance role is checked.
    function _requireProposerRole(address caller_) private view {
        _requireAuthorized(
            !_hasRole(caller_, ADMIN_ROLE) && !_hasRole(caller_, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
    }

    // ========== QUEUE FUNCTIONS ========== //

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if queue admission, the manager's permissionless rescue preview or conflict
    ///      reservation fails. Does not reserve tokens or require the manager locally enabled.
    function queueRescue(
        address token_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManagerV1_1.rescue.selector,
                abi.encode(token_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither admin nor deposit_manager_admin.
    ///      - DepositManager is Kernel-inactive or disabled.
    ///      - This contract is not DepositManager's current config operator.
    ///      - The asset is unconfigured.
    ///      - The cap is below the current minimum.
    ///      - The asset's limits key is pending.
    function queueSetAssetDepositCap(
        IERC20 asset_,
        uint256 depositCap_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.setAssetDepositCap.selector,
                abi.encode(asset_, depositCap_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither admin nor deposit_manager_admin.
    ///      - DepositManager is Kernel-inactive or disabled.
    ///      - This contract is not DepositManager's current config operator.
    ///      - The asset is unconfigured.
    ///      - The minimum exceeds the current cap.
    ///      - The asset's limits key is pending.
    function queueSetAssetMinimumDeposit(
        IERC20 asset_,
        uint256 minimumDeposit_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.setAssetMinimumDeposit.selector,
                abi.encode(asset_, minimumDeposit_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither admin nor deposit_manager_admin.
    ///      - DepositManager is Kernel-inactive or disabled.
    ///      - This contract is not DepositManager's current config operator.
    ///      - The requested requirement is invalid for the configured custody route.
    ///      - The asset's withdrawal-requirement key is pending.
    function queueSetAssetShareWithdrawalRequired(
        IERC20 asset_,
        bool required_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManagerV1_1.setAssetShareWithdrawalRequired.selector,
                abi.encode(asset_, required_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither admin nor deposit_manager_admin.
    ///      - DepositManager is Kernel-inactive or disabled.
    ///      - This contract is not DepositManager's current config operator.
    ///      - The asset period is absent or already enabled.
    ///      - The asset-period key is pending.
    function queueEnableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.enableAssetPeriod.selector,
                abi.encode(asset_, depositPeriod_, operator_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither admin nor deposit_manager_admin.
    ///      - DepositManager is Kernel-inactive or disabled.
    ///      - This contract is not DepositManager's current config operator.
    ///      - The asset period is absent or already disabled.
    ///      - The asset-period key is pending.
    function queueDisableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.disableAssetPeriod.selector,
                abi.encode(asset_, depositPeriod_, operator_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither admin nor deposit_manager_admin.
    ///      - DepositManager is Kernel-inactive or disabled.
    ///      - This contract is not DepositManager's current config operator.
    ///      - The asset is unconfigured.
    ///      - The deposit period is zero.
    ///      - The operator is zero or unregistered.
    ///      - The operator lacks deposit_operator.
    ///      - The route already exists.
    ///      - The asset-period key is pending.
    function queueAddAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return
            _queueAction(
                address(_DEPOSIT_MANAGER),
                IDepositManager.addAssetPeriod.selector,
                abi.encode(asset_, depositPeriod_, operator_)
            );
    }

    /// @inheritdoc IDepositManagerConfigTimelock
    /// @dev Reverts if:
    ///      - Queue-wide lifecycle or authorization validation fails.
    ///      - The batch is empty or too large.
    ///      - A sub-action has an unsupported target or selector.
    ///      - A payload or current target state is invalid.
    ///      - A configuration key is already pending.
    ///
    /// @dev The complete queue operation is atomic.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    // ========== CONFIG TIMELOCK HOOKS ========== //

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - The caller holds neither accepted queue-proposer role (NotAuthorised).
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requireProposerRole(caller_);
        PolicyDependency.requireActive(address(_DEPOSIT_MANAGER), address(kernel));
        _requireAuthorizedConfigOperator();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    // Reason: keeping the bounded seven-selector validator together makes its accepted action
    // surface auditable and avoids single-use dispatch helpers.
    // forge-lint: disable-next-line(cyclomatic-complexity)
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        if (action_.selector != IDepositManagerV1_1.rescue.selector)
            _requireDepositManagerEnabled();
        if (action_.target != address(_DEPOSIT_MANAGER)) _revertInvalidAction(action_);

        bytes4 selector = action_.selector;
        if (selector == IDepositManagerV1_1.rescue.selector) {
            _requirePayloadLength(action_, 32);
            uint256 tokenWord = abi.decode(action_.payload, (uint256));
            if (tokenWord > type(uint160).max) _revertInvalidAction(action_);
            address token = abi.decode(action_.payload, (address));
            // Admission validates the live quote; the balance is not committed to the action.
            // forge-lint: disable-next-line(unused-return)
            IDepositManagerV1_1(address(_DEPOSIT_MANAGER)).previewRescue(token);
            return;
        }
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

        if (selector == IDepositManager.addAssetPeriod.selector) {
            _requirePayloadLength(action_, _LEN_ASSET_PERIOD);
            (IERC20 asset, uint8 period, address operator) = _decodeAssetPeriodPayload(action_);
            IDepositManagerV1_1(address(_DEPOSIT_MANAGER)).validateAddAssetPeriod(
                asset,
                period,
                operator
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
        if (action_.selector == IDepositManagerV1_1.rescue.selector) {
            keys[0] = keccak256(abi.encode(_RESCUE_DOMAIN, abi.decode(action_.payload, (address))));
            return keys;
        }
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
        if (action_.selector == IDepositManagerV1_1.rescue.selector) {
            address token = abi.decode(action_.payload, (address));
            try IDepositManagerV1_1(address(_DEPOSIT_MANAGER)).previewRescue(token) returns (
                uint256
            ) {
                return keccak256(abi.encode(true));
            } catch (bytes memory reason) {
                // Only eligibility drift changes the commitment. Balance/Treasury failures retain
                // their exact error, and receipts never stale a queued full-balance rescue.
                if (
                    keccak256(reason) ==
                    keccak256(
                        abi.encodeWithSelector(
                            IDepositManager.DepositManager_CannotRescueAsset.selector,
                            token
                        )
                    )
                ) return keccak256(abi.encode(false));
                assembly ("memory-safe") {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
        if (action_.selector == IDepositManager.addAssetPeriod.selector) {
            (
                IERC20 routeAsset,
                uint8 routePeriod,
                address routeOperator
            ) = _decodeAssetPeriodPayload(action_);
            IDepositManager.AssetPeriodStatus memory routeStatus = _DEPOSIT_MANAGER.isAssetPeriod(
                routeAsset,
                routePeriod,
                routeOperator
            );
            // Route existence/enabled state and the mutable operator-role membership are both
            // hashed, so direct route creation or a role revocation makes the operation stale.
            // A revoked-then-regranted role once again matches the expected state.
            return
                keccak256(
                    abi.encode(
                        routeStatus.isConfigured,
                        routeStatus.isEnabled,
                        _hasRole(routeOperator, DEPOSIT_OPERATOR_ROLE)
                    )
                );
        }

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
        if (selector == IDepositManagerV1_1.rescue.selector) {
            IDepositManagerV1_1(address(_DEPOSIT_MANAGER)).rescue(
                abi.decode(action_.payload, (address))
            );
        } else if (selector == IDepositManager.setAssetDepositCap.selector) {
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
        } else if (selector == IDepositManager.addAssetPeriod.selector) {
            (IERC20 asset, uint8 period, address operator) = _decodeAssetPeriodPayload(action_);
            /// Reason: receiptTokenId is retrievable off-chain from AssetPeriodConfigured.
            /// forge-lint: disable-next-line(unused-return)
            _DEPOSIT_MANAGER.addAssetPeriod(asset, period, operator);
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
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requirePoliciesActive();
        uint256 count = action_.actions.length;
        bool requiresEnabled;
        for (uint256 i; i < count; ++i) {
            if (action_.actions[i].selector != IDepositManagerV1_1.rescue.selector) {
                requiresEnabled = true;
                break;
            }
        }
        if (requiresEnabled) _requireDepositManagerEnabled();
        _requireAuthorizedConfigOperator();
    }

    /// @inheritdoc TimelockBatchQueue
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnPolicyActive();
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Authorizes bounded re-enablement by governance or `deposit_manager_admin`.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(
            !_isAdmin(msg.sender) && !_hasRole(msg.sender, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override {
        _requireOwnPolicyActive();
        super.setGracePeriod(period_);
    }

    /// @inheritdoc ReEnablerGracePeriod
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

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

    /// @notice Requires the target's local enabled state after its Kernel binding is validated.
    /// @dev Reverts if:
    ///      - The enabled-state getter fails or returns malformed data (PolicyDependency_InvalidDependency).
    ///      - The target is disabled (NotEnabled).
    function _requireDepositManagerEnabled() internal view {
        if (!PolicyDependency.readEnabled(address(_DEPOSIT_MANAGER))) revert IEnabler.NotEnabled();
    }

    /// @notice Requires this timelock to be active in its Kernel.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive (DepositManagerConfigTimelock_PolicyInactive).
    function _requireOwnPolicyActive() internal view {
        if (!kernel.isPolicyActive(this))
            revert DepositManagerConfigTimelock_PolicyInactive(address(this));
    }

    /// @notice Requires own activity and the target's matching Kernel binding and membership.
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive (DepositManagerConfigTimelock_PolicyInactive).
    ///      - The target's Kernel getter fails or is malformed (PolicyDependency_InvalidDependency).
    ///      - The target reports another Kernel (PolicyDependency_KernelMismatch).
    ///      - The target is Kernel-inactive (PolicyDependency_NotActive).
    function _requirePoliciesActive() internal view {
        _requireOwnPolicyActive();
        PolicyDependency.requireActive(address(_DEPOSIT_MANAGER), address(kernel));
    }

    /// @notice Validates the target's binding and readiness for either activation route.
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive (DepositManagerConfigTimelock_PolicyInactive).
    ///      - Kernel or enabled-state metadata fails or is malformed (PolicyDependency_InvalidDependency).
    ///      - The target reports another Kernel (PolicyDependency_KernelMismatch).
    ///      - The target is Kernel-inactive or disabled (PolicyDependency_NotActive).
    function _requireActivationReady() private view {
        _requireOwnPolicyActive();
        PolicyDependency.requireActiveAndEnabled(address(_DEPOSIT_MANAGER), address(kernel));
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
    /// @dev    Does not include route creation, which is validated separately because it targets
    ///         an absent asset-period tuple instead of an existing one.
    function _isAssetPeriodSelector(bytes4 selector_) internal pure returns (bool) {
        return
            selector_ == IDepositManager.enableAssetPeriod.selector ||
            selector_ == IDepositManager.disableAssetPeriod.selector;
    }

    /// @notice Decodes the shared asset/period/operator route payload.
    function _decodeAssetPeriodPayload(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure returns (IERC20 asset, uint8 period, address operator) {
        return abi.decode(action_.payload, (IERC20, uint8, address));
    }

    function _revertInvalidAction(ITimelockBatchQueue.BatchAction memory action_) internal pure {
        revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
    }

    // ========== VERSION / ERC-165 ========== //

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
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

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty (DepositManagerConfigTimelock_InvalidData).
    ///      - Own activity or target binding/readiness validation in _requireActivationReady fails.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert DepositManagerConfigTimelock_InvalidData();
        _requireActivationReady();
    }

    /// @inheritdoc EnablerV2
    /// @dev Kernel inactivity does not prevent disable. Reverts if:
    ///      - Lifecycle data is nonempty (DepositManagerConfigTimelock_InvalidData).
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert DepositManagerConfigTimelock_InvalidData();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The grace deadline exceeds uint48 (SafeCastOverflowedUintDowncast).
    ///      - The current timestamp exceeds the inclusive grace deadline (GracePeriod_Expired).
    ///      - Own activity or target binding/readiness validation in _requireActivationReady fails.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireActivationReady();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The widened deadline exceeds uint48 (SafeCastOverflowedUintDowncast).
    ///      - The current timestamp exceeds the inclusive deadline (GracePeriod_Expired).
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
