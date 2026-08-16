// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {BRIDGE_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @title  CCIPBridgeConfigTimelock
/// @notice Timelock policy through which the bridge admin role queues typed route, remote pool,
///         allowlist and rate limit changes of a `CCIPBridgeConfig` policy.
/// @dev    The config policy address is fixed at construction and must advertise
///         `ICCIPBridgeConfig` through ERC165. The token pool whose state is hashed is read from
///         the config policy at construction and is fixed for the lifetime of that policy.
///
///         Queueing requires this policy to be enabled, the caller to hold the bridge admin
///         role and the config policy to name this timelock as its configurator; it does not
///         require the config policy to be enabled. Every sub-action must target the config
///         policy with a supported selector and a payload whose canonical re-encoding equals the
///         stored bytes, and must pass the config policy's validation mirror of the targeted
///         function. Execution is permissionless once the delay elapses and requires this policy
///         and the config policy to be enabled and this timelock to still be the configurator;
///         the shared base then checks the reserved keys and state hashes before each dispatch.
///         An action queued while the config policy is disabled therefore holds its
///         configuration keys until it is executed once the config policy is enabled again, or
///         until it is cancelled; so does an action whose dispatch reverts because the config
///         policy no longer owns the pool, or whose execution this timelock rejects because the
///         config policy names another configurator. Cancellation is available to the admin
///         role, the emergency role and the proposer of the action, whether or not this policy
///         is enabled and whether or not the action has expired.
///
///         `enable` and `setTimelockDelay` are restricted to the admin role, `disable` to the
///         emergency or admin role, `reEnable` to the bridge admin role within the grace window,
///         and `setGracePeriod` to the admin role while enabled.
contract CCIPBridgeConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    ICCIPBridgeConfigTimelock,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @inheritdoc ICCIPBridgeConfigTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc ICCIPBridgeConfigTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc ICCIPBridgeConfigTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    /// @inheritdoc ICCIPBridgeConfigTimelock
    bytes32 public constant override RATE_LIMITS_DOMAIN =
        keccak256("CCIP_BRIDGE_CONFIG_RATE_LIMITS");

    /// @inheritdoc ICCIPBridgeConfigTimelock
    bytes32 public constant override REMOTE_POOLS_DOMAIN =
        keccak256("CCIP_BRIDGE_CONFIG_REMOTE_POOLS");

    /// @inheritdoc ICCIPBridgeConfigTimelock
    bytes32 public constant override ROUTE_IDENTITY_DOMAIN =
        keccak256("CCIP_BRIDGE_CONFIG_ROUTE_IDENTITY");

    /// @inheritdoc ICCIPBridgeConfigTimelock
    bytes32 public constant override ALLOWLIST_DOMAIN = keccak256("CCIP_BRIDGE_CONFIG_ALLOWLIST");

    /// @notice The maximum number of configuration keys that one batch may reserve.
    /// @dev    A route contributes three keys and the allowlist one.
    uint256 internal constant _MAX_CONFIG_KEYS_PER_BATCH = 24;

    // ========== IMMUTABLES ========== //

    /// @notice The config policy that receives the queued actions.
    ICCIPBridgeConfig internal immutable _CONFIG;

    /// @notice The token pool owned by the config policy, whose state is hashed.
    ICCIPTokenPoolAdmin internal immutable _POOL;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys the config timelock for one config policy.
    /// @dev    The policy starts disabled. It becomes usable once the config policy names it as
    ///         configurator.
    ///
    ///         Reverts if:
    ///         - `config_` is the zero address.
    ///         - `config_` does not advertise `ICCIPBridgeConfig` through ERC165.
    ///         - `initialTimelockDelay_` is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`.
    ///         - `gracePeriod_` is zero.
    /// @param  kernel_ The kernel of the policy.
    /// @param  config_ The config policy that receives the queued actions.
    /// @param  initialTimelockDelay_ The initial timelock delay, in seconds.
    /// @param  gracePeriod_ The length of the re-enable grace window, in seconds.
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
        if (config_ == address(0)) revert CCIPBridgeConfigTimelock_InvalidAddress("config");
        if (!ERC165Checker.supportsInterface(config_, type(ICCIPBridgeConfig).interfaceId)) {
            revert CCIPBridgeConfigTimelock_InvalidConfig(config_);
        }

        _CONFIG = ICCIPBridgeConfig(config_);
        _POOL = ICCIPTokenPoolAdmin(_CONFIG.pool());
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev Reverts if the installed ROLES module major version is not 1.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (rolesMajor != 1) revert CCIPBridgeConfigTimelock_InvalidModuleVersion();
    }

    /// @inheritdoc Policy
    /// @dev This policy does not request module permissions.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc ICCIPBridgeConfigTimelock
    function config() external view override returns (address config_) {
        return address(_CONFIG);
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    function getRateLimitsKey(uint64 chainSelector_) external view override returns (bytes32 key) {
        return _scopedKey(_routeLocalKey(RATE_LIMITS_DOMAIN, chainSelector_));
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    function getRemotePoolsKey(uint64 chainSelector_) external view override returns (bytes32 key) {
        return _scopedKey(_routeLocalKey(REMOTE_POOLS_DOMAIN, chainSelector_));
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    function getRouteIdentityKey(
        uint64 chainSelector_
    ) external view override returns (bytes32 key) {
        return _scopedKey(_routeLocalKey(ROUTE_IDENTITY_DOMAIN, chainSelector_));
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    function getAllowListKey() external view override returns (bytes32 key) {
        return _scopedKey(ALLOWLIST_DOMAIN);
    }

    // ========== QUEUE FUNCTIONS ========== //

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - `validateAddChain` of the config policy rejects `update_`.
    ///      - Any of the three route domains of `update_.remoteChainSelector` is reserved by
    ///        an unresolved action (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueAddChain(
        ICCIPTokenPoolAdmin.ChainUpdate calldata update_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                ICCIPBridgeConfig.addChain.selector,
                abi.encode(update_)
            );
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - `validateRemoveChain` of the config policy rejects `chainSelector_`.
    ///      - Any of the three route domains of `chainSelector_` is reserved by an unresolved
    ///        action (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueRemoveChain(uint64 chainSelector_) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                ICCIPBridgeConfig.removeChain.selector,
                abi.encode(chainSelector_)
            );
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - `validateRecreateChainWithNewRemoteToken` of the config policy rejects the
    ///        arguments.
    ///      - Any of the three route domains of `chainSelector_` is reserved by an unresolved
    ///        action (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueRecreateChainWithNewRemoteToken(
        uint64 chainSelector_,
        bytes calldata remoteToken_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                ICCIPBridgeConfig.recreateChainWithNewRemoteToken.selector,
                abi.encode(chainSelector_, remoteToken_)
            );
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - `validateAddRemotePool` of the config policy rejects the arguments.
    ///      - The remote pools domain of `chainSelector_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueAddRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                ICCIPBridgeConfig.addRemotePool.selector,
                abi.encode(chainSelector_, remotePool_)
            );
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - `validateRemoveRemotePool` of the config policy rejects the arguments.
    ///      - The remote pools domain of `chainSelector_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueRemoveRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                ICCIPBridgeConfig.removeRemotePool.selector,
                abi.encode(chainSelector_, remotePool_)
            );
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - `validateApplyAllowListUpdates` of the config policy rejects the arguments.
    ///      - The allowlist domain is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueApplyAllowListUpdates(
        address[] calldata removes_,
        address[] calldata adds_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                ICCIPBridgeConfig.applyAllowListUpdates.selector,
                abi.encode(removes_, adds_)
            );
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - `validateSetChainRateLimits` of the config policy rejects the arguments.
    ///      - The rate limits domain of `chainSelector_` is reserved by an unresolved action
    ///        (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    function queueSetChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config calldata outbound_,
        ICCIPRateLimiter.Config calldata inbound_
    ) external override returns (uint64 actionId) {
        return
            _queueAction(
                address(_CONFIG),
                ICCIPBridgeConfig.setChainRateLimits.selector,
                abi.encode(chainSelector_, outbound_, inbound_)
            );
    }

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    ///      - The batch is empty (`ITimelockBatchQueue_BatchEmpty`) or holds more than the
    ///        maximum number of sub-actions (`ITimelockBatchQueue_BatchTooLarge`).
    ///      - A sub-action does not target the config policy, uses an unsupported selector or
    ///        carries a payload whose canonical re-encoding differs from the stored bytes
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    ///      - A payload cannot be decoded with the parameter types of its selector; the
    ///        decoding revert is propagated as is.
    ///      - The config policy's validation mirror rejects a sub-action.
    ///      - Two sub-actions reserve the same domain, or a domain is reserved by an unresolved
    ///        action (`IConfigTimelockBatchQueue_ConfigKeyPending`).
    ///      - The batch reserves more than the maximum number of configuration keys
    ///        (`IConfigTimelockBatchQueue_ConfigKeysTooMany`).
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external override returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    // ========== CONFIGURATION ========== //

    /// @inheritdoc ICCIPBridgeConfigTimelock
    /// @dev Setting the current value writes and emits.
    ///
    ///      Reverts if:
    ///      - This policy is disabled.
    ///      - The caller does not hold the admin role.
    ///      - `delay_` is outside `[MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]`
    ///        (`ITimelockBatchQueue_TimelockDelayInvalid`).
    function setTimelockDelay(uint48 delay_) external override givenEnabled onlyAdminRole {
        _setTimelockDelay(delay_);
    }

    // ========== CONFIG TIMELOCK HOOKS ========== //

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The enabled state of the config policy is not checked here; it is checked by
    ///      `_validateExecution`. An action queued while the config policy is disabled holds its
    ///      configuration keys until it executes or is cancelled.
    ///
    ///      Reverts if:
    ///      - This policy is disabled.
    ///      - `caller_` does not hold the bridge admin role.
    ///      - The config policy does not name this timelock as its configurator.
    function _validateConfigQueue(address caller_) internal view override {
        _requireEnabled();
        _requireRole(caller_, BRIDGE_ADMIN_ROLE);
        _requireConfigurator();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The payload is decoded with the parameter types of the targeted config function and
    ///      re-encoded; the re-encoding must equal the stored payload. The decoded arguments are
    ///      then passed to the config policy's validation mirror of that function.
    ///
    ///      Reverts if:
    ///      - The target is not the config policy (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The selector is not one of the supported config functions
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The payload cannot be decoded with the parameter types of the selector; the
    ///        decoding revert is propagated as is.
    ///      - The canonical re-encoding of the decoded payload differs from the stored bytes
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The validation mirror of the targeted function rejects the decoded arguments.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        bytes4 selector = action_.selector;
        if (action_.target != address(_CONFIG)) {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }
        bytes memory payload = action_.payload;

        if (selector == ICCIPBridgeConfig.addChain.selector) {
            ICCIPTokenPoolAdmin.ChainUpdate memory update = abi.decode(
                payload,
                (ICCIPTokenPoolAdmin.ChainUpdate)
            );
            _requireCanonicalPayload(payload, abi.encode(update), selector);
            _CONFIG.validateAddChain(update);
        } else if (selector == ICCIPBridgeConfig.removeChain.selector) {
            uint64 chainSelector = abi.decode(payload, (uint64));
            _requireCanonicalPayload(payload, abi.encode(chainSelector), selector);
            _CONFIG.validateRemoveChain(chainSelector);
        } else if (selector == ICCIPBridgeConfig.recreateChainWithNewRemoteToken.selector) {
            (uint64 chainSelector, bytes memory remoteToken) = abi.decode(payload, (uint64, bytes));
            _requireCanonicalPayload(payload, abi.encode(chainSelector, remoteToken), selector);
            _CONFIG.validateRecreateChainWithNewRemoteToken(chainSelector, remoteToken);
        } else if (selector == ICCIPBridgeConfig.addRemotePool.selector) {
            (uint64 chainSelector, bytes memory remotePool) = abi.decode(payload, (uint64, bytes));
            _requireCanonicalPayload(payload, abi.encode(chainSelector, remotePool), selector);
            _CONFIG.validateAddRemotePool(chainSelector, remotePool);
        } else if (selector == ICCIPBridgeConfig.removeRemotePool.selector) {
            (uint64 chainSelector, bytes memory remotePool) = abi.decode(payload, (uint64, bytes));
            _requireCanonicalPayload(payload, abi.encode(chainSelector, remotePool), selector);
            _CONFIG.validateRemoveRemotePool(chainSelector, remotePool);
        } else if (selector == ICCIPBridgeConfig.applyAllowListUpdates.selector) {
            (address[] memory removes, address[] memory adds) = abi.decode(
                payload,
                (address[], address[])
            );
            _requireCanonicalPayload(payload, abi.encode(removes, adds), selector);
            _CONFIG.validateApplyAllowListUpdates(removes, adds);
        } else if (selector == ICCIPBridgeConfig.setChainRateLimits.selector) {
            (
                uint64 chainSelector,
                ICCIPRateLimiter.Config memory outbound,
                ICCIPRateLimiter.Config memory inbound
            ) = abi.decode(payload, (uint64, ICCIPRateLimiter.Config, ICCIPRateLimiter.Config));
            _requireCanonicalPayload(
                payload,
                abi.encode(chainSelector, outbound, inbound),
                selector
            );
            _CONFIG.validateSetChainRateLimits(chainSelector, outbound, inbound);
        } else {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The config policy is the destination of every sub-action.
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address destination) {
        return address(_CONFIG);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Route domains are keyed by `keccak256(abi.encode(domain, chainSelector))`; the
    ///      allowlist domain is keyed by `ALLOWLIST_DOMAIN` itself.
    ///
    ///      Reverts if:
    ///      - The selector is not one of the supported config functions
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        bytes4 selector = action_.selector;

        if (selector == ICCIPBridgeConfig.applyAllowListUpdates.selector) {
            keys = new bytes32[](1);
            keys[0] = ALLOWLIST_DOMAIN;
            return keys;
        }

        uint64 chainSelector = _routeChainSelector(action_);
        if (
            selector == ICCIPBridgeConfig.addChain.selector ||
            selector == ICCIPBridgeConfig.removeChain.selector ||
            selector == ICCIPBridgeConfig.recreateChainWithNewRemoteToken.selector
        ) {
            keys = new bytes32[](3);
            keys[0] = _routeLocalKey(RATE_LIMITS_DOMAIN, chainSelector);
            keys[1] = _routeLocalKey(REMOTE_POOLS_DOMAIN, chainSelector);
            keys[2] = _routeLocalKey(ROUTE_IDENTITY_DOMAIN, chainSelector);
        } else if (
            selector == ICCIPBridgeConfig.addRemotePool.selector ||
            selector == ICCIPBridgeConfig.removeRemotePool.selector
        ) {
            keys = new bytes32[](1);
            keys[0] = _routeLocalKey(REMOTE_POOLS_DOMAIN, chainSelector);
        } else {
            // Only `setChainRateLimits` remains: `_routeChainSelector` reverts for any
            // unsupported selector.
            keys = new bytes32[](1);
            keys[0] = _routeLocalKey(RATE_LIMITS_DOMAIN, chainSelector);
        }
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev The hash preimages are:
    ///      - rate limits: `abi.encode(RATE_LIMITS_DOMAIN, chainSelector, outbound.isEnabled,
    ///        outbound.capacity, outbound.rate, inbound.isEnabled, inbound.capacity,
    ///        inbound.rate)`;
    ///      - remote pools: `abi.encode(REMOTE_POOLS_DOMAIN, chainSelector, count, aggregate)`,
    ///        where `count` is the number of accepted remote pools and `aggregate` is the XOR of
    ///        `keccak256(remotePool)` over the raw bytes of every accepted remote pool;
    ///      - route identity: `abi.encode(ROUTE_IDENTITY_DOMAIN, chainSelector, isSupported,
    ///        remoteToken)`;
    ///      - allowlist: `abi.encode(ALLOWLIST_DOMAIN, allowListEnabled, count, aggregate)`,
    ///        where `count` is the number of allowlisted addresses and `aggregate` is the XOR of
    ///        `keccak256(abi.encode(member))` over every allowlisted address.
    ///
    ///      The two set aggregates are independent of the order in which the pool returns the
    ///      members, which changes when an entry is removed from the underlying enumerable set,
    ///      and are computed in one pass over the returned array. Members are hashed before
    ///      the XOR and the cardinality is part of the preimage. The XOR aggregate is not
    ///      collision resistant against members chosen by an adversary, since XOR is linear: two
    ///      distinct sets of equal cardinality whose hashed members XOR to the same value collide.
    ///      It serves as a detector of state drift between queueing and execution and relies on
    ///      the pool storing both sets as enumerable sets, so that `getRemotePools` and
    ///      `getAllowList` return each member exactly once and only the pool owner writes them.
    ///
    ///      Reverts if:
    ///      - `key_` is not one of the keys that `_configKeys` returns for `action_`
    ///        (`CCIPBridgeConfigTimelock_UnsupportedConfigKey`).
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32 key_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32 stateHash) {
        if (key_ == ALLOWLIST_DOMAIN) return _allowListStateHash();

        uint64 chainSelector = _routeChainSelector(action_);
        if (key_ == _routeLocalKey(RATE_LIMITS_DOMAIN, chainSelector)) {
            return _rateLimitsStateHash(chainSelector);
        }
        if (key_ == _routeLocalKey(REMOTE_POOLS_DOMAIN, chainSelector)) {
            return _remotePoolsStateHash(chainSelector);
        }
        if (key_ == _routeLocalKey(ROUTE_IDENTITY_DOMAIN, chainSelector)) {
            return _routeIdentityStateHash(chainSelector);
        }

        revert CCIPBridgeConfigTimelock_UnsupportedConfigKey(key_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Dispatches the sub-action as a typed call of the config policy function selected at
    ///      queue time, with the arguments decoded from the stored payload. A revert of the
    ///      config policy reverts the whole batch.
    ///
    ///      Reverts if:
    ///      - The selector is not one of the supported config functions
    ///        (`ITimelockBatchQueue_ActionInvalid`).
    ///      - The config policy reverts the dispatched call.
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        bytes4 selector = action_.selector;
        bytes memory payload = action_.payload;

        if (selector == ICCIPBridgeConfig.addChain.selector) {
            _CONFIG.addChain(abi.decode(payload, (ICCIPTokenPoolAdmin.ChainUpdate)));
        } else if (selector == ICCIPBridgeConfig.removeChain.selector) {
            _CONFIG.removeChain(abi.decode(payload, (uint64)));
        } else if (selector == ICCIPBridgeConfig.recreateChainWithNewRemoteToken.selector) {
            (uint64 chainSelector, bytes memory remoteToken) = abi.decode(payload, (uint64, bytes));
            _CONFIG.recreateChainWithNewRemoteToken(chainSelector, remoteToken);
        } else if (selector == ICCIPBridgeConfig.addRemotePool.selector) {
            (uint64 chainSelector, bytes memory remotePool) = abi.decode(payload, (uint64, bytes));
            _CONFIG.addRemotePool(chainSelector, remotePool);
        } else if (selector == ICCIPBridgeConfig.removeRemotePool.selector) {
            (uint64 chainSelector, bytes memory remotePool) = abi.decode(payload, (uint64, bytes));
            _CONFIG.removeRemotePool(chainSelector, remotePool);
        } else if (selector == ICCIPBridgeConfig.applyAllowListUpdates.selector) {
            (address[] memory removes, address[] memory adds) = abi.decode(
                payload,
                (address[], address[])
            );
            _CONFIG.applyAllowListUpdates(removes, adds);
        } else if (selector == ICCIPBridgeConfig.setChainRateLimits.selector) {
            (
                uint64 chainSelector,
                ICCIPRateLimiter.Config memory outbound,
                ICCIPRateLimiter.Config memory inbound
            ) = abi.decode(payload, (uint64, ICCIPRateLimiter.Config, ICCIPRateLimiter.Config));
            _CONFIG.setChainRateLimits(chainSelector, outbound, inbound);
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
    ///      re-enabled. Queued actions are not cleared by a disable, by a configurator rotation
    ///      or by a transfer of the pool ownership: after `setConfigurator` names another
    ///      contract this hook reverts with `CCIPBridgeConfigTimelock_NotConfigurator`, and
    ///      after the config policy loses the ownership of the pool every dispatch reverts inside
    ///      the pool (`OnlyCallableByOwner`, or `Unauthorized` for `setChainRateLimits`); in
    ///      both cases the action keeps its configuration keys until it is cancelled.
    ///
    ///      Reverts if:
    ///      - This policy is disabled (`NotEnabled`).
    ///      - The config policy is disabled (`NotEnabled`).
    ///      - The config policy does not name this timelock as its configurator.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireEnabled();
        if (!IEnabler(address(_CONFIG)).isEnabled()) revert NotEnabled();
        _requireConfigurator();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Cancellation is available while this policy is disabled and after the action has
    ///      expired.
    ///
    ///      Reverts if:
    ///      - `caller_` holds neither the admin role nor the emergency role and is not the
    ///        proposer of the action.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view override {
        _requireAuthorized(
            !_isAdmin(caller_) && !_hasRole(caller_, EMERGENCY_ROLE) && caller_ != action_.proposer
        );
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
    function _executionWindow() internal pure override returns (uint48 executionWindow) {
        return EXECUTION_WINDOW;
    }

    // ========== REENABLER HOOKS ========== //

    /// @notice Authorizes a re-enable transition during the grace window.
    /// @dev The admin role is not accepted here: it restarts the policy through `enable`.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the bridge admin role.
    function _authorizeReEnable() internal view override {
        _requireRole(msg.sender, BRIDGE_ADMIN_ROLE);
    }

    /// @notice Authorizes a grace window update.
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    // ========== INTERNAL HELPERS ========== //

    /// @notice Reverts with `CCIPBridgeConfigTimelock_NotConfigurator` unless the config policy
    ///         names this timelock as its configurator.
    function _requireConfigurator() internal view {
        address currentConfigurator = _CONFIG.configurator();
        if (currentConfigurator != address(this)) {
            revert CCIPBridgeConfigTimelock_NotConfigurator(currentConfigurator);
        }
    }

    /// @notice Reverts with `ITimelockBatchQueue_ActionInvalid` unless the canonical re-encoding
    ///         of the decoded arguments equals the stored payload.
    /// @param  payload_ The stored payload.
    /// @param  encoded_ The canonical re-encoding of the decoded arguments.
    /// @param  selector_ The selector of the sub-action, for the error.
    function _requireCanonicalPayload(
        bytes memory payload_,
        bytes memory encoded_,
        bytes4 selector_
    ) internal view {
        if (keccak256(payload_) != keccak256(encoded_)) {
            revert ITimelockBatchQueue_ActionInvalid(address(_CONFIG), selector_);
        }
    }

    /// @notice Decodes the chain selector of a route sub-action from its payload.
    /// @dev    Reverts with `ITimelockBatchQueue_ActionInvalid` for a selector that does not
    ///         address one route.
    /// @param  action_ The sub-action.
    /// @return chainSelector The chain selector of the route.
    function _routeChainSelector(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure returns (uint64 chainSelector) {
        bytes4 selector = action_.selector;
        bytes memory payload = action_.payload;

        if (selector == ICCIPBridgeConfig.addChain.selector) {
            return abi.decode(payload, (ICCIPTokenPoolAdmin.ChainUpdate)).remoteChainSelector;
        }
        if (selector == ICCIPBridgeConfig.removeChain.selector) {
            return abi.decode(payload, (uint64));
        }
        if (
            selector == ICCIPBridgeConfig.recreateChainWithNewRemoteToken.selector ||
            selector == ICCIPBridgeConfig.addRemotePool.selector ||
            selector == ICCIPBridgeConfig.removeRemotePool.selector
        ) {
            (chainSelector, ) = abi.decode(payload, (uint64, bytes));
            return chainSelector;
        }
        if (selector == ICCIPBridgeConfig.setChainRateLimits.selector) {
            (chainSelector, , ) = abi.decode(
                payload,
                (uint64, ICCIPRateLimiter.Config, ICCIPRateLimiter.Config)
            );
            return chainSelector;
        }

        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @notice Returns the destination-local key of a route domain.
    /// @param  domain_ The domain constant.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return localKey The local key `keccak256(abi.encode(domain_, chainSelector_))`.
    function _routeLocalKey(
        bytes32 domain_,
        uint64 chainSelector_
    ) internal pure returns (bytes32 localKey) {
        return keccak256(abi.encode(domain_, chainSelector_));
    }

    /// @notice Returns the destination-scoped key of a local key, as reserved by the shared base.
    /// @param  localKey_ The local key.
    /// @return key The key `keccak256(abi.encode(config, localKey_))`.
    function _scopedKey(bytes32 localKey_) internal view returns (bytes32 key) {
        return keccak256(abi.encode(address(_CONFIG), localKey_));
    }

    /// @notice Returns the state hash of the rate limits domain of a route.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return stateHash The state hash.
    function _rateLimitsStateHash(uint64 chainSelector_) internal view returns (bytes32 stateHash) {
        ICCIPRateLimiter.TokenBucket memory outbound = _POOL.getCurrentOutboundRateLimiterState(
            chainSelector_
        );
        ICCIPRateLimiter.TokenBucket memory inbound = _POOL.getCurrentInboundRateLimiterState(
            chainSelector_
        );

        return
            keccak256(
                abi.encode(
                    RATE_LIMITS_DOMAIN,
                    chainSelector_,
                    outbound.isEnabled,
                    outbound.capacity,
                    outbound.rate,
                    inbound.isEnabled,
                    inbound.capacity,
                    inbound.rate
                )
            );
    }

    /// @notice Returns the state hash of the remote pools domain of a route.
    /// @dev    The aggregate is the XOR of `keccak256(remotePool)` over the raw bytes of every
    ///         accepted remote pool, computed in one pass over the array returned by the pool.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return stateHash The state hash.
    function _remotePoolsStateHash(
        uint64 chainSelector_
    ) internal view returns (bytes32 stateHash) {
        bytes[] memory remotePools = _POOL.getRemotePools(chainSelector_);
        uint256 count = remotePools.length;
        bytes32 aggregate;
        for (uint256 i; i < count; ++i) {
            aggregate ^= keccak256(remotePools[i]);
        }

        return keccak256(abi.encode(REMOTE_POOLS_DOMAIN, chainSelector_, count, aggregate));
    }

    /// @notice Returns the state hash of the identity domain of a route.
    /// @param  chainSelector_ The chain selector of the route.
    /// @return stateHash The state hash.
    function _routeIdentityStateHash(
        uint64 chainSelector_
    ) internal view returns (bytes32 stateHash) {
        return
            keccak256(
                abi.encode(
                    ROUTE_IDENTITY_DOMAIN,
                    chainSelector_,
                    _POOL.isSupportedChain(chainSelector_),
                    _POOL.getRemoteToken(chainSelector_)
                )
            );
    }

    /// @notice Returns the state hash of the allowlist domain.
    /// @dev    The aggregate is the XOR of `keccak256(abi.encode(member))` over every allowlisted
    ///         address, computed in one pass over the array returned by the pool.
    /// @return stateHash The state hash.
    function _allowListStateHash() internal view returns (bytes32 stateHash) {
        address[] memory allowList = _POOL.getAllowList();
        uint256 count = allowList.length;
        bytes32 aggregate;
        for (uint256 i; i < count; ++i) {
            aggregate ^= keccak256(abi.encode(allowList[i]));
        }

        return
            keccak256(abi.encode(ALLOWLIST_DOMAIN, _POOL.getAllowListEnabled(), count, aggregate));
    }

    // ========== VERSION ========== //

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    /// @dev Adds `ICCIPBridgeConfigTimelock` and `IVersioned` to the interfaces advertised by
    ///      the bases, which include `ITimelockBatchQueue` and `IConfigTimelockBatchQueue`.
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
            interfaceId_ == type(ICCIPBridgeConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
