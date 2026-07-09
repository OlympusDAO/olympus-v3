// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/IYieldRepurchaseFacilityV2.sol";
import {IYRFManagerTimelock} from "src/policies/interfaces/IYRFManagerTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";
import {EMERGENCY_ROLE, YRF_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title YRFManagerTimelock
/// @notice Timelock policy that owns the operational (manager) parameters of a
///         YieldRepurchaseFacilityV2 on behalf of the `yrf_manager` role.
/// @dev The policy is intended to be pinned as the facility's immutable manager timelock. In
///      that deployment shape the facility's `setYieldBuybackShare`, `setInitialDiscount`, and
///      `enableAsset` are reachable either through the queue exposed here or directly by the
///      admin (expected to be held only by the OCG timelock).
///
///      Authorization maps to the existing roles: `yrf_manager` is the sole queue proposer,
///      `emergency` is the sole canceller, and `admin` owns the policy's own configuration.
///      Disabling the policy suspends queueing and execution but does not clear queued actions;
///      before re-enabling, the emergency role must cancel any queued action that should not
///      become executable again.
contract YRFManagerTimelock is
    Policy,
    PolicyEnablerV2,
    TimelockBatchQueue,
    IYRFManagerTimelock,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @inheritdoc IYRFManagerTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc IYRFManagerTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc IYRFManagerTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    /// @notice Pre-computed keycode for the ROLES module dependency.
    /// @dev Avoids the runtime cost of `toKeycode("ROLES")` at the call site.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524F4C4553); // toKeycode("ROLES")

    // ========== STATE ========== //

    /// @inheritdoc IYRFManagerTimelock
    address public override facility;

    // ========== INITIALIZATION ========== //

    /// @dev Wire the facility after deployment with `setFacility`.
    ///
    ///      Reverts if the kernel is the zero address or the initial delay is outside
    ///      `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`.
    /// @param kernel_ The Olympus Kernel.
    /// @param initialTimelockDelay_ The initial timelock delay.
    constructor(
        Kernel kernel_,
        uint48 initialTimelockDelay_
    ) Policy(kernel_) TimelockBatchQueue(initialTimelockDelay_) {
        _requireNonzeroAddress(address(kernel_), "kernel");

        // EnablerV2 starts disabled.
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = _KEYCODE_ROLES;

        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 major, ) = roles.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([1, 1]));

        ROLES = roles;

        return dependencies;
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory) {
        // No permissions: the facility is called directly, gated on this policy's address.
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== QUEUE ========== //

    /// @inheritdoc IYRFManagerTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_manager` role.
    ///      - The facility slot has not been set.
    function queueSetYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                _requireFacility(),
                IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
                abi.encode(vault_, newShare_)
            );
    }

    /// @inheritdoc IYRFManagerTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_manager` role.
    ///      - The facility slot has not been set.
    function queueSetInitialDiscount(
        uint256 initialDiscount_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                _requireFacility(),
                IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
                abi.encode(initialDiscount_)
            );
    }

    /// @inheritdoc IYRFManagerTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_manager` role.
    ///      - The facility slot has not been set.
    function queueEnableAsset(address vault_) external override returns (uint64 actionId) {
        return
            _queueAction(
                _requireFacility(),
                IYieldRepurchaseFacilityV2.enableAsset.selector,
                abi.encode(vault_)
            );
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @inheritdoc TimelockBatchQueue
    /// @dev Validates the proposer role and the (target, selector) pair.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_manager` role.
    ///      - The target is not the current facility.
    ///      - The selector is not one of the supported facility mutators.
    function _onSubActionQueued(
        address caller_,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        _requireEnabled();
        _requireRole(caller_, YRF_MANAGER_ROLE);

        if (action_.target == address(0) || action_.target != facility)
            _revertActionInvalid(action_.target, action_.selector);

        _requireSupportedSelector(action_.target, action_.selector);
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Execution is permissionless once the timelock elapses; this hook only enforces
    ///      enabled status. The proposer was authorized at queue time by `_onSubActionQueued`,
    ///      and requiring an execution role would let an unavailable or compromised executor
    ///      block already-approved changes.
    ///
    ///      Disabling the policy suspends execution but does not clear the queue: queued actions
    ///      remain in storage and become executable again once the policy is re-enabled, for as
    ///      long as their execution windows have not expired. Before re-enabling, the emergency
    ///      role must therefore cancel every queued action that should not survive the disable.
    ///
    ///      Reverts if the policy is disabled.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireEnabled();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Cancellation is restricted to the emergency role. Intentionally permitted while
    ///      the policy is disabled so that stale or unwanted queued actions can be cleared before
    ///      the policy is re-enabled.
    ///
    ///      Reverts if the caller does not hold the emergency role.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Asserts the facility slot still holds the address the action was queued against,
    ///      then dispatches the call by selector. The value invariants of the facility are not
    ///      re-checked here; the facility reverts the batch if the queued values are invalid.
    ///
    ///      Reverts if:
    ///      - The facility slot no longer holds the queued facility.
    ///      - The selector is not one of the supported facility mutators.
    ///      - The facility reverts the dispatched call.
    function _executeSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        address currentFacility = facility;
        if (action_.target != currentFacility)
            revert IYRFManagerTimelock_FacilityStale(
                actionId_,
                index_,
                action_.target,
                currentFacility
            );

        IYieldRepurchaseFacilityV2 yrf = IYieldRepurchaseFacilityV2(currentFacility);
        bytes4 sel = action_.selector;

        if (sel == IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector) {
            (address vault, uint256 newShare) = abi.decode(action_.payload, (address, uint256));
            yrf.setYieldBuybackShare(vault, newShare);
        } else if (sel == IYieldRepurchaseFacilityV2.setInitialDiscount.selector) {
            yrf.setInitialDiscount(abi.decode(action_.payload, (uint256)));
        } else if (sel == IYieldRepurchaseFacilityV2.enableAsset.selector) {
            yrf.enableAsset(abi.decode(action_.payload, (address)));
        } else {
            _revertActionInvalid(action_.target, sel);
        }
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

    // ========== CONFIGURATION ========== //

    /// @inheritdoc IYRFManagerTimelock
    /// @dev The setter exists so that the facility, which pins this policy as its immutable
    ///      manager timelock, can be wired after this policy is deployed.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the `admin` role.
    ///      - `facility_` is the zero address.
    function setFacility(address facility_) external override onlyAdminRole {
        _setFacility(facility_);
    }

    /// @inheritdoc IYRFManagerTimelock
    /// @dev Already-queued actions keep the delay they were queued with. The admin role is
    ///      expected to be held only by the OCG timelock, so the change is de-facto
    ///      timelocked.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the `admin` role.
    ///      - `delay_` is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`.
    function setTimelockDelay(uint48 delay_) external override onlyAdminRole {
        _setTimelockDelay(delay_);
    }

    // ========== HELPERS ========== //

    /// @notice Sets the facility.
    function _setFacility(address facility_) private {
        _requireNonzeroAddress(facility_, "facility");

        facility = facility_;
        emit FacilitySet(facility_);
    }

    /// @notice Returns the facility slot, reverting if it has not been set.
    function _requireFacility() private view returns (address facility_) {
        facility_ = facility;
        if (facility_ == address(0)) revert IYRFManagerTimelock_FacilityNotSet();
    }

    /// @notice Reverts unless the selector is one of the supported facility mutators.
    function _requireSupportedSelector(address target_, bytes4 selector_) private pure {
        if (
            selector_ != IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector &&
            selector_ != IYieldRepurchaseFacilityV2.setInitialDiscount.selector &&
            selector_ != IYieldRepurchaseFacilityV2.enableAsset.selector
        ) _revertActionInvalid(target_, selector_);
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert IYRFManagerTimelock_InvalidAddress(parameter_);
    }

    /// @notice Reverts for an unsupported action.
    function _revertActionInvalid(address target_, bytes4 selector_) private pure {
        revert ITimelockBatchQueue_ActionInvalid(target_, selector_);
    }

    // ========== ERC-165 ========== //

    /// @notice Queries if a contract implements an interface.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, TimelockBatchQueue) returns (bool) {
        return
            interfaceId_ == type(IYRFManagerTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IPolicyAdmin).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
