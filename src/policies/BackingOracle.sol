// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

// Interfaces
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockQueue} from "src/policies/utils/TimelockQueue.sol";

// Constants
import {BACKING_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title BackingOracle
/// @notice A policy that serves as the canonical OHM backing value (the reserve per OHM, 18 decimals).
/// @dev Backing updates are timelocked. The backing_admin or admin role queues an update, the
///      timelock delay elapses, and then anyone can execute the queued action. The emergency role
///      can cancel malicious or stale queued actions. The admin role can additionally update the
///      backing directly via `setBacking`, without the timelock.
contract BackingOracle is Policy, PolicyEnablerV2, TimelockQueue, IBackingOracle, IVersioned {
    // ========== CONSTANTS ========== //

    uint256 private constant _ENABLE_DATA_LENGTH = 32;
    uint256 private constant _MAX_BACKING_CHANGE_PERCENT = 10;
    uint256 private constant _PERCENT_SCALE = 100;

    /// @notice The minimum accepted timelock delay.
    uint48 public constant MIN_TIMELOCK_DELAY = 1 days;

    /// @notice The maximum accepted timelock delay.
    uint48 public constant MAX_TIMELOCK_DELAY = 30 days;

    /// @notice The window after the timelock delay during which a queued action can be executed.
    uint48 public constant EXECUTION_WINDOW = 7 days;

    // ========== STATE ========== //

    /// @inheritdoc IBackingOracle
    uint256 public override backing;

    // ========== INITIALIZATION & POLICY SETUP ========== //

    constructor(Kernel kernel_) Policy(kernel_) TimelockQueue(MIN_TIMELOCK_DELAY) {
        if (address(kernel_) == address(0)) revert BackingOracle_ZeroKernelAddress();

        // Disabled by default
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 m, ) = ROLES.VERSION();
        if (m != 1) revert Policy_WrongModuleVersion(abi.encode([1]));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev A read-only policy; no module writes are required.
    function requestPermissions() external pure override returns (Permissions[] memory) {}

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IBackingOracle
    /// @dev The backing value is denominated in 18 decimals. Does not revert.
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    // ========== ROLE GATES ========== //

    /// @notice Reverts if `account_` holds neither the `backing_admin` role nor the admin role.
    function _onlyBackingAdminOrAdminRole(address account_) internal view {
        _requireAuthorized(!_hasRole(account_, BACKING_ADMIN_ROLE) && !_isAdmin(account_));
    }

    // ========== ENABLE ========== //

    /// @inheritdoc EnablerV2
    /// @dev Sets the `backing`. The value is applied without the timelock because `enable` is
    ///      already gated to the admin role.
    ///
    ///      Reverts if:
    ///      - The enable data is not the correct length.
    ///      - The initial backing value is zero.
    function _beforeEnable(bytes calldata data_) internal override {
        if (data_.length != _ENABLE_DATA_LENGTH) revert BackingOracle_InvalidEnableDataLength();
        uint256 initialBacking = abi.decode(data_, (uint256));
        _requireNonzeroBacking(initialBacking);

        _setBacking(initialBacking);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IBackingOracle
    /// @dev The admin role is expected to be held only by the OCG timelock, so the
    ///      function is de-facto timelocked.
    ///
    ///      Reverts if:
    ///      - The policy is not enabled.
    ///      - The caller does not hold the admin role.
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` changes the current backing beyond the allowed threshold.
    function setBacking(uint256 newBacking_) external givenEnabled onlyAdminRole {
        _validateBackingChange(newBacking_);

        _setBacking(newBacking_);
    }

    /// @inheritdoc IBackingOracle
    /// @dev The queued action targets this policy with the `queueSetBacking` selector and is
    ///      applied by `_executeAction` when executed.
    ///
    ///      Reverts if:
    ///      - The policy is not enabled.
    ///      - The caller holds neither the backing_admin role nor the admin role.
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` changes the current backing beyond the allowed threshold.
    function queueSetBacking(uint256 newBacking_) external returns (uint64 actionId_) {
        return _queueAction(address(this), this.queueSetBacking.selector, abi.encode(newBacking_));
    }

    // ========== TIMELOCK MANAGEMENT ========== //

    /// @inheritdoc IBackingOracle
    /// @dev Already-queued actions keep the delay they were queued with. The admin role is
    ///      expected to be held only by the OCG timelock, so the change is de-facto
    ///      timelocked.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - The delay is outside the `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]` range.
    function setTimelockDelay(uint48 delay_) external onlyAdminRole {
        _setTimelockDelay(delay_);
    }

    /// @inheritdoc TimelockQueue
    /// @dev Called by `_queueAction` before the queued action is stored. This is the queue-time
    ///      gate: it checks enabled status, queue authorization, the supported target and
    ///      selector pair, and payload validity.
    ///
    ///      Reverts if:
    ///      - The policy is not enabled.
    ///      - The caller cannot queue the requested action.
    ///      - The target and selector pair is not supported.
    ///      - The payload cannot be decoded for the action.
    ///      - The decoded payload fails action-specific validation.
    function _validateQueue(
        address caller_,
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) internal view override {
        _requireEnabled();

        if (target_ == address(this) && selector_ == this.queueSetBacking.selector) {
            _onlyBackingAdminOrAdminRole(caller_);
            _validateBackingChange(abi.decode(payload_, (uint256)));
            return;
        }

        revert ITimelockQueue_ActionInvalid(target_, selector_);
    }

    /// @inheritdoc TimelockQueue
    /// @dev Called by `executeQueuedAction` after the standard timelock state checks pass and
    ///      before `_executeAction` runs. Execution is deliberately permissionless: the proposer
    ///      was authorized by `_validateQueue`, and requiring an execution role would let an
    ///      unavailable or compromised executor block already-approved changes.
    ///
    ///      Reverts if:
    ///      - The policy is not enabled.
    ///      - The queued target and selector pair is not supported.
    function _validateExecution(
        address,
        uint64,
        ITimelockQueue.QueuedAction memory action_
    ) internal view override {
        _requireEnabled();

        if (action_.target == address(this) && action_.selector == this.queueSetBacking.selector)
            return;

        revert ITimelockQueue_ActionInvalid(action_.target, action_.selector);
    }

    /// @inheritdoc TimelockQueue
    /// @dev Called by `cancelQueuedAction` after the standard cancellable-state checks pass.
    ///      Cancellation is intentionally allowed while the policy is disabled so the emergency
    ///      role can clear malicious or stale queued actions. The emergency role is separate from
    ///      the roles that can queue actions, giving emergency operators a narrow veto path
    ///      without granting them backing or timelock-delay authority.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the emergency role.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockQueue.QueuedAction memory
    ) internal view override {
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @inheritdoc TimelockQueue
    /// @dev Called by `executeQueuedAction` after `_validateExecution` passes. Dispatches the
    ///      queued action to the corresponding local operation.
    ///
    ///      Reverts if:
    ///      - The queued target and selector pair is not supported.
    ///      - The queued payload cannot be decoded for the action.
    ///      - The decoded payload fails action-specific validation at execution time.
    function _executeAction(uint64, ITimelockQueue.QueuedAction memory action_) internal override {
        if (action_.target == address(this) && action_.selector == this.queueSetBacking.selector) {
            uint256 newBacking = abi.decode(action_.payload, (uint256));
            // The current backing may have moved since queueing, so the change threshold is
            // validated again at execution time.
            _validateBackingChange(newBacking);
            _setBacking(newBacking);
            return;
        }

        revert ITimelockQueue_ActionInvalid(action_.target, action_.selector);
    }

    /// @inheritdoc TimelockQueue
    /// @dev Reverts if the delay is outside the `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]` range.
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY)
            revert ITimelockQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
    }

    /// @inheritdoc TimelockQueue
    function _executionWindow() internal pure override returns (uint48 executionWindow_) {
        return EXECUTION_WINDOW;
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Validate a proposed backing change against the current backing value.
    /// @dev The check runs at queue time as an early guard and again at execution time as the
    ///      authoritative check, because the current backing may change between the two.
    ///
    ///      Reverts if:
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` changes the current backing beyond the allowed threshold.
    ///
    /// @param newBacking_ The proposed backing value (18 decimals).
    function _validateBackingChange(uint256 newBacking_) internal view {
        _requireNonzeroBacking(newBacking_);

        uint256 currentBacking = backing;
        // Cannot change by more than _MAX_BACKING_CHANGE_PERCENT per executed update
        uint256 minBacking = (currentBacking * (_PERCENT_SCALE - _MAX_BACKING_CHANGE_PERCENT)) /
            _PERCENT_SCALE;
        uint256 maxBacking = (currentBacking * (_PERCENT_SCALE + _MAX_BACKING_CHANGE_PERCENT)) /
            _PERCENT_SCALE;
        if (newBacking_ < minBacking || newBacking_ > maxBacking)
            revert BackingOracle_BackingChangeTooLarge(
                currentBacking,
                newBacking_,
                minBacking,
                maxBacking
            );
    }

    function _setBacking(uint256 backing_) private {
        backing = backing_;
        emit BackingSet(backing_);
    }

    function _requireNonzeroBacking(uint256 backing_) private pure {
        if (backing_ == 0) revert BackingOracle_ZeroBacking();
    }

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, TimelockQueue) returns (bool) {
        return
            interfaceId_ == type(IBackingOracle).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            EnablerV2.supportsInterface(interfaceId_) ||
            TimelockQueue.supportsInterface(interfaceId_);
    }
}
