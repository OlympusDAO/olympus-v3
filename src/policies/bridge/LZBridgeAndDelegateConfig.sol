// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.30;

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title  LZBridgeAndDelegateConfig
/// @notice Timelock policy that owns LayerZero bridge configuration on behalf of an
///         LZBridgeGateway, LZEndpointDelegate, and periphery LZCrossChainBridge triple.
/// @dev The policy is intended to hold the `bridge_configurator` role on the
///      gateway/delegate and to be pinned as the periphery bridge's `configurator`. The
///      `queue` entry point packs one or more gateway/delegate/facilitator sub-actions into
///      a single atomic timelock entry; each sub-action's proposer role and payload shape is
///      validated at queue time and dispatched at execution time via a typed call against
///      the configured target. The policy's own configuration (target slots, timelock delay)
///      is managed through the typed `queueSetTarget*` and `queueSetTimelockDelay` helpers;
///      `queue` deliberately rejects self-targeted sub-actions so that these privileged
///      rotations cannot be smuggled into an arbitrary batch. Cancellation is gated to the
///      emergency role only, so the proposer cannot rescind its own queued action; the
///      emergency role is intended for a multisig veto independent of the proposer roles.
contract LZBridgeAndDelegateConfig is
    Policy,
    PolicyEnablerV2,
    TimelockBatchQueue,
    ILZBridgeAndDelegateConfig,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @inheritdoc ILZBridgeAndDelegateConfig
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc ILZBridgeAndDelegateConfig
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc ILZBridgeAndDelegateConfig
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    /// @notice Pre-computed keycode for the ROLES module dependency.
    /// @dev Avoids the runtime cost of `toKeycode("ROLES")` at the call site.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524F4C4553); // toKeycode("ROLES")

    // ========== STATE ========== //

    /// @inheritdoc ILZBridgeAndDelegateConfig
    address public override gateway;

    /// @inheritdoc ILZBridgeAndDelegateConfig
    address public override delegate;

    /// @inheritdoc ILZBridgeAndDelegateConfig
    address public override facilitator;

    // ========== INITIALIZATION ========== //

    /// @dev Reverts if any address argument is zero or the initial delay is outside
    ///      `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`.
    /// @param kernel_ Bophades kernel.
    /// @param gateway_ LZBridgeGateway to manage.
    /// @param delegate_ LZEndpointDelegate to manage.
    /// @param facilitator_ Periphery LZCrossChainBridge to manage.
    /// @param initialTimelockDelay_ Initial timelock delay; validated by `_validateTimelockDelay`.
    constructor(
        Kernel kernel_,
        address gateway_,
        address delegate_,
        address facilitator_,
        uint48 initialTimelockDelay_
    ) Policy(kernel_) TimelockBatchQueue(initialTimelockDelay_) {
        _requireNonzeroAddress(address(kernel_), "kernel");
        _requireNonzeroAddress(gateway_, "gateway");
        _requireNonzeroAddress(delegate_, "delegate");
        _requireNonzeroAddress(facilitator_, "facilitator");

        _setTargetGateway(gateway_);
        _setTargetDelegate(delegate_);
        _setTargetFacilitator(facilitator_);

        // EnablerV2 starts disabled
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = _KEYCODE_ROLES;

        ROLESv1 roles = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 major, ) = roles.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([1, 1]));

        ROLES = roles;
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory) {
        // No permissions
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== QUEUE: SELF ========== //

    /// @inheritdoc ILZBridgeAndDelegateConfig
    /// @dev Reverts if:
    ///      - The policy is disabled
    ///      - The caller does not have the `admin` role
    ///      - `newGateway_` is the zero address
    function queueSetTargetGateway(
        address newGateway_
    ) external override returns (uint64 actionId_) {
        return
            _queueAction(
                address(this),
                this.queueSetTargetGateway.selector,
                abi.encode(newGateway_)
            );
    }

    /// @inheritdoc ILZBridgeAndDelegateConfig
    /// @dev Reverts if:
    ///      - The policy is disabled
    ///      - The caller does not have the `admin` role
    ///      - `newDelegate_` is the zero address
    function queueSetTargetDelegate(
        address newDelegate_
    ) external override returns (uint64 actionId_) {
        return
            _queueAction(
                address(this),
                this.queueSetTargetDelegate.selector,
                abi.encode(newDelegate_)
            );
    }

    /// @inheritdoc ILZBridgeAndDelegateConfig
    /// @dev Reverts if:
    ///      - The policy is disabled
    ///      - The caller does not have the `admin` role
    ///      - `newFacilitator_` is the zero address
    function queueSetTargetFacilitator(
        address newFacilitator_
    ) external override returns (uint64 actionId_) {
        return
            _queueAction(
                address(this),
                this.queueSetTargetFacilitator.selector,
                abi.encode(newFacilitator_)
            );
    }

    /// @inheritdoc ILZBridgeAndDelegateConfig
    /// @dev Reverts if:
    ///      - The policy is disabled
    ///      - The caller does not have the `admin` role
    ///      - `delay_` is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`
    function queueSetTimelockDelay(uint48 delay_) external override returns (uint64 actionId_) {
        return _queueAction(address(this), this.queueSetTimelockDelay.selector, abi.encode(delay_));
    }

    // ========== QUEUE: BATCH ========== //

    /// @inheritdoc ILZBridgeAndDelegateConfig
    /// @dev Reverts if:
    ///      - The policy is disabled
    ///      - The batch is empty
    ///      - The batch exceeds the maximum batch size
    ///      - Any sub-action targets this policy (self-actions must use the typed
    ///        `queueSetTarget*` / `queueSetTimelockDelay` helpers)
    ///      - Any sub-action target is not the gateway, delegate, or facilitator
    ///      - The caller does not hold the proposer role required by any sub-action
    ///      - Any sub-action payload cannot be decoded into the expected types
    function queue(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external override returns (uint64 actionId_) {
        uint256 len = actions_.length;
        // `_queueAction` re-checks these, but the size bounds are duplicated here so the
        // self-target rejection below cannot mask an empty or oversize batch: the revert
        // ordering stays deterministic (empty -> too large -> self-target -> per-sub).
        if (len == 0) revert ITimelockBatchQueue_BatchEmpty();
        if (len > _maxBatchSize()) revert ITimelockBatchQueue_BatchTooLarge(len, _maxBatchSize());
        for (uint256 i; i < len; ++i) {
            if (actions_[i].target == address(this))
                revert ITimelockBatchQueue_ActionInvalid(actions_[i].target, actions_[i].selector);
        }
        return _queueAction(actions_);
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @inheritdoc TimelockBatchQueue
    /// @dev Validates the proposer's role and the (target, selector, payload) triple against
    ///      the supported action table.
    ///
    ///      Reverts if:
    ///      - The policy is disabled
    ///      - The action's target is unknown
    ///      - The proposer lacks the role required by the action
    ///      - The payload cannot be decoded into the expected types for the action
    function _validateSubAction(
        address caller_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        _requireEnabled();

        if (action_.target == gateway) {
            _validateGatewaySubAction(caller_, action_);
        } else if (action_.target == delegate) {
            _validateDelegateSubAction(caller_, action_);
        } else if (action_.target == facilitator) {
            _validateFacilitatorSubAction(caller_, action_);
        } else if (action_.target == address(this)) {
            _validateSelfSubAction(caller_, action_);
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Execution is permissionless once the timelock elapses; this hook only enforces
    ///      enabled status. The proposer was authorized at queue time by `_validateSubAction`,
    ///      and requiring an execution role would let an unavailable or compromised executor
    ///      block already-approved changes. Target/selector validity is not re-checked: targets
    ///      are fixed storage slots rotated only through their own timelocked actions, and a
    ///      queued sub-action stays bound to the address the timelock originally approved.
    ///      Undesirable queued actions are cleared via emergency cancellation.
    ///
    ///      Reverts if:
    ///      - The policy is disabled
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction memory
    ) internal view override {
        _requireEnabled();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Cancellation is restricted to the emergency role; the proposer cannot rescind
    ///      its own queued action. Intentionally permitted while the policy is disabled so
    ///      stale or malicious queued actions can be cleared.
    ///
    ///      Reverts if:
    ///      - The caller does not have the emergency role
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction memory
    ) internal view override {
        if (!_isEmergency(caller_)) revert ROLESv1.ROLES_RequireRole(EMERGENCY_ROLE);
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev The payload-shape checks performed at queue time are deliberately not re-run here,
    ///      since storage already holds the queued action and ABI decoding will revert on mismatch.
    ///
    ///      Reverts if:
    ///      - The (target, selector) pair is not supported.
    function _executeSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        if (action_.target == gateway) {
            _executeGatewaySubAction(action_);
        } else if (action_.target == delegate) {
            _executeDelegateSubAction(action_);
        } else if (action_.target == facilitator) {
            _executeFacilitatorSubAction(action_);
        } else if (action_.target == address(this)) {
            _executeSelfSubAction(action_);
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
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

    // ========== ERC-165 ========== //

    /// @notice Query if a contract implements an interface.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, TimelockBatchQueue) returns (bool) {
        return
            interfaceId_ == type(ILZBridgeAndDelegateConfig).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IPolicyAdmin).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ========== PROPOSER-ROLE HELPERS ========== //

    /// @notice Requires the caller to hold `bridge_admin` or `admin`.
    function _requireBridgeAdminProposer(address caller_) private view {
        if (!_hasRole(caller_, BRIDGE_ADMIN_ROLE) && !_isAdmin(caller_))
            revert IPolicyAdmin.NotAuthorised();
    }

    /// @notice Requires the caller to hold `bridge_rate_limiter`, `bridge_admin`, or `admin`.
    function _requireRateLimiterProposer(address caller_) private view {
        if (
            !_hasRole(caller_, BRIDGE_RATE_LIMITER_ROLE) &&
            !_hasRole(caller_, BRIDGE_ADMIN_ROLE) &&
            !_isAdmin(caller_)
        ) revert IPolicyAdmin.NotAuthorised();
    }

    /// @notice Requires the caller to hold `admin`.
    function _requireAdminProposer(address caller_) private view {
        if (!_isAdmin(caller_)) revert ROLESv1.ROLES_RequireRole(ADMIN_ROLE);
    }

    /// @notice Returns whether `account_` holds `role_` on the `ROLES` module.
    function _hasRole(address account_, bytes32 role_) private view returns (bool) {
        return ROLES.hasRole(account_, role_);
    }

    // ========== SUB-ACTION VALIDATORS ========== //

    function _validateGatewaySubAction(
        address caller_,
        ITimelockBatchQueue.BatchAction memory action_
    ) private view {
        bytes4 sel = action_.selector;
        if (
            sel == ILZBridgeGateway.setOutRateLimits.selector ||
            sel == ILZBridgeGateway.setInRateLimits.selector ||
            sel == ILZBridgeGateway.clearOutboundInFlight.selector ||
            sel == ILZBridgeGateway.clearInboundInFlight.selector
        ) {
            _requireRateLimiterProposer(caller_);
            _decodeGatewayRateLimitPayload(sel, action_.payload);
            return;
        }
        if (
            sel == ILZBridgeGateway.setDelegate.selector ||
            sel == ILZBridgeGateway.increaseBridgedSupply.selector ||
            sel == ILZBridgeGateway.decreaseBridgedSupply.selector ||
            sel == IGracePeriod.setGracePeriod.selector
        ) {
            _requireBridgeAdminProposer(caller_);
            _decodeGatewayAdminPayload(sel, action_.payload);
            return;
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
    }

    function _validateDelegateSubAction(
        address caller_,
        ITimelockBatchQueue.BatchAction memory action_
    ) private view {
        bytes4 sel = action_.selector;
        if (
            sel == ILZEndpointV2Authorized.setSendLibrary.selector ||
            sel == ILZEndpointV2Authorized.setReceiveLibrary.selector ||
            sel == ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector ||
            sel == ILZEndpointV2Authorized.setEndpointConfig.selector ||
            sel == ILZEndpointV2Authorized.skip.selector ||
            sel == ILZEndpointV2Authorized.nilify.selector ||
            sel == ILZEndpointV2Authorized.burn.selector ||
            sel == ILZEndpointV2Authorized.clear.selector
        ) {
            _requireBridgeAdminProposer(caller_);
            _decodeDelegatePayload(sel, action_.payload);
            return;
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
    }

    function _validateFacilitatorSubAction(
        address caller_,
        ITimelockBatchQueue.BatchAction memory action_
    ) private view {
        bytes4 sel = action_.selector;
        if (sel == ILZCrossChainBridge.setConfigurator.selector) {
            _requireAdminProposer(caller_);
            address candidate = abi.decode(action_.payload, (address));
            ILZCrossChainBridge(facilitator).validateSetConfigurator(candidate);
            return;
        }
        if (
            sel == ILZCrossChainBridge.setGateway.selector ||
            sel == ILZCrossChainBridge.setReEnabler.selector ||
            sel == IGracePeriod.setGracePeriod.selector
        ) {
            _requireBridgeAdminProposer(caller_);
            _decodeFacilitatorPayload(sel, action_.payload);
            return;
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
    }

    function _validateSelfSubAction(
        address caller_,
        ITimelockBatchQueue.BatchAction memory action_
    ) private view {
        bytes4 sel = action_.selector;
        if (
            sel == this.queueSetTargetGateway.selector ||
            sel == this.queueSetTargetDelegate.selector ||
            sel == this.queueSetTargetFacilitator.selector
        ) {
            _requireAdminProposer(caller_);
            address candidate = abi.decode(action_.payload, (address));
            if (candidate == address(0))
                revert LZBridgeAndDelegateConfig_InvalidAddress(
                    sel == this.queueSetTargetGateway.selector
                        ? "gateway"
                        : sel == this.queueSetTargetDelegate.selector
                        ? "delegate"
                        : "facilitator"
                );
            return;
        }
        if (sel == this.queueSetTimelockDelay.selector) {
            _requireAdminProposer(caller_);
            uint48 delay = abi.decode(action_.payload, (uint48));
            _validateTimelockDelay(delay);
            return;
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
    }

    /// @notice Decodes the payload of a rate-limit-related gateway sub-action.
    /// @dev Only the type shape is checked, the target function validates the values.
    function _decodeGatewayRateLimitPayload(bytes4 sel_, bytes memory payload_) private pure {
        if (
            sel_ == ILZBridgeGateway.setOutRateLimits.selector ||
            sel_ == ILZBridgeGateway.setInRateLimits.selector
        ) {
            abi.decode(payload_, (IOffsettingRateLimiter.RateLimitConfig[]));
        } else {
            abi.decode(payload_, (uint32[]));
        }
    }

    /// @notice Decodes the payload of a non-rate-limit gateway sub-action and forwards it to
    ///         the target's `validate*` mirror so payload invariants fail at queue time.
    function _decodeGatewayAdminPayload(bytes4 sel_, bytes memory payload_) private view {
        if (sel_ == ILZBridgeGateway.setDelegate.selector) {
            address delegateCandidate = abi.decode(payload_, (address));
            ILZBridgeGateway(gateway).validateSetDelegate(delegateCandidate);
        } else if (sel_ == ILZBridgeGateway.increaseBridgedSupply.selector) {
            uint256 amount = abi.decode(payload_, (uint256));
            ILZBridgeGateway(gateway).validateIncreaseBridgedSupply(amount);
        } else if (sel_ == ILZBridgeGateway.decreaseBridgedSupply.selector) {
            uint256 amount = abi.decode(payload_, (uint256));
            ILZBridgeGateway(gateway).validateDecreaseBridgedSupply(amount);
        } else {
            // setGracePeriod
            uint32 period = abi.decode(payload_, (uint32));
            _validateGracePeriod(period);
        }
    }

    /// @notice Decodes the payload of a delegate sub-action.
    function _decodeDelegatePayload(bytes4 sel_, bytes memory payload_) private pure {
        if (sel_ == ILZEndpointV2Authorized.setSendLibrary.selector) {
            abi.decode(payload_, (uint32, address));
        } else if (
            sel_ == ILZEndpointV2Authorized.setReceiveLibrary.selector ||
            sel_ == ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector
        ) {
            abi.decode(payload_, (uint32, address, uint256));
        } else if (sel_ == ILZEndpointV2Authorized.setEndpointConfig.selector) {
            abi.decode(payload_, (address, SetConfigParam[]));
        } else if (sel_ == ILZEndpointV2Authorized.skip.selector) {
            abi.decode(payload_, (uint32, bytes32, uint64));
        } else if (
            sel_ == ILZEndpointV2Authorized.nilify.selector ||
            sel_ == ILZEndpointV2Authorized.burn.selector
        ) {
            abi.decode(payload_, (uint32, bytes32, uint64, bytes32));
        } else {
            // clear
            abi.decode(payload_, (Origin, bytes32, bytes));
        }
    }

    /// @notice Decodes the payload of a facilitator sub-action that is not `setConfigurator`,
    ///         forwarding it to the target's `validate*` mirror where one exists so payload
    ///         invariants fail at queue time.
    function _decodeFacilitatorPayload(bytes4 sel_, bytes memory payload_) private view {
        if (sel_ == ILZCrossChainBridge.setGateway.selector) {
            address candidate = abi.decode(payload_, (address));
            ILZCrossChainBridge(facilitator).validateSetGateway(candidate);
        } else if (sel_ == ILZCrossChainBridge.setReEnabler.selector) {
            abi.decode(payload_, (address));
        } else {
            // setGracePeriod
            uint32 period = abi.decode(payload_, (uint32));
            _validateGracePeriod(period);
        }
    }

    // ========== SUB-ACTION EXECUTORS ========== //

    function _executeGatewaySubAction(ITimelockBatchQueue.BatchAction memory action_) private {
        bytes4 sel = action_.selector;
        ILZBridgeGateway gw = ILZBridgeGateway(gateway);
        if (sel == ILZBridgeGateway.setDelegate.selector) {
            gw.setDelegate(abi.decode(action_.payload, (address)));
        } else if (sel == ILZBridgeGateway.increaseBridgedSupply.selector) {
            gw.increaseBridgedSupply(abi.decode(action_.payload, (uint256)));
        } else if (sel == ILZBridgeGateway.decreaseBridgedSupply.selector) {
            gw.decreaseBridgedSupply(abi.decode(action_.payload, (uint256)));
        } else if (sel == ILZBridgeGateway.setOutRateLimits.selector) {
            gw.setOutRateLimits(
                abi.decode(action_.payload, (IOffsettingRateLimiter.RateLimitConfig[]))
            );
        } else if (sel == ILZBridgeGateway.setInRateLimits.selector) {
            gw.setInRateLimits(
                abi.decode(action_.payload, (IOffsettingRateLimiter.RateLimitConfig[]))
            );
        } else if (sel == ILZBridgeGateway.clearOutboundInFlight.selector) {
            gw.clearOutboundInFlight(abi.decode(action_.payload, (uint32[])));
        } else if (sel == ILZBridgeGateway.clearInboundInFlight.selector) {
            gw.clearInboundInFlight(abi.decode(action_.payload, (uint32[])));
        } else if (sel == IGracePeriod.setGracePeriod.selector) {
            IGracePeriod(address(gw)).setGracePeriod(abi.decode(action_.payload, (uint32)));
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
        }
    }

    function _executeDelegateSubAction(ITimelockBatchQueue.BatchAction memory action_) private {
        bytes4 sel = action_.selector;
        ILZEndpointV2Authorized dg = ILZEndpointV2Authorized(delegate);
        if (sel == ILZEndpointV2Authorized.setSendLibrary.selector) {
            (uint32 eid, address lib) = abi.decode(action_.payload, (uint32, address));
            dg.setSendLibrary(eid, lib);
        } else if (sel == ILZEndpointV2Authorized.setReceiveLibrary.selector) {
            (uint32 eid, address lib, uint256 grace) = abi.decode(
                action_.payload,
                (uint32, address, uint256)
            );
            dg.setReceiveLibrary(eid, lib, grace);
        } else if (sel == ILZEndpointV2Authorized.setReceiveLibraryTimeout.selector) {
            (uint32 eid, address lib, uint256 expiry) = abi.decode(
                action_.payload,
                (uint32, address, uint256)
            );
            dg.setReceiveLibraryTimeout(eid, lib, expiry);
        } else if (sel == ILZEndpointV2Authorized.setEndpointConfig.selector) {
            (address lib, SetConfigParam[] memory params) = abi.decode(
                action_.payload,
                (address, SetConfigParam[])
            );
            dg.setEndpointConfig(lib, params);
        } else if (sel == ILZEndpointV2Authorized.skip.selector) {
            (uint32 srcEid, bytes32 sender, uint64 nonce) = abi.decode(
                action_.payload,
                (uint32, bytes32, uint64)
            );
            dg.skip(srcEid, sender, nonce);
        } else if (sel == ILZEndpointV2Authorized.nilify.selector) {
            (uint32 srcEid, bytes32 sender, uint64 nonce, bytes32 payloadHash) = abi.decode(
                action_.payload,
                (uint32, bytes32, uint64, bytes32)
            );
            dg.nilify(srcEid, sender, nonce, payloadHash);
        } else if (sel == ILZEndpointV2Authorized.burn.selector) {
            (uint32 srcEid, bytes32 sender, uint64 nonce, bytes32 payloadHash) = abi.decode(
                action_.payload,
                (uint32, bytes32, uint64, bytes32)
            );
            dg.burn(srcEid, sender, nonce, payloadHash);
        } else if (sel == ILZEndpointV2Authorized.clear.selector) {
            (Origin memory origin, bytes32 guid, bytes memory message) = abi.decode(
                action_.payload,
                (Origin, bytes32, bytes)
            );
            dg.clear(origin, guid, message);
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
        }
    }

    function _executeFacilitatorSubAction(ITimelockBatchQueue.BatchAction memory action_) private {
        bytes4 sel = action_.selector;
        ILZCrossChainBridge fac = ILZCrossChainBridge(facilitator);
        if (sel == ILZCrossChainBridge.setGateway.selector) {
            fac.setGateway(abi.decode(action_.payload, (address)));
        } else if (sel == ILZCrossChainBridge.setReEnabler.selector) {
            fac.setReEnabler(abi.decode(action_.payload, (address)));
        } else if (sel == IGracePeriod.setGracePeriod.selector) {
            IGracePeriod(address(fac)).setGracePeriod(abi.decode(action_.payload, (uint32)));
        } else if (sel == ILZCrossChainBridge.setConfigurator.selector) {
            fac.setConfigurator(abi.decode(action_.payload, (address)));
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
        }
    }

    /// @dev Queue-time validation in `_validateSelfSubAction` already enforces non-zero target
    ///      addresses and the timelock delay bounds, so this execute path trusts the decoded
    ///      payload and routes to the matching `_setTarget*` helper.
    function _executeSelfSubAction(ITimelockBatchQueue.BatchAction memory action_) private {
        bytes4 sel = action_.selector;
        if (sel == this.queueSetTimelockDelay.selector) {
            _setTimelockDelay(abi.decode(action_.payload, (uint48)));
            return;
        }
        address candidate = abi.decode(action_.payload, (address));
        if (sel == this.queueSetTargetGateway.selector) {
            _setTargetGateway(candidate);
        } else if (sel == this.queueSetTargetDelegate.selector) {
            _setTargetDelegate(candidate);
        } else if (sel == this.queueSetTargetFacilitator.selector) {
            _setTargetFacilitator(candidate);
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, sel);
        }
    }

    // ========== HELPERS ========== //

    /// @notice Writes the gateway target and emits `TargetGatewaySet`. Shared between the
    ///         constructor and the timelocked rotation path.
    function _setTargetGateway(address gateway_) private {
        gateway = gateway_;
        emit TargetGatewaySet(gateway_);
    }

    /// @notice Writes the delegate target and emits `TargetDelegateSet`. Shared between the
    ///         constructor and the timelocked rotation path.
    function _setTargetDelegate(address delegate_) private {
        delegate = delegate_;
        emit TargetDelegateSet(delegate_);
    }

    /// @notice Writes the facilitator target and emits `TargetFacilitatorSet`. Shared between
    ///         the constructor and the timelocked rotation path.
    function _setTargetFacilitator(address facilitator_) private {
        facilitator = facilitator_;
        emit TargetFacilitatorSet(facilitator_);
    }

    /// @notice Mirrors the zero-period check performed by `ReEnablerGracePeriod._setGracePeriod`
    ///         so that a `setGracePeriod` sub-action is rejected at queue time rather than at
    ///         execution time.
    function _validateGracePeriod(uint32 period_) private pure {
        if (period_ == 0) revert IGracePeriod.GracePeriod_ZeroPeriod();
    }

    function _requireNonzeroAddress(address address_, string memory parameter_) private pure {
        if (address_ == address(0)) revert LZBridgeAndDelegateConfig_InvalidAddress(parameter_);
    }
}
