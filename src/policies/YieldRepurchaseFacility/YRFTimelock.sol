// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYRFTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {EMERGENCY_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @title YRFTimelock
/// @notice Timelock policy that owns the operational parameters of a
///         YieldRepurchaseFacilityV2 on behalf of the `yrf_admin` role.
/// @dev The policy is intended to be pinned as the facility's immutable timelock. In that
///      deployment shape the facility's `setYieldBuybackShare`, `setInitialDiscount`,
///      `enableAsset`, `disableAsset`, `excludeClearinghouse`, `increaseClearinghouseOffset`,
///      and `decreaseNextYield` are reachable either through the queue exposed here or
///      directly by the admin (expected to be held only by the OCG timelock).
///
///      Every queue entry point validates the queued action against the live facility
///      state, so an action that would revert on the facility cannot be queued. The
///      overwrite setters `setYieldBuybackShare` and `setInitialDiscount` are additionally
///      bound to the parameter value observed at queue time: execution reverts with
///      `IYRFTimelock_PreStateChanged` when the live value no longer matches, and at most
///      one update per parameter can be pending at a time. The other facility functions are
///      re-validated by the facility itself at execution: the asset and Clearinghouse state
///      flips revert when re-applied, `decreaseNextYield` is compare-and-set, and offset
///      increases are checked against the live receivables.
///
///      Authorization maps to the existing roles: `yrf_admin` is the sole queue proposer
///      and may re-enable the policy within the grace window after a disable, `emergency` is
///      the sole canceller, and `admin` owns the policy's own configuration. Execution is
///      permissionless once a timelock elapses.
///
///      Disabling the policy suspends queueing and execution but does not clear queued
///      actions or their pending parameter slots; before re-enabling, the emergency role must
///      cancel any queued action that should not become executable again.
contract YRFTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    TimelockBatchQueue,
    IYRFTimelock,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @inheritdoc IYRFTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc IYRFTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc IYRFTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    /// @inheritdoc IYRFTimelock
    uint32 public constant override MAX_GRACE_PERIOD = 7 days;

    /// @notice The facility's scale of the yield buyback share and the initial discount.
    uint256 internal constant _ONE_HUNDRED_PERCENT = 1e18;

    /// @notice Expected `abi.encode` payload lengths of the supported selectors, named by
    ///         parameter types.
    uint256 internal constant _LEN_ADDRESS = 32;
    uint256 internal constant _LEN_UINT256 = 32;
    uint256 internal constant _LEN_ADDRESS_UINT256 = 64;
    uint256 internal constant _LEN_ADDRESS_UINT256_UINT256 = 96;

    /// @notice Pre-computed keycode for the ROLES module dependency.
    /// @dev Avoids the runtime cost of `toKeycode("ROLES")` at the call site.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524F4C4553); // toKeycode("ROLES")

    // ========== STATE ========== //

    /// @inheritdoc IYRFTimelock
    address public override facility;

    /// @notice Hash of the facility parameter state a sub-action was validated against at
    ///         queue time, recorded for the pre-state bound selectors.
    mapping(uint64 actionId => mapping(uint256 index => bytes32 expectedHash))
        internal _expectedPreStateHashes;

    /// @notice The pending parameter slot key held by a sub-action, recorded for the
    ///         pre-state bound selectors.
    /// @dev Stored per sub-action so that cancellation can release the slot after the base
    ///      contract has already cleared the sub-actions from storage.
    mapping(uint64 actionId => mapping(uint256 index => bytes32 lockKey)) internal _lockKeys;

    /// @notice The queued action currently holding a parameter's pending slot.
    /// @dev A held slot rejects further queueing of the same parameter until the holder is
    ///      executed or cancelled.
    mapping(bytes32 lockKey => uint64 actionId) internal _pendingActionIds;

    // ========== INITIALIZATION ========== //

    /// @dev Wire the facility after deployment with `setFacility`.
    ///
    ///      Reverts if:
    ///      - The kernel is the zero address.
    ///      - The initial delay is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`.
    ///      - The grace period is zero or not less than `MAX_GRACE_PERIOD`.
    /// @param kernel_ The Olympus Kernel.
    /// @param initialTimelockDelay_ The initial timelock delay.
    /// @param gracePeriod_ The initial re-enable grace window, in seconds.
    constructor(
        Kernel kernel_,
        uint48 initialTimelockDelay_,
        uint32 gracePeriod_
    ) Policy(kernel_) ReEnablerGracePeriod(gracePeriod_) TimelockBatchQueue(initialTimelockDelay_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireValidGracePeriod(gracePeriod_);

        // EnablerV2 starts disabled.
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = _KEYCODE_ROLES;

        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 major, ) = roles.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([1]));

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

    // ========== VIEW ========== //

    /// @inheritdoc IYRFTimelock
    function pendingYieldBuybackShareActionId(
        address vault_
    ) external view override returns (uint64 actionId) {
        return _pendingActionIds[_yieldBuybackShareLockKey(vault_)];
    }

    /// @inheritdoc IYRFTimelock
    function pendingInitialDiscountActionId() external view override returns (uint64 actionId) {
        return _pendingActionIds[_initialDiscountLockKey()];
    }

    // ========== QUEUE ========== //

    /// @inheritdoc IYRFTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - The vault is not registered in the facility.
    ///      - `newShare_` exceeds 100% (`1e18`).
    ///      - Another yield buyback share update for `vault_` is already pending.
    function queueSetYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                facility,
                IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
                abi.encode(vault_, newShare_)
            );
    }

    /// @inheritdoc IYRFTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - `initialDiscount_` is not less than 100% (`1e18`).
    ///      - Another initial discount update is already pending.
    function queueSetInitialDiscount(
        uint256 initialDiscount_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                facility,
                IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
                abi.encode(initialDiscount_)
            );
    }

    /// @inheritdoc IYRFTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - The vault is not registered in the facility.
    ///      - The vault is already enabled.
    function queueEnableAsset(address vault_) external override returns (uint64 actionId) {
        return
            _queueAction(
                facility,
                IYieldRepurchaseFacilityV2.enableAsset.selector,
                abi.encode(vault_)
            );
    }

    /// @inheritdoc IYRFTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - The vault is not registered in the facility.
    ///      - The vault is already disabled.
    ///      - The vault is the backing vault.
    function queueDisableAsset(address vault_) external override returns (uint64 actionId) {
        return
            _queueAction(
                facility,
                IYieldRepurchaseFacilityV2.disableAsset.selector,
                abi.encode(vault_)
            );
    }

    /// @inheritdoc IYRFTimelock
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - The Clearinghouse is not included in the backing yield.
    function queueExcludeClearinghouse(
        address clearinghouse_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                facility,
                IYieldRepurchaseFacilityV2.excludeClearinghouse.selector,
                abi.encode(clearinghouse_)
            );
    }

    /// @inheritdoc IYRFTimelock
    /// @dev The receivables bound is re-checked by the facility at execution against the
    ///      live value, so repayments during the delay can revert the execution; the action
    ///      is then cancelled and re-queued with a smaller offset.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - `clearinghouse_` is the zero address.
    ///      - The resulting offset exceeds the Clearinghouse's current
    ///        `principalReceivables`.
    function queueIncreaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                facility,
                IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector,
                abi.encode(clearinghouse_, additionalOffset_)
            );
    }

    /// @inheritdoc IYRFTimelock
    /// @dev The facility re-checks the compare-and-set at execution, so a weekly reset that
    ///      replaces the stored value during the delay makes the queued correction revert
    ///      instead of cutting the fresh value.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - The vault is not registered in the facility.
    ///      - `expectedNextYield_` does not match the stored next yield.
    ///      - `newNextYield_` is not lower than the stored next yield.
    function queueDecreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                facility,
                IYieldRepurchaseFacilityV2.decreaseNextYield.selector,
                abi.encode(vault_, expectedNextYield_, newNextYield_)
            );
    }

    /// @inheritdoc IYRFTimelock
    /// @dev Sub-actions are validated independently against the live facility state; the
    ///      effect of an earlier sub-action within the batch is not projected onto the
    ///      validation of a later one. A later sub-action that requires the effect of an
    ///      earlier one therefore fails validation at queue time (e.g. disabling and
    ///      re-enabling the same vault cannot be batched), and one invalidated by an
    ///      earlier one's effect reverts the entire batch at execution.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - The batch is empty or exceeds the maximum batch size.
    ///      - Any sub-action targets an address other than the facility.
    ///      - Any sub-action uses an unsupported selector or a malformed payload.
    ///      - Any sub-action fails the validation of its typed queue helper.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external override returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @inheritdoc TimelockBatchQueue
    /// @dev Validates the proposer role and the sub-action against the live facility state,
    ///      and records the pre-state binding for the overwrite setters.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the `yrf_admin` role.
    ///      - The facility slot has not been set.
    ///      - The target is not the current facility.
    ///      - The selector is not one of the supported facility mutators.
    ///      - The payload length does not match the selector's parameter types.
    ///      - The decoded parameters fail the selector-specific validation.
    function _onSubActionQueued(
        address caller_,
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        _requireEnabled();
        _requireRole(caller_, YRF_ADMIN_ROLE);

        address currentFacility = _requireFacility();
        if (action_.target != currentFacility)
            _revertActionInvalid(action_.target, action_.selector);

        _validateQueuedFacilityAction(actionId_, index_, action_);
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Execution is permissionless once the timelock elapses; this hook only enforces
    ///      that this policy is enabled. The proposer was authorized at queue time by
    ///      `_onSubActionQueued`, and requiring an execution role would let an unavailable or
    ///      compromised executor block already-approved changes.
    ///
    ///      The facility's enabled state is intentionally not checked: the facility's
    ///      operational functions are callable while the facility is disabled, and executing
    ///      a queued action during a facility downtime (for example an offset increase ahead
    ///      of a re-enable) is a supported recovery path.
    ///
    ///      Disabling this policy suspends execution but does not clear the queue: queued
    ///      actions remain in storage and become executable again once the policy is
    ///      re-enabled, for as long as their execution windows have not expired. Before
    ///      re-enabling, the emergency role must therefore cancel every queued action that
    ///      should not survive the disable.
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
    ///      the policy is disabled so that stale or unwanted queued actions can be cleared
    ///      before the policy is re-enabled.
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
    /// @dev Releases the pre-state bindings and pending parameter slots recorded at queue
    ///      time, so a cancelled action stops blocking new updates of the same parameters.
    function _onActionCancelled(uint64 actionId_, uint256 subActionCount_) internal override {
        for (uint256 i = 0; i < subActionCount_; ++i) {
            _clearSubActionState(actionId_, i);
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Asserts the facility slot still holds the address the action was queued against,
    ///      re-checks the pre-state binding for the overwrite setters, releases the recorded
    ///      per-sub-action state, and dispatches the call by selector. The remaining value
    ///      invariants are enforced by the facility itself, so a queued action invalidated by
    ///      state drift reverts inside the facility and rolls back the entire batch.
    ///
    ///      Reverts if:
    ///      - The facility slot no longer holds the queued facility.
    ///      - The pre-state bound parameter no longer matches its queue-time value.
    ///      - The selector is not one of the supported facility mutators.
    ///      - The facility reverts the dispatched call.
    function _executeSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        address currentFacility = facility;
        if (action_.target != currentFacility)
            revert IYRFTimelock_FacilityStale(actionId_, index_, action_.target, currentFacility);

        IYieldRepurchaseFacilityV2 yrf = IYieldRepurchaseFacilityV2(currentFacility);
        bytes4 sel = action_.selector;

        if (sel == IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector) {
            (address vault, uint256 newShare) = abi.decode(action_.payload, (address, uint256));
            _validatePreState(
                actionId_,
                index_,
                keccak256(abi.encode(vault, yrf.getAssetConfig(vault).yieldBuybackShare))
            );
            _clearSubActionState(actionId_, index_);
            yrf.setYieldBuybackShare(vault, newShare);
        } else if (sel == IYieldRepurchaseFacilityV2.setInitialDiscount.selector) {
            uint256 initialDiscount = abi.decode(action_.payload, (uint256));
            _validatePreState(actionId_, index_, keccak256(abi.encode(yrf.initialDiscount())));
            _clearSubActionState(actionId_, index_);
            yrf.setInitialDiscount(initialDiscount);
        } else if (sel == IYieldRepurchaseFacilityV2.enableAsset.selector) {
            yrf.enableAsset(abi.decode(action_.payload, (address)));
        } else if (sel == IYieldRepurchaseFacilityV2.disableAsset.selector) {
            yrf.disableAsset(abi.decode(action_.payload, (address)));
        } else if (sel == IYieldRepurchaseFacilityV2.excludeClearinghouse.selector) {
            yrf.excludeClearinghouse(abi.decode(action_.payload, (address)));
        } else if (sel == IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector) {
            (address clearinghouse, uint256 additionalOffset) = abi.decode(
                action_.payload,
                (address, uint256)
            );
            yrf.increaseClearinghouseOffset(clearinghouse, additionalOffset);
        } else if (sel == IYieldRepurchaseFacilityV2.decreaseNextYield.selector) {
            (address vault, uint256 expectedNextYield, uint256 newNextYield) = abi.decode(
                action_.payload,
                (address, uint256, uint256)
            );
            yrf.decreaseNextYield(vault, expectedNextYield, newNextYield);
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

    // ========== REENABLER HOOKS ========== //

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev The re-enable is restricted to the yrf_admin, the operational role of this
    ///      policy; the admin restarts through `enable` instead. The grace-period deadline is
    ///      enforced by `ReEnablerGracePeriod` before the policy is re-enabled.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the yrf_admin role.
    function _authorizeReEnable() internal view override {
        _requireRole(msg.sender, YRF_ADMIN_ROLE);
    }

    /// @notice Authorizes a grace-period update.
    /// @dev The admin role is expected to be held only by the OCG timelock, so the grace
    ///      window is de-facto timelocked.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    // ========== CONFIGURATION ========== //

    /// @inheritdoc IYRFTimelock
    /// @dev The setter exists so that the facility, which pins this policy as its immutable
    ///      timelock, can be wired after this policy is deployed. Rotating the slot makes
    ///      every action queued against the previous facility revert with
    ///      `IYRFTimelock_FacilityStale` at execution. The pending parameter slots of the
    ///      overwrite setters are keyed by parameter, not by facility, so a stale action
    ///      keeps holding its slot until it is cancelled.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the `admin` role.
    ///      - `facility_` is the zero address.
    ///      - `facility_` does not advertise `IYieldRepurchaseFacilityV2` support through
    ///        ERC165.
    ///      - `facility_` does not pin this policy as its timelock.
    function setFacility(address facility_) external override onlyAdminRole {
        _requireNonzeroAddress(facility_, "facility");
        if (
            !ERC165Checker.supportsInterface(
                facility_,
                type(IYieldRepurchaseFacilityV2).interfaceId
            ) || IYieldRepurchaseFacilityV2(facility_).timelock() != address(this)
        ) revert IYRFTimelock_InvalidFacility(facility_);

        facility = facility_;
        emit FacilitySet(facility_);
    }

    /// @inheritdoc IYRFTimelock
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

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Bounds the window: the grace period must be strictly shorter than one weekly
    ///      cycle of the facility (`MAX_GRACE_PERIOD`).
    ///
    ///      Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - `period_` is zero.
    ///      - `period_` is not less than `MAX_GRACE_PERIOD`.
    function setGracePeriod(uint32 period_) public override givenEnabled {
        _requireValidGracePeriod(period_);
        super.setGracePeriod(period_);
    }

    // ========== VALIDATION ========== //

    /// @notice Validates a queued sub-action against the live facility state and records the
    ///         pre-state binding for the overwrite setters.
    /// @dev The checks mirror the facility's own execution-time checks, so a queued action
    ///      can only be invalidated by state that changes between queue and execution.
    ///      Value-bound failures revert with the facility's error types; a malformed payload
    ///      reverts with `ITimelockBatchQueue_ActionInvalid` and a zero clearinghouse with
    ///      `IYRFTimelock_InvalidAddress`.
    function _validateQueuedFacilityAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) private {
        IYieldRepurchaseFacilityV2 yrf = IYieldRepurchaseFacilityV2(action_.target);
        bytes4 selector = action_.selector;

        if (selector == IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS_UINT256, selector);
            (address vault, uint256 newShare) = abi.decode(action_.payload, (address, uint256));
            IYieldRepurchaseFacilityV2.ReserveAsset memory config = _requireRegisteredAsset(
                yrf,
                vault
            );
            if (newShare > _ONE_HUNDRED_PERCENT)
                revert IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();
            _recordPreState(
                actionId_,
                index_,
                selector,
                _yieldBuybackShareLockKey(vault),
                keccak256(abi.encode(vault, config.yieldBuybackShare))
            );
            return;
        }

        if (selector == IYieldRepurchaseFacilityV2.setInitialDiscount.selector) {
            _requirePayloadLength(action_.payload, _LEN_UINT256, selector);
            uint256 initialDiscount = abi.decode(action_.payload, (uint256));
            if (initialDiscount >= _ONE_HUNDRED_PERCENT)
                revert IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_InitialDiscountTooHigh();
            _recordPreState(
                actionId_,
                index_,
                selector,
                _initialDiscountLockKey(),
                keccak256(abi.encode(yrf.initialDiscount()))
            );
            return;
        }

        if (selector == IYieldRepurchaseFacilityV2.enableAsset.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS, selector);
            address vault = abi.decode(action_.payload, (address));
            IYieldRepurchaseFacilityV2.ReserveAsset memory config = _requireRegisteredAsset(
                yrf,
                vault
            );
            if (config.isAssetEnabled)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetEnabled();
            return;
        }

        if (selector == IYieldRepurchaseFacilityV2.disableAsset.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS, selector);
            address vault = abi.decode(action_.payload, (address));
            IYieldRepurchaseFacilityV2.ReserveAsset memory config = _requireRegisteredAsset(
                yrf,
                vault
            );
            if (!config.isAssetEnabled)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled();
            if (vault == yrf.backingVault())
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultIsBackingVault();
            return;
        }

        if (selector == IYieldRepurchaseFacilityV2.excludeClearinghouse.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS, selector);
            address clearinghouse = abi.decode(action_.payload, (address));
            if (!yrf.isClearinghouseIncluded(clearinghouse))
                revert IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded();
            return;
        }

        if (selector == IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS_UINT256, selector);
            (address clearinghouse, uint256 additionalOffset) = abi.decode(
                action_.payload,
                (address, uint256)
            );
            _requireNonzeroAddress(clearinghouse, "clearinghouse");
            uint256 newOffset = yrf.clearinghouseOffset(clearinghouse) + additionalOffset;
            uint256 receivables = _readClearinghousePrincipal(clearinghouse);
            if (newOffset > receivables)
                revert IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_OffsetExceedsReceivables(
                        clearinghouse,
                        newOffset,
                        receivables
                    );
            return;
        }

        if (selector == IYieldRepurchaseFacilityV2.decreaseNextYield.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS_UINT256_UINT256, selector);
            (address vault, uint256 expectedNextYield, uint256 newNextYield) = abi.decode(
                action_.payload,
                (address, uint256, uint256)
            );
            IYieldRepurchaseFacilityV2.ReserveAsset memory config = _requireRegisteredAsset(
                yrf,
                vault
            );
            if (config.nextYield != expectedNextYield)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldMismatch(
                    vault,
                    expectedNextYield,
                    config.nextYield
                );
            if (newNextYield >= config.nextYield)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldNotDecreased(
                    vault,
                    newNextYield,
                    config.nextYield
                );
            return;
        }

        _revertActionInvalid(action_.target, selector);
    }

    // ========== HELPERS ========== //

    /// @notice Records the pre-state binding of an overwrite setter sub-action and takes the
    ///         parameter's pending slot.
    /// @dev Reverts with `IYRFTimelock_ConflictingActionPending` if the slot is already held
    ///      by a queued action, including an earlier sub-action of the batch being queued.
    function _recordPreState(
        uint64 actionId_,
        uint256 index_,
        bytes4 selector_,
        bytes32 lockKey_,
        bytes32 expectedHash_
    ) private {
        uint64 pendingActionId = _pendingActionIds[lockKey_];
        if (pendingActionId != 0)
            revert IYRFTimelock_ConflictingActionPending(selector_, pendingActionId);

        _pendingActionIds[lockKey_] = actionId_;
        _lockKeys[actionId_][index_] = lockKey_;
        _expectedPreStateHashes[actionId_][index_] = expectedHash_;
    }

    /// @notice Reverts unless the live pre-state hash matches the hash captured at queue
    ///         time.
    function _validatePreState(
        uint64 actionId_,
        uint256 index_,
        bytes32 currentHash_
    ) private view {
        bytes32 expectedHash = _expectedPreStateHashes[actionId_][index_];
        if (expectedHash != currentHash_)
            revert IYRFTimelock_PreStateChanged(actionId_, index_, expectedHash, currentHash_);
    }

    /// @notice Clears the pre-state binding of a sub-action and releases its pending
    ///         parameter slot, if any.
    function _clearSubActionState(uint64 actionId_, uint256 index_) private {
        bytes32 lockKey = _lockKeys[actionId_][index_];
        if (lockKey == bytes32(0)) return;

        delete _lockKeys[actionId_][index_];
        delete _pendingActionIds[lockKey];
        delete _expectedPreStateHashes[actionId_][index_];
    }

    /// @notice Returns the pending slot key of the vault's yield buyback share.
    function _yieldBuybackShareLockKey(address vault_) private pure returns (bytes32) {
        return
            keccak256(abi.encode(IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector, vault_));
    }

    /// @notice Returns the pending slot key of the initial discount.
    function _initialDiscountLockKey() private pure returns (bytes32) {
        return keccak256(abi.encode(IYieldRepurchaseFacilityV2.setInitialDiscount.selector));
    }

    /// @notice Returns the facility's config of a registered vault, reverting for an
    ///         unregistered one.
    /// @dev The facility's `getAssetConfig` itself reverts for an unregistered vault; the
    ///      zero-check guards against an implementation that returns an empty config instead.
    function _requireRegisteredAsset(
        IYieldRepurchaseFacilityV2 yrf_,
        address vault_
    ) private view returns (IYieldRepurchaseFacilityV2.ReserveAsset memory config) {
        config = yrf_.getAssetConfig(vault_);
        if (config.vault == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered(vault_);
    }

    /// @notice Reads the Clearinghouse's `principalReceivables`, treating a revert as zero.
    /// @dev Mirrors the facility's read, so that the queue-time offset bound matches the
    ///      execution-time bound.
    function _readClearinghousePrincipal(address clearinghouse_) private view returns (uint256) {
        try IGenericClearinghouse(clearinghouse_).principalReceivables() returns (
            uint256 receivables
        ) {
            return receivables;
        } catch {
            return 0;
        }
    }

    /// @notice Reverts unless the payload has the exact `abi.encode` length of the selector's
    ///         parameter types.
    /// @dev The zero target in the error marks a payload shape failure, distinguishing it
    ///      from a target or selector failure.
    function _requirePayloadLength(
        bytes memory payload_,
        uint256 expectedLength_,
        bytes4 selector_
    ) private pure {
        if (payload_.length != expectedLength_)
            revert ITimelockBatchQueue_ActionInvalid(address(0), selector_);
    }

    /// @notice Returns the facility slot, reverting if it has not been set.
    function _requireFacility() private view returns (address facility_) {
        facility_ = facility;
        if (facility_ == address(0)) revert IYRFTimelock_FacilityNotSet();
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert IYRFTimelock_InvalidAddress(parameter_);
    }

    /// @notice Reverts unless the grace window is strictly shorter than `MAX_GRACE_PERIOD`.
    function _requireValidGracePeriod(uint32 period_) private pure {
        if (period_ >= MAX_GRACE_PERIOD) revert GracePeriod_TooLong();
    }

    /// @notice Reverts for an unsupported action.
    function _revertActionInvalid(address target_, bytes4 selector_) private pure {
        revert ITimelockBatchQueue_ActionInvalid(target_, selector_);
    }

    // ========== ERC-165 ========== //

    /// @notice Queries if a contract implements an interface.
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        virtual
        override(EnablerV2, ReEnablerGracePeriod, TimelockBatchQueue)
        returns (bool)
    {
        return
            interfaceId_ == type(IYRFTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
