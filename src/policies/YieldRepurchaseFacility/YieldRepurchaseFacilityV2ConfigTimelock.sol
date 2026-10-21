// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2ConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2ConfigTimelock.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

// Constants
import {EMERGENCY_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title YieldRepurchaseFacilityV2ConfigTimelock
/// @notice The timelock policy through which the yrf_admin role queues the operator setters of
///         `YieldRepurchaseFacilityV2Config`, for permissionless execution after a delay.
/// @dev The configuration policy address is fixed at construction and must advertise
///      `IYieldRepurchaseFacilityV2Config`, `IConfigOperator`, and `IEnabler` through ERC165
///      and belong to the same kernel as this policy. The facility whose state is hashed is
///      read from the configuration policy, which binds it once; the facility address is part
///      of every state hash preimage.
///
///      Queueing requires this policy and the configuration policy to be enabled, the caller
///      to hold the yrf_admin role, and the configuration policy to name this policy as its
///      config operator. Every sub-action must target the configuration policy with a
///      supported operator setter and a payload whose canonical re-encoding equals the stored
///      bytes, and must pass the facility's validation mirror of the forwarded function.
///      Execution is permissionless once the delay elapses and requires the same enabled
///      states and the config operator binding; the shared base then checks the reserved keys
///      and the state hashes before each dispatch. The facility may be disabled at queue and
///      execution time: its configuration setters apply while it is disabled.
///
///      The domains, keys, and hash preimages are those documented by
///      `IYieldRepurchaseFacilityV2ConfigTimelock`, scoped to the configuration policy. An
///      action whose guarded state changed after queueing, through a direct admin call on the
///      configuration policy or through the facility's own cycle, and an action whose vault
///      was de-registered, cannot execute and hold their domains until the emergency role
///      cancels them; so does an action whose execution this policy rejects because the
///      configuration policy names another config operator or none. A vault that is
///      de-registered and registered again between queueing and execution is not
///      distinguished from its original registration: the hashes read only the guarded
///      fields, so an action whose guarded fields match the new registration executes
///      against it. Cancellation is available whether or not this policy is enabled and
///      whether or not the action has expired.
///
///      `enable` and `setTimelockDelay` are restricted to the admin role, `disable` to the
///      emergency or admin role, `reEnable` to the yrf_admin role within the grace window, and
///      `setGracePeriod` to the admin role while enabled. The grace window is strictly shorter
///      than one weekly cycle of the facility (`MAX_GRACE_PERIOD`). The admin role is expected
///      to be held only by the OCG timelock, so every admin-gated function of this contract is
///      de-facto timelocked.
contract YieldRepurchaseFacilityV2ConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IYieldRepurchaseFacilityV2ConfigTimelock,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    uint32 public constant override MAX_GRACE_PERIOD =
        YieldRepurchaseFacilityV2Constants.MAX_GRACE_PERIOD;

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    bytes32 public constant override INITIAL_DISCOUNT_DOMAIN =
        keccak256("YIELD_REPURCHASE_FACILITY_V2_INITIAL_DISCOUNT");

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    bytes32 public constant override MAX_PRICE_PREMIUM_DOMAIN =
        keccak256("YIELD_REPURCHASE_FACILITY_V2_MAX_PRICE_PREMIUM");

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    bytes32 public constant override YIELD_BUYBACK_SHARE_DOMAIN =
        keccak256("YIELD_REPURCHASE_FACILITY_V2_YIELD_BUYBACK_SHARE");

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    bytes32 public constant override ASSET_STATUS_DOMAIN =
        keccak256("YIELD_REPURCHASE_FACILITY_V2_ASSET_STATUS");

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    bytes32 public constant override NEXT_YIELD_DOMAIN =
        keccak256("YIELD_REPURCHASE_FACILITY_V2_NEXT_YIELD");

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    bytes32 public constant override CLEARINGHOUSE_OFFSET_DOMAIN =
        keccak256("YIELD_REPURCHASE_FACILITY_V2_CLEARINGHOUSE_OFFSET");

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    bytes32 public constant override CLEARINGHOUSE_INCLUSION_DOMAIN =
        keccak256("YIELD_REPURCHASE_FACILITY_V2_CLEARINGHOUSE_INCLUSION");

    /// @notice The number of configuration keys `enableAsset` reserves: the status domain and
    ///         the next yield domain of its vault.
    uint256 internal constant _ENABLE_ASSET_KEY_COUNT = 2;

    /// @notice The maximum number of configuration keys that one batch may reserve: two keys
    ///         for each of the 15 sub-actions of a maximal batch.
    uint256 internal constant _MAX_CONFIG_KEYS_PER_BATCH = 30;

    /// @notice The number of interfaces the constructor requires the configuration policy to
    ///         advertise: `IYieldRepurchaseFacilityV2Config`, `IConfigOperator`, and
    ///         `IEnabler`.
    uint256 internal constant _CONFIG_INTERFACE_COUNT = 3;

    /// @notice Keycode for the ROLES module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("ROLES")`.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524f4c4553); // toKeycode("ROLES")

    // ========== IMMUTABLES ========== //

    /// @notice The configuration policy that receives the queued actions.
    IYieldRepurchaseFacilityV2Config internal immutable _CONFIG;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys the config timelock for one configuration policy.
    /// @dev The policy starts disabled. It becomes usable once the configuration policy names
    ///      it as config operator.
    ///
    ///      Reverts if:
    ///      - `kernel_` is the zero address.
    ///      - `config_` is the zero address, or does not advertise
    ///        `IYieldRepurchaseFacilityV2Config`, `IConfigOperator`, and `IEnabler` through
    ///        ERC165.
    ///      - `config_` reports a kernel other than `kernel_`.
    ///      - `initialTimelockDelay_` is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`.
    ///      - `gracePeriod_` is zero or not less than `MAX_GRACE_PERIOD`.
    /// @param kernel_ The Olympus Kernel.
    /// @param config_ The configuration policy that receives the queued actions.
    /// @param initialTimelockDelay_ The initial timelock delay, in seconds.
    /// @param gracePeriod_ The initial re-enable grace window, in seconds.
    constructor(
        Kernel kernel_,
        address config_,
        uint48 initialTimelockDelay_,
        uint32 gracePeriod_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(gracePeriod_)
        ConfigTimelockBatchQueue(initialTimelockDelay_)
    {
        if (address(kernel_) == address(0)) revert Errors.BadInput("kernel");
        _requireValidGracePeriod(gracePeriod_);
        if (config_ == address(0))
            revert IYieldRepurchaseFacilityV2ConfigTimelock_InvalidConfig(config_);

        bytes4[] memory configInterfaceIds = new bytes4[](_CONFIG_INTERFACE_COUNT);
        configInterfaceIds[0] = type(IYieldRepurchaseFacilityV2Config).interfaceId;
        configInterfaceIds[1] = type(IConfigOperator).interfaceId;
        configInterfaceIds[2] = type(IEnabler).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(config_, configInterfaceIds))
            revert IYieldRepurchaseFacilityV2ConfigTimelock_InvalidConfig(config_);

        address configKernel = address(Policy(config_).kernel());
        if (configKernel != address(kernel_))
            revert IYieldRepurchaseFacilityV2ConfigTimelock_KernelMismatch(configKernel);

        _CONFIG = IYieldRepurchaseFacilityV2Config(config_);

        // Disabled by default by EnablerV2
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - The ROLES module does not report major version 1.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = _KEYCODE_ROLES;

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // ROLES compatibility depends only on its major version
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev The policy does not request module permissions.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    function config() external view override returns (address config_) {
        return address(_CONFIG);
    }

    // ========== QUEUE FUNCTIONS ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateSetYieldBuybackShare` of the facility rejects the arguments.
    ///      - The share domain of `vault_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueSetYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector,
                abi.encode(vault_, newShare_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateSetInitialDiscount` of the facility rejects the argument.
    ///      - The initial discount domain is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueSetInitialDiscount(
        uint256 initialDiscount_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.setInitialDiscount.selector,
                abi.encode(initialDiscount_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateSetMaxPricePremium` of the facility rejects the argument.
    ///      - The max price premium domain is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueSetMaxPricePremium(
        uint256 maxPricePremium_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.setMaxPricePremium.selector,
                abi.encode(maxPricePremium_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateIncreaseClearinghouseOffset` of the facility rejects the arguments.
    ///      - The offset domain of `clearinghouse_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueIncreaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector,
                abi.encode(clearinghouse_, additionalOffset_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateDecreaseNextYield` of the facility rejects the arguments.
    ///      - The next yield domain of `vault_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueDecreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector,
                abi.encode(vault_, expectedNextYield_, newNextYield_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateExcludeClearinghouse` of the facility rejects the argument.
    ///      - The inclusion domain of `clearinghouse_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueExcludeClearinghouse(
        address clearinghouse_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector,
                abi.encode(clearinghouse_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateEnableAsset` of the facility rejects the argument.
    ///      - The status domain or the next yield domain of `vault_` is reserved by an
    ///        unresolved action (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueEnableAsset(address vault_) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.enableAsset.selector,
                abi.encode(vault_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - `validateDisableAsset` of the facility rejects the argument.
    ///      - The status domain of `vault_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueDisableAsset(address vault_) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                IYieldRepurchaseFacilityV2Config.disableAsset.selector,
                abi.encode(vault_)
            );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Every sub-action is validated against the live state at queue time: the effect of
    ///      an earlier sub-action is not projected onto the validation of a later one. At
    ///      execution, the shared base re-checks the state hashes immediately before each
    ///      dispatch, so an earlier sub-action that changes the guarded state of a later one
    ///      reverts the whole batch.
    ///
    ///      Reverts if:
    ///      - This policy is disabled.
    ///      - The configuration policy is disabled.
    ///      - The caller does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    ///      - The batch is empty (`ITimelockBatchQueue_BatchEmpty`) or holds more than the
    ///        maximum number of sub-actions (`ITimelockBatchQueue_BatchTooLarge`).
    ///      - A sub-action does not target the configuration policy, uses an unsupported
    ///        selector, or carries a payload whose canonical re-encoding differs from the
    ///        stored bytes (`ITimelockBatchQueue_ActionInvalid`).
    ///      - A payload cannot be decoded with the parameter types of its selector; the
    ///        decoding revert is propagated as is.
    ///      - The facility's validation mirror rejects a sub-action.
    ///      - Two sub-actions reserve the same domain, or a domain is reserved by an
    ///        unresolved action (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    ///      - The batch reserves more than the maximum number of configuration keys
    ///        (`IConfigTimelockBatchQueue_ConfigKeysTooMany`).
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external override returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    // ========== CONFIGURATION ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2ConfigTimelock
    /// @dev Setting the current value writes and emits. The admin role is expected to be
    ///      held only by the OCG timelock, so the change is de-facto timelocked.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the admin role.
    ///      - `delay_` is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`
    ///        (`ITimelockBatchQueue_TimelockDelayInvalid`).
    function setTimelockDelay(uint48 delay_) external override onlyAdminRole {
        _setTimelockDelay(delay_);
    }

    // ========== CONFIG TIMELOCK HOOKS ========== //

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - This policy is disabled (`NotEnabled`).
    ///      - The configuration policy is disabled (`NotEnabled`).
    ///      - `caller_` does not hold the yrf_admin role.
    ///      - The configuration policy does not name this policy as its config operator.
    function _validateConfigQueue(address caller_) internal view override {
        _requireEnabled();
        _requireConfigEnabled();
        _requireRole(caller_, YRF_ADMIN_ROLE);
        _requireOperatorOfConfig();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The payload is decoded with the parameter types of the targeted setter and
    ///      re-encoded; the re-encoding must equal the stored payload. The decoded arguments
    ///      are then passed to the facility's validation mirror of that setter.
    ///
    ///      Reverts if:
    ///      - The target is not the configuration policy (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The selector is not one of the supported operator setters
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The payload cannot be decoded with the parameter types of the selector; the
    ///        decoding revert is propagated as is.
    ///      - The canonical re-encoding of the decoded payload differs from the stored bytes
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The validation mirror of the targeted setter rejects the decoded arguments.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        bytes4 selector = action_.selector;
        if (action_.target != address(_CONFIG))
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        bytes memory payload = action_.payload;
        IYieldRepurchaseFacilityV2View facility = _facility();

        if (selector == IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector) {
            (address vault, uint256 newShare) = abi.decode(payload, (address, uint256));
            _requireCanonicalPayload(payload, abi.encode(vault, newShare), selector);
            facility.validateSetYieldBuybackShare(vault, newShare);
        } else if (selector == IYieldRepurchaseFacilityV2Config.setInitialDiscount.selector) {
            uint256 initialDiscount = abi.decode(payload, (uint256));
            _requireCanonicalPayload(payload, abi.encode(initialDiscount), selector);
            facility.validateSetInitialDiscount(initialDiscount);
        } else if (selector == IYieldRepurchaseFacilityV2Config.setMaxPricePremium.selector) {
            uint256 maxPricePremium = abi.decode(payload, (uint256));
            _requireCanonicalPayload(payload, abi.encode(maxPricePremium), selector);
            facility.validateSetMaxPricePremium(maxPricePremium);
        } else if (
            selector == IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector
        ) {
            (address clearinghouse, uint256 additionalOffset) = abi.decode(
                payload,
                (address, uint256)
            );
            _requireCanonicalPayload(
                payload,
                abi.encode(clearinghouse, additionalOffset),
                selector
            );
            facility.validateIncreaseClearinghouseOffset(clearinghouse, additionalOffset);
        } else if (selector == IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector) {
            (address vault, uint256 expectedNextYield, uint256 newNextYield) = abi.decode(
                payload,
                (address, uint256, uint256)
            );
            _requireCanonicalPayload(
                payload,
                abi.encode(vault, expectedNextYield, newNextYield),
                selector
            );
            facility.validateDecreaseNextYield(vault, expectedNextYield, newNextYield);
        } else if (selector == IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector) {
            address clearinghouse = abi.decode(payload, (address));
            _requireCanonicalPayload(payload, abi.encode(clearinghouse), selector);
            facility.validateExcludeClearinghouse(clearinghouse);
        } else if (selector == IYieldRepurchaseFacilityV2Config.enableAsset.selector) {
            address vault = abi.decode(payload, (address));
            _requireCanonicalPayload(payload, abi.encode(vault), selector);
            facility.validateEnableAsset(vault);
        } else if (selector == IYieldRepurchaseFacilityV2Config.disableAsset.selector) {
            address vault = abi.decode(payload, (address));
            _requireCanonicalPayload(payload, abi.encode(vault), selector);
            facility.validateDisableAsset(vault);
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The configuration policy is the destination of every sub-action.
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address destination) {
        return address(_CONFIG);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The global domains are their own local keys; the local key of an entity domain is
    ///      `keccak256(abi.encode(domain, entity))`, where the entity is the vault or the
    ///      Clearinghouse in the first payload word. `enableAsset` reserves the status domain
    ///      and the next yield domain of its vault, since it zeroes the stored next yield that
    ///      a queued `decreaseNextYield` targets.
    ///
    ///      Reverts if:
    ///      - The selector is not one of the supported operator setters
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        bytes4 selector = action_.selector;

        if (selector == IYieldRepurchaseFacilityV2Config.setInitialDiscount.selector) {
            keys = new bytes32[](1);
            keys[0] = INITIAL_DISCOUNT_DOMAIN;
            return keys;
        }
        if (selector == IYieldRepurchaseFacilityV2Config.setMaxPricePremium.selector) {
            keys = new bytes32[](1);
            keys[0] = MAX_PRICE_PREMIUM_DOMAIN;
            return keys;
        }

        address entity = _entityAddress(action_);
        if (selector == IYieldRepurchaseFacilityV2Config.enableAsset.selector) {
            keys = new bytes32[](_ENABLE_ASSET_KEY_COUNT);
            keys[0] = _entityKey(ASSET_STATUS_DOMAIN, entity);
            keys[1] = _entityKey(NEXT_YIELD_DOMAIN, entity);
            return keys;
        }

        keys = new bytes32[](1);
        if (selector == IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector) {
            keys[0] = _entityKey(YIELD_BUYBACK_SHARE_DOMAIN, entity);
        } else if (
            selector == IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector
        ) {
            keys[0] = _entityKey(CLEARINGHOUSE_OFFSET_DOMAIN, entity);
        } else if (selector == IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector) {
            keys[0] = _entityKey(NEXT_YIELD_DOMAIN, entity);
        } else if (selector == IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector) {
            keys[0] = _entityKey(CLEARINGHOUSE_INCLUSION_DOMAIN, entity);
        } else {
            // Only `disableAsset` remains: `_entityAddress` reverts for any unsupported
            // selector.
            keys[0] = _entityKey(ASSET_STATUS_DOMAIN, entity);
        }
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The hash preimages are, with `facility` the facility bound to the configuration
    ///      policy:
    ///      - initial discount: `abi.encode(INITIAL_DISCOUNT_DOMAIN, facility,
    ///        initialDiscount)`;
    ///      - max price premium: `abi.encode(MAX_PRICE_PREMIUM_DOMAIN, facility,
    ///        maxPricePremium)`;
    ///      - yield buyback share: `abi.encode(YIELD_BUYBACK_SHARE_DOMAIN, facility, vault,
    ///        yieldBuybackShare)`;
    ///      - asset status: `abi.encode(ASSET_STATUS_DOMAIN, facility, vault, isAssetEnabled,
    ///        backingVault == vault)`;
    ///      - next yield: `abi.encode(NEXT_YIELD_DOMAIN, facility, vault, nextYield)`;
    ///      - Clearinghouse offset: `abi.encode(CLEARINGHOUSE_OFFSET_DOMAIN, facility,
    ///        clearinghouse, offset)`;
    ///      - Clearinghouse inclusion: `abi.encode(CLEARINGHOUSE_INCLUSION_DOMAIN, facility,
    ///        clearinghouse, isIncluded)`.
    ///
    ///      The per-vault fields are read through `getAssetConfig`, which reverts for a
    ///      de-registered vault: the action then cannot execute and holds its domains until
    ///      it is cancelled. A vault registered again after a de-registration is not
    ///      distinguished from its original registration: only the guarded fields are
    ///      hashed. The next yield preimage duplicates the compare-and-set guard of
    ///      `decreaseNextYield`, so a weekly reset that replaces the stored value is detected
    ///      before the dispatch; the yield snapshots, the unfunded carry, and the live
    ///      `principalReceivables` of a Clearinghouse are not hashed.
    ///
    ///      Reverts if:
    ///      - `key_` is not one of the keys that `_configKeys` returns for `action_`
    ///        (`IYieldRepurchaseFacilityV2ConfigTimelock_UnsupportedConfigKey`).
    ///      - The facility rejects a state read, including
    ///        `IYieldRepurchaseFacilityV2_AssetNotRegistered` for a de-registered vault.
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32 key_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32 stateHash) {
        IYieldRepurchaseFacilityV2View facility = _facility();

        if (key_ == INITIAL_DISCOUNT_DOMAIN) {
            return
                keccak256(
                    abi.encode(INITIAL_DISCOUNT_DOMAIN, facility, facility.initialDiscount())
                );
        }
        if (key_ == MAX_PRICE_PREMIUM_DOMAIN) {
            return
                keccak256(
                    abi.encode(MAX_PRICE_PREMIUM_DOMAIN, facility, facility.maxPricePremium())
                );
        }

        address entity = _entityAddress(action_);
        if (key_ == _entityKey(YIELD_BUYBACK_SHARE_DOMAIN, entity)) {
            return
                keccak256(
                    abi.encode(
                        YIELD_BUYBACK_SHARE_DOMAIN,
                        facility,
                        entity,
                        facility.getAssetConfig(entity).yieldBuybackShare
                    )
                );
        }
        if (key_ == _entityKey(ASSET_STATUS_DOMAIN, entity)) {
            IYieldRepurchaseFacilityV2.ReserveAsset memory assetConfig = facility.getAssetConfig(
                entity
            );
            return
                keccak256(
                    abi.encode(
                        ASSET_STATUS_DOMAIN,
                        facility,
                        entity,
                        assetConfig.isAssetEnabled,
                        facility.backingVault() == entity
                    )
                );
        }
        if (key_ == _entityKey(NEXT_YIELD_DOMAIN, entity)) {
            return
                keccak256(
                    abi.encode(
                        NEXT_YIELD_DOMAIN,
                        facility,
                        entity,
                        facility.getAssetConfig(entity).nextYield
                    )
                );
        }
        if (key_ == _entityKey(CLEARINGHOUSE_OFFSET_DOMAIN, entity)) {
            return
                keccak256(
                    abi.encode(
                        CLEARINGHOUSE_OFFSET_DOMAIN,
                        facility,
                        entity,
                        facility.clearinghouseOffset(entity)
                    )
                );
        }
        if (key_ == _entityKey(CLEARINGHOUSE_INCLUSION_DOMAIN, entity)) {
            return
                keccak256(
                    abi.encode(
                        CLEARINGHOUSE_INCLUSION_DOMAIN,
                        facility,
                        entity,
                        facility.isClearinghouseIncluded(entity)
                    )
                );
        }

        revert IYieldRepurchaseFacilityV2ConfigTimelock_UnsupportedConfigKey(key_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Dispatches the sub-action as a typed call of the configuration policy setter
    ///      selected at queue time, with the arguments decoded from the stored payload. A
    ///      revert of the configuration policy or of the facility reverts the whole batch.
    ///
    ///      Reverts if:
    ///      - The selector is not one of the supported operator setters
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The configuration policy reverts the dispatched call.
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        bytes4 selector = action_.selector;
        bytes memory payload = action_.payload;

        if (selector == IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector) {
            (address vault, uint256 newShare) = abi.decode(payload, (address, uint256));
            _CONFIG.setYieldBuybackShare(vault, newShare);
        } else if (selector == IYieldRepurchaseFacilityV2Config.setInitialDiscount.selector) {
            _CONFIG.setInitialDiscount(abi.decode(payload, (uint256)));
        } else if (selector == IYieldRepurchaseFacilityV2Config.setMaxPricePremium.selector) {
            _CONFIG.setMaxPricePremium(abi.decode(payload, (uint256)));
        } else if (
            selector == IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector
        ) {
            (address clearinghouse, uint256 additionalOffset) = abi.decode(
                payload,
                (address, uint256)
            );
            _CONFIG.increaseClearinghouseOffset(clearinghouse, additionalOffset);
        } else if (selector == IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector) {
            (address vault, uint256 expectedNextYield, uint256 newNextYield) = abi.decode(
                payload,
                (address, uint256, uint256)
            );
            _CONFIG.decreaseNextYield(vault, expectedNextYield, newNextYield);
        } else if (selector == IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector) {
            _CONFIG.excludeClearinghouse(abi.decode(payload, (address)));
        } else if (selector == IYieldRepurchaseFacilityV2Config.enableAsset.selector) {
            _CONFIG.enableAsset(abi.decode(payload, (address)));
        } else if (selector == IYieldRepurchaseFacilityV2Config.disableAsset.selector) {
            _CONFIG.disableAsset(abi.decode(payload, (address)));
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _maxConfigKeysPerBatch() internal pure override returns (uint256 maximum) {
        return _MAX_CONFIG_KEYS_PER_BATCH;
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @inheritdoc TimelockBatchQueue
    /// @dev Execution is permissionless. The delay that elapses while this policy is disabled
    ///      still counts, so an action can become executable as soon as the policy is
    ///      re-enabled. Queued actions are not cleared by a disable or by a rotation or
    ///      revocation of the config operator: after `setConfigOperator` names another
    ///      contract or the zero address this hook reverts with
    ///      `IYieldRepurchaseFacilityV2ConfigTimelock_NotConfigOperator`, and the action keeps
    ///      its configuration keys until it is cancelled. The facility is not required to be
    ///      enabled.
    ///
    ///      Reverts if:
    ///      - This policy is disabled (`NotEnabled`).
    ///      - The configuration policy is disabled (`NotEnabled`).
    ///      - The configuration policy does not name this policy as its config operator.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireEnabled();
        _requireConfigEnabled();
        _requireOperatorOfConfig();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Cancellation is available while this policy is disabled and after the action has
    ///      expired, so the configuration keys of a stale or expired action can always be
    ///      released.
    ///
    ///      Reverts if:
    ///      - `caller_` does not hold the emergency role.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @inheritdoc TimelockBatchQueue
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY)
            revert ITimelockBatchQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
    }

    /// @inheritdoc TimelockBatchQueue
    function _executionWindow() internal pure override returns (uint48 executionWindow) {
        return EXECUTION_WINDOW;
    }

    // ========== ENABLE / DISABLE ========== //

    /// @inheritdoc EnablerV2
    /// @dev The payload is not used.
    ///
    ///      Reverts if:
    ///      - The configuration policy is not an active policy of this policy's kernel.
    function _beforeEnable(bytes calldata) internal view override {
        _requireConfigActive();
    }

    /// @notice Authorizes a re-enable transition during the grace window.
    /// @dev The admin role is not accepted here: it restarts the policy through `enable`.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the yrf_admin role.
    function _authorizeReEnable() internal view override {
        _requireRole(msg.sender, YRF_ADMIN_ROLE);
    }

    /// @notice Validates the grace window and the configuration policy binding before this
    ///         policy is re-enabled.
    /// @dev Reverts if:
    ///      - The grace window since the last transition has elapsed (`GracePeriod_Expired`).
    ///      - The configuration policy is not an active policy of this policy's kernel.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireConfigActive();
    }

    /// @notice Authorizes a grace window update.
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

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

    // ========== INTERNAL HELPERS ========== //

    /// @notice Returns the facility bound to the configuration policy, as its read-only
    ///         surface.
    function _facility() internal view returns (IYieldRepurchaseFacilityV2View) {
        return IYieldRepurchaseFacilityV2View(_CONFIG.facility());
    }

    /// @notice Reverts with `NotEnabled` unless the configuration policy is enabled.
    function _requireConfigEnabled() internal view {
        if (!IEnabler(address(_CONFIG)).isEnabled()) revert NotEnabled();
    }

    /// @notice Reverts with `IYieldRepurchaseFacilityV2ConfigTimelock_ConfigNotActive` unless
    ///         the configuration policy is an active policy of this policy's kernel.
    function _requireConfigActive() internal view {
        address configAddress = address(_CONFIG);
        if (!kernel.isPolicyActive(Policy(configAddress)))
            revert IYieldRepurchaseFacilityV2ConfigTimelock_ConfigNotActive(configAddress);
    }

    /// @notice Reverts with `IYieldRepurchaseFacilityV2ConfigTimelock_NotConfigOperator` unless
    ///         the configuration policy names this policy as its config operator.
    function _requireOperatorOfConfig() internal view {
        address currentConfigOperator = IConfigOperator(address(_CONFIG)).configOperator();
        if (currentConfigOperator != address(this))
            revert IYieldRepurchaseFacilityV2ConfigTimelock_NotConfigOperator(
                currentConfigOperator
            );
    }

    /// @notice Reverts with `ITimelockBatchQueue_ActionInvalid` unless the canonical
    ///         re-encoding of the decoded arguments equals the stored payload.
    /// @param payload_ The stored payload.
    /// @param encoded_ The canonical re-encoding of the decoded arguments.
    /// @param selector_ The selector of the sub-action, for the error.
    function _requireCanonicalPayload(
        bytes memory payload_,
        bytes memory encoded_,
        bytes4 selector_
    ) internal view {
        if (keccak256(payload_) != keccak256(encoded_))
            revert ITimelockBatchQueue_ActionInvalid(address(_CONFIG), selector_);
    }

    /// @notice Decodes the entity of an entity sub-action from its payload: the vault or the
    ///         Clearinghouse in the first payload word.
    /// @dev Reverts with `ITimelockBatchQueue_ActionInvalid` for a selector that does not
    ///      address one entity.
    /// @param action_ The sub-action.
    /// @return entity The vault or the Clearinghouse address.
    function _entityAddress(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure returns (address entity) {
        bytes4 selector = action_.selector;
        if (
            selector == IYieldRepurchaseFacilityV2Config.setYieldBuybackShare.selector ||
            selector == IYieldRepurchaseFacilityV2Config.increaseClearinghouseOffset.selector ||
            selector == IYieldRepurchaseFacilityV2Config.decreaseNextYield.selector ||
            selector == IYieldRepurchaseFacilityV2Config.excludeClearinghouse.selector ||
            selector == IYieldRepurchaseFacilityV2Config.enableAsset.selector ||
            selector == IYieldRepurchaseFacilityV2Config.disableAsset.selector
        ) {
            return abi.decode(action_.payload, (address));
        }

        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @notice Returns the destination-local key of an entity domain.
    /// @param domain_ The domain constant.
    /// @param entity_ The vault or the Clearinghouse address.
    /// @return key The key `keccak256(abi.encode(domain_, entity_))`.
    function _entityKey(bytes32 domain_, address entity_) internal pure returns (bytes32 key) {
        return keccak256(abi.encode(domain_, entity_));
    }

    /// @notice Reverts unless the grace window is strictly shorter than `MAX_GRACE_PERIOD`.
    function _requireValidGracePeriod(uint32 period_) private pure {
        if (period_ >= MAX_GRACE_PERIOD)
            revert IYieldRepurchaseFacilityV2ConfigTimelock_GracePeriodTooLong();
    }

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    /// @dev Adds `IYieldRepurchaseFacilityV2ConfigTimelock` and `IVersioned` to the interfaces
    ///      advertised by the bases, which include `ITimelockBatchQueue` and
    ///      `IConfigTimelockBatchQueue`.
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        virtual
        override(EnablerV2, ReEnablerGracePeriod, ConfigTimelockBatchQueue)
        returns (bool)
    {
        return
            interfaceId_ == type(IYieldRepurchaseFacilityV2ConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
