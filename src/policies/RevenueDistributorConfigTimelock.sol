// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Revenue Distributor Config Timelock
/// @notice Bounded, state-checked delayed configuration and rescue authority.
contract RevenueDistributorConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IRevenueDistributorConfigTimelock,
    IVersioned
{
    /// @notice Minimum delay for queued distributor configuration.
    uint48 public constant MIN_TIMELOCK_DELAY = 1 days;
    /// @notice Maximum delay for queued distributor configuration.
    uint48 public constant MAX_TIMELOCK_DELAY = 30 days;
    /// @notice Time after readiness during which a queued action can execute.
    uint48 public constant EXECUTION_WINDOW = 3 days;
    /// @dev Time after disablement in which this policy can be re-enabled.
    uint32 internal constant _REENABLE_GRACE_PERIOD = 7 days;
    /// @dev Length of one static ABI-encoded argument.
    uint256 internal constant _ABI_WORD_BYTES = 32;
    /// @dev Four static ABI-encoded arguments.
    uint256 internal constant _FOUR_ABI_WORD_BYTES = 128;
    /// @dev Conflict-key namespace for per-asset actions.
    bytes32 internal constant _ASSET_DOMAIN = keccak256("REVENUE_DISTRIBUTOR_ASSET");
    /// @dev Conflict-key namespace for the global yield recipient.
    bytes32 internal constant _YIELD_RECIPIENT_DOMAIN =
        keccak256("REVENUE_DISTRIBUTOR_YIELD_RECIPIENT");

    /// @dev Distributor configured by this timelock.
    IRevenueDistributor internal immutable _DISTRIBUTOR;
    /// @dev Rescue surface of the distributor configured by this timelock.
    IRevenueDistributorRescue internal immutable _DISTRIBUTOR_RESCUE;

    /// @dev Reverts if:
    ///      - The distributor is zero or lacks a required interface.
    ///      - The distributor belongs to another Kernel.
    constructor(
        Kernel kernel_,
        IRevenueDistributor distributor_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(_REENABLE_GRACE_PERIOD)
        ConfigTimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        address target = address(distributor_);
        if (target == address(0)) {
            revert RevenueDistributorConfigTimelock_InvalidDistributor(target);
        }
        _requireTargetInterfaces(target);
        // Construction permits deployment before the distributor is active or enabled.
        PolicyDependency.requireSameKernel(target, address(kernel_));
        _DISTRIBUTOR = distributor_;
        _DISTRIBUTOR_RESCUE = IRevenueDistributorRescue(target);
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - The installed ROLES module has an incompatible major version.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IRevenueDistributorConfigTimelock
    function distributor() external view override returns (address) {
        return address(_DISTRIBUTOR);
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
            !_hasRole(caller_, ADMIN_ROLE) && !_hasRole(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE)
        );
    }

    /// @inheritdoc IRevenueDistributorConfigTimelock
    /// @dev Reverts if:
    ///      - The caller lacks admin or revenue_distributor_admin role.
    ///      - This timelock is disabled, inactive, or not the selected config operator.
    ///      - The distributor is disabled or inactive.
    ///      - The action conflicts with another queued action.
    function queueSetAssetRoutes(
        address asset_,
        uint16 repurchaseBps_,
        IRevenueDistributor.AssetRoute[] calldata routes_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_DISTRIBUTOR),
                IRevenueDistributor.setAssetRoutes.selector,
                abi.encode(asset_, repurchaseBps_, routes_)
            );
    }

    /// @inheritdoc IRevenueDistributorConfigTimelock
    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    ///      - This timelock is disabled, inactive, or not the selected config operator.
    ///      - The distributor is disabled or inactive.
    ///      - The action conflicts with another queued action.
    function queueDisableAssetRoutes(
        address asset_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_DISTRIBUTOR),
                IRevenueDistributor.disableAssetRoutes.selector,
                abi.encode(asset_)
            );
    }

    /// @inheritdoc IRevenueDistributorConfigTimelock
    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    ///      - This timelock is disabled, inactive, or not the selected config operator.
    ///      - The distributor is disabled or inactive.
    ///      - The action conflicts with another queued action.
    function queueSetYieldRecipient(
        address recipient_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_DISTRIBUTOR),
                IRevenueDistributor.setYieldRecipient.selector,
                abi.encode(recipient_)
            );
    }

    /// @inheritdoc IRevenueDistributorConfigTimelock
    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    ///      - This timelock is disabled, inactive, or not the selected config operator.
    ///      - The action conflicts with another queued action.
    function queueRescue(
        address asset_,
        address destination_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_DISTRIBUTOR),
                IRevenueDistributorRescue.rescue.selector,
                abi.encode(asset_, destination_)
            );
    }

    /// @inheritdoc IRevenueDistributorConfigTimelock
    /// @dev Admission validates current entitlement; execution rechecks current routing.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor REVENUE_DISTRIBUTOR_ADMIN.
    ///      - The operator metadata is invalid or this timelock is not selected.
    ///      - The distributor is Kernel-inactive or reports a different Kernel.
    ///      - The asset has no deployed code.
    ///      - The recipient is zero.
    ///      - The destination is invalid.
    ///      - The amount is zero.
    ///      - The amount exceeds the current combined entitlement.
    ///      - The target preview rejects the requested rescue.
    ///      - A conflicting key is reserved.
    ///      - The shared queue action-ID or deadline bounds are exceeded.
    ///
    /// @param asset_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Recipient of the rescued tokens.
    /// @param amount_ Exact positive amount, at most pendingPayout(asset_, recipient_).
    /// @return actionId Queued action identifier.
    function queueRescuePendingPayout(
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_DISTRIBUTOR),
                IRevenueDistributorRescue.rescuePendingPayout.selector,
                abi.encode(asset_, recipient_, destination_, amount_)
            );
    }

    /// @inheritdoc IRevenueDistributorConfigTimelock
    /// @dev Reverts if:
    ///      - The caller lacks admin or revenue_distributor_admin role.
    ///      - This timelock is disabled, inactive, or not the selected config operator.
    ///      - The batch is invalid, conflicts with queued actions, or exceeds capacity.
    ///      Rescue may target a locally disabled distributor.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return _queueAction(actions_);
    }

    /// @dev Reverts if:
    ///      - This timelock is disabled, Kernel-inactive, or not the selected config operator.
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requireProposerRole(caller_);
        _requireSelectedOperator();
    }

    /// @dev Reverts if:
    ///      - The target, selector, or payload is unsupported.
    ///      - A route change targets a disabled or Kernel-inactive distributor.
    ///      Rescue may target a locally disabled distributor.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        if (action_.target != address(_DISTRIBUTOR)) _revertUnsupportedAction(action_);
        bytes4 selector = action_.selector;
        if (
            selector == IRevenueDistributorRescue.rescue.selector ||
            selector == IRevenueDistributorRescue.rescuePendingPayout.selector
        ) {
            _validateRescueAction(action_);
            return;
        }
        if (selector == IRevenueDistributor.setAssetRoutes.selector) {
            (address asset, uint16 bps, IRevenueDistributor.AssetRoute[] memory routes) = abi
                .decode(action_.payload, (address, uint16, IRevenueDistributor.AssetRoute[]));
            if (keccak256(action_.payload) != keccak256(abi.encode(asset, bps, routes))) {
                _revertUnsupportedAction(action_);
            }
            _requireTargetActiveAndEnabled();
            _DISTRIBUTOR.validateSetAssetRoutes(asset, bps, routes);
            return;
        }
        if (
            selector == IRevenueDistributor.disableAssetRoutes.selector ||
            selector == IRevenueDistributor.setYieldRecipient.selector
        ) {
            if (action_.payload.length != _ABI_WORD_BYTES) _revertUnsupportedAction(action_);
            _requireTargetActiveAndEnabled();
            address requestedAddress = abi.decode(action_.payload, (address));
            if (selector == IRevenueDistributor.disableAssetRoutes.selector) {
                _DISTRIBUTOR.validateDisableAssetRoutes(requestedAddress);
            } else {
                _DISTRIBUTOR.validateSetYieldRecipient(requestedAddress);
            }
            return;
        }
        _revertUnsupportedAction(action_);
    }

    /// @dev Reverts if:
    ///      - The payload is malformed or the live preview rejects its inputs.
    function _validateRescueAction(ITimelockBatchQueue.BatchAction memory action_) internal view {
        if (action_.selector == IRevenueDistributorRescue.rescue.selector) {
            if (action_.payload.length != 2 * _ABI_WORD_BYTES) _revertUnsupportedAction(action_);
            (address asset, address destination) = abi.decode(action_.payload, (address, address));
            // Queue validation uses the preview's revert conditions.
            // forge-lint: disable-next-line(unused-return)
            _DISTRIBUTOR_RESCUE.previewRescue(asset, destination);
        } else {
            if (action_.payload.length != _FOUR_ABI_WORD_BYTES) _revertUnsupportedAction(action_);
            (address asset, address recipient, address destination, uint256 amount) = abi.decode(
                action_.payload,
                (address, address, address, uint256)
            );
            // forge-lint: disable-next-line(unused-return)
            _DISTRIBUTOR_RESCUE.previewRescuePendingPayout(asset, recipient, destination, amount);
        }
    }

    /// @dev Returns the sole contract this timelock may configure.
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address) {
        return address(_DISTRIBUTOR);
    }

    /// @dev Shares an asset key among its route, retirement, and rescue actions; yield recipient
    ///      changes use a separate global key.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        if (action_.selector == IRevenueDistributor.setYieldRecipient.selector) {
            keys[0] = _YIELD_RECIPIENT_DOMAIN;
        } else {
            address asset = abi.decode(action_.payload, (address));
            keys[0] = keccak256(abi.encode(_ASSET_DOMAIN, asset));
        }
    }

    /// @dev Stales route changes on distribution or selected-operator changes, and rescue on
    ///      listing-state or selected-operator changes. New token receipts do not stale rescue.
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32) {
        if (action_.selector == IRevenueDistributor.setYieldRecipient.selector) {
            return keccak256(abi.encode(_DISTRIBUTOR.yieldRecipient(), _readConfigOperator()));
        }
        address asset = abi.decode(action_.payload, (address));
        if (
            action_.selector == IRevenueDistributorRescue.rescue.selector ||
            action_.selector == IRevenueDistributorRescue.rescuePendingPayout.selector
        ) {
            // Rescue stays queued across balance or payout changes. A listing-state change
            // invalidates it; the distributor checks the requested amount again at execution.
            return keccak256(abi.encode(_DISTRIBUTOR.assetState(asset), _readConfigOperator()));
        }
        return
            keccak256(abi.encode(_DISTRIBUTOR.assetDistributionHash(asset), _readConfigOperator()));
    }

    /// @dev Reverts if:
    ///      - A validated action has an unsupported selector.
    ///      - The distributor rejects the requested configuration or rescue.
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        bytes4 selector = action_.selector;
        if (selector == IRevenueDistributor.setAssetRoutes.selector) {
            (address asset, uint16 bps, IRevenueDistributor.AssetRoute[] memory routes) = abi
                .decode(action_.payload, (address, uint16, IRevenueDistributor.AssetRoute[]));
            _DISTRIBUTOR.setAssetRoutes(asset, bps, routes);
        } else if (selector == IRevenueDistributor.disableAssetRoutes.selector) {
            _DISTRIBUTOR.disableAssetRoutes(abi.decode(action_.payload, (address)));
        } else if (selector == IRevenueDistributor.setYieldRecipient.selector) {
            _DISTRIBUTOR.setYieldRecipient(abi.decode(action_.payload, (address)));
        } else if (selector == IRevenueDistributorRescue.rescue.selector) {
            (address asset, address destination) = abi.decode(action_.payload, (address, address));
            _DISTRIBUTOR_RESCUE.rescue(asset, destination);
        } else if (selector == IRevenueDistributorRescue.rescuePendingPayout.selector) {
            (address asset, address recipient, address destination, uint256 amount) = abi.decode(
                action_.payload,
                (address, address, address, uint256)
            );
            _DISTRIBUTOR_RESCUE.rescuePendingPayout(asset, recipient, destination, amount);
        } else {
            _revertUnsupportedAction(action_);
        }
    }

    /// @dev Reverts if:
    ///      - This timelock is disabled, Kernel-inactive, or no longer the selected operator.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requireSelectedOperator();
    }

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - The caller lacks the emergency role.
    ///
    /// @dev Target lifecycle and operator selection do not gate cancellation.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnPolicyActive();
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @dev Reverts if:
    ///      - The caller lacks admin and revenue_distributor_admin roles.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(
            !_isAdmin(msg.sender) && !_hasRole(msg.sender, REVENUE_DISTRIBUTOR_ADMIN_ROLE)
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

    /// @dev Reverts if:
    ///      - The caller lacks the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Reverts if:
    ///      - The requested delay is outside governance's allowed range.
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY) {
            revert ITimelockBatchQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
        }
    }

    /// @dev Returns the fixed window in which a ready action may execute.
    function _executionWindow() internal pure override returns (uint48) {
        return EXECUTION_WINDOW;
    }

    /// @dev Reverts if:
    ///      - The target lacks a consumed distributor, rescue, ConfigOperator or Enabler interface.
    function _requireTargetInterfaces(address target_) private view {
        if (
            !ERC165Checker.supportsInterface(target_, type(IRevenueDistributor).interfaceId) ||
            !ERC165Checker.supportsInterface(
                target_,
                type(IRevenueDistributorRescue).interfaceId
            ) ||
            !ERC165Checker.supportsInterface(target_, type(IConfigOperator).interfaceId) ||
            !ERC165Checker.supportsInterface(target_, type(IEnabler).interfaceId)
        ) revert RevenueDistributorConfigTimelock_InvalidDistributor(target_);
    }

    /// @dev Reverts if:
    ///      - The distributor's operator getter fails or returns a noncanonical address.
    function _readConfigOperator() private view returns (address operator) {
        bool success;
        (success, operator) = SafeCallDecoder.safeReadAddress(
            address(_DISTRIBUTOR),
            IConfigOperator.configOperator.selector
        );
        if (!success)
            revert RevenueDistributorConfigTimelock_InvalidDistributor(address(_DISTRIBUTOR));
    }

    /// @dev Reverts if:
    ///      - The distributor's operator getter fails or returns a noncanonical address.
    ///      - This timelock is not the selected operator.
    function _requireSelectedOperator() internal view {
        if (_readConfigOperator() != address(this)) {
            revert IConfigOperator.ConfigOperator_Unauthorized(address(this));
        }
    }

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    function _requireOwnPolicyActive() internal view {
        if (!kernel.isPolicyActive(Policy(address(this)))) {
            revert RevenueDistributorConfigTimelock_PolicyNotActive(address(this));
        }
    }

    /// @dev Reverts if:
    ///      - Required distributor metadata is unreadable or malformed.
    ///      - The distributor reports a different Kernel.
    ///      - The distributor is Kernel-inactive or locally disabled.
    function _requireTargetActiveAndEnabled() internal view {
        PolicyDependency.requireActiveAndEnabled(address(_DISTRIBUTOR), address(kernel));
    }

    /// @dev Target local enablement is neither read nor required.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - The target lacks a consumed interface.
    ///      - The target Kernel getter fails or returns malformed data.
    ///      - The target reports a different Kernel.
    ///      - The target is Kernel-inactive.
    ///      - The target operator getter fails or returns malformed data.
    ///      - This timelock is not the target's selected config operator.
    function _requireActivationReady() private view {
        _requireOwnPolicyActive();
        _requireTargetInterfaces(address(_DISTRIBUTOR));
        PolicyDependency.requireActive(address(_DISTRIBUTOR), address(kernel));
        _requireSelectedOperator();
    }

    /// @dev Reverts if:
    ///      - This helper is called; it always raises InvalidAction with the target and selector.
    function _revertUnsupportedAction(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure {
        revert RevenueDistributorConfigTimelock_InvalidAction(action_.target, action_.selector);
    }

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(EnablerV2, ReEnablerGracePeriod, ConfigTimelockBatchQueue)
        returns (bool)
    {
        return
            interfaceId_ == type(IRevenueDistributorConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///      - This policy is inactive or a required operational dependency is unavailable.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert RevenueDistributorConfigTimelock_InvalidData();
        _requireActivationReady();
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///
    /// @dev Kernel inactivity does not prevent disable.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert RevenueDistributorConfigTimelock_InvalidData();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The shared re-enable grace checks fail.
    ///      - The enable prerequisites fail.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireActivationReady();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The grace deadline does not fit uint48 (SafeCastOverflowedUintDowncast).
    ///      - The inclusive grace window has expired (GracePeriod_Expired).
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
