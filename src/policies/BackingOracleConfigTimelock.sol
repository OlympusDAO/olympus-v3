// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

// Constants
import {BACKING_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Backing Oracle Configuration Timelock
/// @notice	Replaceable delayed governance for one immutable backing oracle.
/// @dev	ADMIN selects this policy as config operator. Replacing that selection immediately
///      revokes this queue's write authority without moving backing storage.
contract BackingOracleConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IBackingOracleConfigTimelock,
    IVersioned
{
    /// @notice	Fixed notice in seconds.
    uint48 public constant TIMELOCK_DELAY = 1 days;
    /// @notice	Inclusive execution window after the notice in seconds.
    uint48 public constant EXECUTION_WINDOW = 7 days;

    uint32 internal constant _DEFAULT_GRACE_PERIOD = 7 days;
    uint256 internal constant _SET_BACKING_PAYLOAD_LENGTH = 32;

    IBackingOracle internal immutable _ORACLE;

    /// @notice	Bind one same-Kernel oracle without requiring startup readiness.
    /// @dev	Does not read target membership, enablement or operator selection.
    /// @dev	Reverts if:
    ///      - `kernel_` is zero.
    ///      - The oracle lacks a consumed interface.
    ///      - The oracle's Kernel getter fails or returns noncanonical data.
    ///      - The oracle reports another Kernel.
    ///
    /// @param	kernel_	Kernel supplying governance roles.
    /// @param	oracle_	Immutable oracle to configure.
    constructor(
        Kernel kernel_,
        IBackingOracle oracle_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(_DEFAULT_GRACE_PERIOD)
        ConfigTimelockBatchQueue(TIMELOCK_DELAY)
    {
        if (address(kernel_) == address(0)) revert BackingOracleTimelock_ZeroKernelAddress();
        _requireTargetInterfaces(address(oracle_));
        PolicyDependency.requireSameKernel(address(oracle_), address(kernel_));
        _ORACLE = oracle_;
    }

    /// @inheritdoc IBackingOracleConfigTimelock
    function backingOracle() external view returns (IBackingOracle) {
        return _ORACLE;
    }

    /// @inheritdoc Policy
    /// @dev	ROLES minor versions remain compatible.
    /// @dev	Reverts if:
    ///      - ROLES is not installed in the Kernel.
    ///      - The ROLES major version is not one.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        // Minor versions do not affect compatibility.
        // forge-lint: disable-next-line(unused-return)
        (uint8 major, ) = ROLES.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IBackingOracleConfigTimelock
    /// @dev	Reverts if:
    ///      - This queue is not active in its Kernel.
    ///      - The queue is not enabled.
    ///      - The caller holds neither ADMIN nor backing_admin.
    ///      - Required target metadata fails or is malformed.
    ///      - The oracle reports another Kernel.
    ///      - The oracle is inactive.
    ///      - The oracle is disabled.
    ///      - This queue is not the oracle's selected config operator.
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` is outside the current backing bounds.
    ///      - The computed upper backing bound exceeds uint256.
    ///      - The backing configuration key is already reserved.
    ///      - The next action ID overflows uint64.
    ///      - An execution deadline overflows uint48.
    function queueSetBacking(uint256 newBacking_) external returns (uint64) {
        return
            _queueAction(
                address(_ORACLE),
                IBackingOracle.setBacking.selector,
                abi.encode(newBacking_)
            );
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev	Reverts if:
    ///      - This queue is not active in its Kernel.
    ///      - The queue is not enabled.
    ///      - The caller holds neither ADMIN nor backing_admin.
    ///      - Target readiness or operator selection validation fails.
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnActive();
        _requireEnabled();
        _requireAuthorized(!_hasRole(caller_, BACKING_ADMIN_ROLE) && !_isAdmin(caller_));
        _requireTargetReady();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev	Only the typed backing setter and canonical uint256 payload are supported.
    /// @dev	Reverts if:
    ///      - The target or selector is unsupported.
    ///      - The payload length is not 32 bytes.
    ///      - The oracle's backing validator rejects the decoded value or current state.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        if (
            action_.target != address(_ORACLE) ||
            action_.selector != IBackingOracle.setBacking.selector ||
            action_.payload.length != _SET_BACKING_PAYLOAD_LENGTH
        ) revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
        _ORACLE.validateSetBacking(abi.decode(action_.payload, (uint256)));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address) {
        return address(_ORACLE);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev	Every proposal configures one backing setting, sharing a destination-scoped key.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory
    ) internal pure override returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = keccak256(abi.encode(IBackingOracle.setBacking.selector));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev	Execution compares the current backing and selected operator with this commitment.
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (bytes32) {
        return
            keccak256(
                abi.encode(IConfigOperator(address(_ORACLE)).configOperator(), _ORACLE.backing())
            );
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev	The immutable oracle checks live authority and backing bounds again. Failures
    ///      propagate and roll back action flags, payloads and reservation changes.
    /// @dev	Reverts if:
    ///      - The oracle rejects the backing update.
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        _ORACLE.setBacking(abi.decode(action_.payload, (uint256)));
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev	Permissionless execution follows shared existence/terminal/time checks.
    /// @dev	Reverts if:
    ///      - This queue is not active in its Kernel.
    ///      - The queue is not enabled.
    ///      - Target readiness or operator selection validation fails.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnActive();
        _requireEnabled();
        _requireTargetReady();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev	Cancellation remains available while paused and never reads the target. Until the
    ///      action expires, ADMIN, EMERGENCY and its proposer (matched by address, not by role)
    ///      may cancel; once the block timestamp is past `expiresAt`, any caller may.
    /// @dev	Reverts if:
    ///      - This queue is not active in its Kernel.
    ///      - The action has not expired and the caller holds neither ADMIN nor EMERGENCY and
    ///        is not its proposer.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view override {
        _requireOwnActive();
        if (_getBlockTimestamp() > action_.expiresAt) return;
        _requireAuthorized(
            !_isAdmin(caller_) && !_hasRole(caller_, EMERGENCY_ROLE) && caller_ != action_.proposer
        );
    }

    /// @notice	Require active/enabled target and current selection at runtime.
    /// @dev	Reverts if:
    ///      - Required target Kernel or enabled-state metadata fails or is malformed.
    ///      - The oracle reports another Kernel.
    ///      - The oracle is inactive.
    ///      - The oracle is disabled.
    ///      - This queue is not the oracle's selected config operator.
    function _requireTargetReady() private view {
        PolicyDependency.requireActiveAndEnabled(address(_ORACLE), address(kernel));
        _requireSelected();
    }

    /// @notice	Reject an inactive queue independently of downstream failures.
    /// @dev	Reverts if:
    ///      - This queue is not active in its Kernel.
    function _requireOwnActive() private view {
        if (!kernel.isPolicyActive(this))
            revert BackingOracleTimelock_PolicyNotActive(address(this));
    }

    /// @notice	Require current delegation independently of proposer authority.
    /// @dev	Reverts if:
    ///      - The oracle's config-operator getter fails or returns malformed data.
    ///      - This queue is not the oracle's selected config operator.
    function _requireSelected() private view {
        _requireAuthorized(IConfigOperator(address(_ORACLE)).configOperator() != address(this));
    }

    /// @notice	Share constructor and activation interface admission.
    /// @dev	Reverts if:
    ///      - The target lacks IBackingOracle, IConfigOperator or IEnabler support.
    function _requireTargetInterfaces(address target_) private view {
        if (
            !ERC165Checker.supportsInterface(target_, type(IBackingOracle).interfaceId) ||
            !ERC165Checker.supportsInterface(target_, type(IConfigOperator).interfaceId) ||
            !ERC165Checker.supportsInterface(target_, type(IEnabler).interfaceId)
        ) revert BackingOracleTimelock_InvalidBackingOracle(target_);
    }

    /// @inheritdoc EnablerV2
    /// @dev	Target enablement is not read, permitting queue repair while the oracle is paused.
    /// @dev	Reverts if:
    ///      - `data_` is nonempty.
    ///      - Activation validation fails.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert BackingOracleTimelock_InvalidEnablerData();
        _validateActivation();
    }

    /// @notice	Validate target identity, membership and delegation independently of its pause.
    /// @dev	Reverts if:
    ///      - This queue is not active in its Kernel.
    ///      - The oracle lacks a consumed interface.
    ///      - The oracle's Kernel getter fails or returns noncanonical data.
    ///      - The oracle reports another Kernel.
    ///      - The oracle is not active in this Kernel.
    ///      - This queue is not the oracle's selected config operator.
    function _validateActivation() private view {
        _requireOwnActive();
        _requireTargetInterfaces(address(_ORACLE));
        PolicyDependency.requireActive(address(_ORACLE), address(kernel));
        _requireSelected();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Recovery preserves pending intent and shares enable's activation validation.
    /// @dev	Reverts if:
    ///      - The grace deadline exceeds uint48.
    ///      - The inclusive grace deadline has expired.
    ///      - Activation validation fails.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateActivation();
    }

    /// @notice	ADMIN or backing_admin may recover within the configured grace window.
    /// @dev	Reverts if:
    ///      - The caller holds neither ADMIN nor backing_admin.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BACKING_ADMIN_ROLE));
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Reverts if:
    ///      - This queue is not active in its Kernel.
    ///      - The queue is not enabled.
    ///      - The caller does not hold ADMIN.
    ///      - `period_` is zero.
    function setGracePeriod(uint32 period_) public override {
        _requireOwnActive();
        super.setGracePeriod(period_);
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Reverts if:
    ///      - The caller does not hold ADMIN.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Widen before narrowing to report informative deadline overflow.
    /// @dev	Reverts if:
    ///      - The grace deadline exceeds uint48.
    ///      - The inclusive grace deadline has expired.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @inheritdoc EnablerV2
    /// @dev	Own inactivity or a broken target does not prevent pausing.
    /// @dev	Reverts if:
    ///      - `data_` is nonempty.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert BackingOracleTimelock_InvalidEnablerData();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev	Reverts if:
    ///      - `delay_` differs from the fixed one-day notice.
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ != TIMELOCK_DELAY)
            revert ITimelockBatchQueue_TimelockDelayInvalid(delay_, TIMELOCK_DELAY, TIMELOCK_DELAY);
    }

    /// @inheritdoc TimelockBatchQueue
    function _executionWindow() internal pure override returns (uint48) {
        return EXECUTION_WINDOW;
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev	Only one backing setting exists; the typed helper creates one sub-action.
    function _maxBatchSize() internal pure override returns (uint256) {
        return 1;
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
            interfaceId_ == type(IBackingOracleConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
