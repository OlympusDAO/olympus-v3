// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

// Interfaces
import {ITypeAndVersion} from "@chainlink-ccip-1.6.0/shared/interfaces/ITypeAndVersion.sol";
import {ICCIPLiquidityContainer} from "src/external/bridge/ICCIPLiquidityContainer.sol";
import {ICCIPLockReleaseTokenPool} from "src/external/bridge/ICCIPLockReleaseTokenPool.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {BRIDGE_ADMIN_ROLE, BRIDGE_RATE_LIMITER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title  CCIPTokenPoolConfig
/// @notice Policy that owns the local Chainlink CCIP token pool of OHM and exposes a typed,
///         role-separated subset of the pool owner's authority.
/// @dev    The pool address is fixed at construction. The constructor requires the pool to
///         advertise `Pool.CCIP_POOL_V1` through ERC165, the identifier that the on-ramp and the
///         off-ramp check before calling a pool, and probes it for the liquidity container
///         interface, whose result gates `setRebalancer` and `transferLiquidity`.
///
///         Authorization is split into four groups:
///         - admin functions (callable by the admin role, enabled only): pool ownership,
///           config operator, router, rebalancer, rate limit admin, liquidity transfer;
///         - route functions (callable by the config operator or the admin role, enabled only):
///           supported chains, remote pools, allowlist;
///         - the rate limit function (callable by the bridge rate limiter role, the config
///           operator or the admin role, enabled only);
///         - containment functions (callable by the emergency, admin, bridge admin or bridge
///           rate limiter role, whether or not the policy is enabled): they only write the
///           disabled rate limiter configuration and cannot restore capacity.
///
///         `enable` is restricted to the admin role, `disable` to the emergency or admin role,
///         `reEnable` to the bridge admin role within the grace window, and `setGracePeriod` to
///         the admin role while enabled.
///
///         The config operator is the single-step delegated operator of `ConfigOperatorSingleStep`:
///         it starts unset, `setConfigOperator` replaces it immediately, and the zero address
///         revokes it. The route and rate limit functions accept it alongside the admin role.
///
///         Every check that this contract adds on top of the pool is shared between the
///         state-changing function and its `validate*` mirror, and the mirrors also repeat the
///         checks that the pool performs itself, so that a caller can learn the exact revert of a
///         call before making it. In the "Reverts if" lists below, an error without the
///         `CCIPTokenPoolConfig_` prefix is raised by the pool and declared in
///         `ICCIPTokenPoolAdmin`, `ICCIPRateLimiter` or `ICCIPLockReleaseTokenPool`; the validation
///         mirrors raise the same errors for the checks they repeat. Disabling this policy does not
///         stop the pool from processing transfers; only the containment functions do.
contract CCIPTokenPoolConfig is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    ICCIPTokenPoolConfig,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @notice The capacity of the disabled rate limiter configuration written by the
    ///         containment functions, in token base units.
    uint128 internal constant _DISABLED_RATE_LIMIT_CAPACITY = 2;

    /// @notice The refill rate of the disabled rate limiter configuration written by the
    ///         containment functions, in token base units per second.
    uint128 internal constant _DISABLED_RATE_LIMIT_RATE = 1;

    /// @notice The refill rate of the temporary configuration that restores a bucket fill level,
    ///         in token base units per second: the smallest rate of an enabled configuration.
    uint128 internal constant _MIN_ENABLED_RATE = 1;

    /// @notice The smallest capacity of an enabled configuration with a rate of
    ///         `_MIN_ENABLED_RATE`, in token base units: the pool requires the rate of an enabled
    ///         configuration to be non-zero and below its capacity.
    uint128 internal constant _MIN_ENABLED_CAPACITY = 2;

    /// @notice The minimum length of the return data of a successful `typeAndVersion()` call:
    ///         the ABI encoding of an empty string.
    uint256 internal constant _MIN_TYPE_AND_VERSION_RETURN_LENGTH = 64;

    // ========== IMMUTABLES ========== //

    /// @notice The token pool owned by this policy.
    ICCIPTokenPoolAdmin internal immutable _POOL;

    /// @notice Whether the pool advertises `ICCIPLiquidityContainer` through ERC165.
    bool internal immutable _IS_LIQUIDITY_CONTAINER;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys the config policy for one token pool.
    /// @dev    The policy starts disabled. The pool is not required to be owned by this policy at
    ///         construction: ownership is completed later through `acceptPoolOwnership`.
    ///
    ///         Reverts if:
    ///         - `pool_` is the zero address.
    ///         - `pool_` does not advertise `Pool.CCIP_POOL_V1` through ERC165.
    ///         - `gracePeriod_` is zero.
    /// @param  kernel_ The kernel of the policy.
    /// @param  pool_ The token pool to own.
    /// @param  gracePeriod_ The length of the re-enable grace window, in seconds.
    constructor(
        Kernel kernel_,
        address pool_,
        uint32 gracePeriod_
    ) Policy(kernel_) ReEnablerGracePeriod(gracePeriod_) {
        if (pool_ == address(0)) revert CCIPTokenPoolConfig_InvalidAddress("pool");
        if (!ERC165Checker.supportsInterface(pool_, Pool.CCIP_POOL_V1)) {
            revert CCIPTokenPoolConfig_InvalidPool(pool_);
        }

        _POOL = ICCIPTokenPoolAdmin(pool_);
        _IS_LIQUIDITY_CONTAINER = ERC165Checker.supportsInterface(
            pool_,
            type(ICCIPLiquidityContainer).interfaceId
        );
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev Reverts if the installed ROLES module major version is not 1.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (rolesMajor != 1) revert CCIPTokenPoolConfig_InvalidModuleVersion();
    }

    /// @inheritdoc Policy
    /// @dev This policy does not request module permissions.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    // ========== MODIFIERS ========== //

    /// @notice Reverts with `NotAuthorised` unless the caller is the config operator or holds
    ///         the admin role.
    modifier onlyConfigOperatorOrAdmin() {
        _requireAuthorized(!_isConfigOperator(msg.sender) && !_isAdmin(msg.sender));
        _;
    }

    /// @notice Reverts with `NotAuthorised` unless the caller holds the bridge rate limiter
    ///         role, is the config operator or holds the admin role.
    modifier onlyRateLimiterOrConfigOperatorOrAdmin() {
        _requireAuthorized(
            !_hasRole(msg.sender, BRIDGE_RATE_LIMITER_ROLE) &&
                !_isConfigOperator(msg.sender) &&
                !_isAdmin(msg.sender)
        );
        _;
    }

    /// @notice Reverts with `NotAuthorised` unless the caller holds the emergency, admin,
    ///         bridge admin or bridge rate limiter role.
    modifier onlyContainmentRole() {
        _requireAuthorized(
            !_isEmergency(msg.sender) &&
                !_isAdmin(msg.sender) &&
                !_hasRole(msg.sender, BRIDGE_ADMIN_ROLE) &&
                !_hasRole(msg.sender, BRIDGE_RATE_LIMITER_ROLE)
        );
        _;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc ICCIPTokenPoolConfig
    function pool() external view override returns (address pool_) {
        return address(_POOL);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    function isLiquidityContainer() external view override returns (bool isContainer) {
        return _IS_LIQUIDITY_CONTAINER;
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    function getDisabledRateLimiterConfig()
        external
        pure
        override
        returns (ICCIPRateLimiter.Config memory config)
    {
        return _disabledRateLimiterConfig();
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - `chainSelector_` is not a configured route (`NonExistentChain`).
    function isChainDisabled(uint64 chainSelector_) external view override returns (bool disabled) {
        _requireSupportedChain(chainSelector_);

        return
            _isDisabledBucket(_POOL.getCurrentOutboundRateLimiterState(chainSelector_)) &&
            _isDisabledBucket(_POOL.getCurrentInboundRateLimiterState(chainSelector_));
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the admin role.
    ///      - This policy is not the pending owner of the pool (`MustBeProposedOwner`), which
    ///        includes the case where it already owns the pool.
    function acceptPoolOwnership() external override givenEnabled onlyAdminRole {
        _POOL.acceptOwnership();

        emit PoolOwnershipAccepted(address(_POOL));
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev A pending proposal is overwritten by a later one. After the recipient accepts, this
    ///      policy no longer owns the pool: every function that calls the pool reverts
    ///      (`OnlyCallableByOwner`, or `Unauthorized` for the rate limiter setters), and every
    ///      action queued in the config operator reverts at execution and keeps its
    ///      configuration keys until it is cancelled.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the admin role.
    ///      - `newOwner_` is the zero address.
    ///      - `newOwner_` is this policy (`CannotTransferToSelf`).
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function transferPoolOwnership(address newOwner_) external override givenEnabled onlyAdminRole {
        if (newOwner_ == address(0)) revert CCIPTokenPoolConfig_InvalidAddress("newOwner");

        _POOL.transferOwnership(newOwner_);

        emit PoolOwnershipTransferRequested(newOwner_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev The candidate is probed with a static call to `typeAndVersion()`, which must succeed
    ///      and return at least the ABI encoding of an empty string. Setting the current value
    ///      writes and emits. Whether the candidate serves the configured routes is not checked.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the admin role.
    ///      - `router_` is the zero address.
    ///      - `router_` holds no code.
    ///      - The `typeAndVersion()` probe of `router_` fails.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function setRouter(address router_) external override givenEnabled onlyAdminRole {
        if (router_ == address(0)) revert CCIPTokenPoolConfig_InvalidAddress("router");
        if (router_.code.length == 0) revert CCIPTokenPoolConfig_InvalidRouter(router_);

        (bool success, bytes memory returnData) = router_.staticcall(
            abi.encodeWithSelector(ITypeAndVersion.typeAndVersion.selector)
        );
        if (!success || returnData.length < _MIN_TYPE_AND_VERSION_RETURN_LENGTH) {
            revert CCIPTokenPoolConfig_InvalidRouter(router_);
        }

        _POOL.setRouter(router_);

        emit PoolRouterSet(router_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev The pool emits no event for this change; `PoolRebalancerSet` is the only log of it.
    ///      Setting the current value writes and emits.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The pool is not a liquidity container.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function setRebalancer(address rebalancer_) external override givenEnabled onlyAdminRole {
        _requireLiquidityContainer();

        ICCIPLockReleaseTokenPool(address(_POOL)).setRebalancer(rebalancer_);

        emit PoolRebalancerSet(rebalancer_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Setting the current value writes and emits.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the admin role.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function setRateLimitAdmin(
        address rateLimitAdmin_
    ) external override givenEnabled onlyAdminRole {
        _POOL.setRateLimitAdmin(rateLimitAdmin_);

        emit PoolRateLimitAdminSet(rateLimitAdmin_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev The tokens move directly from `from_` to the pool.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The pool is not a liquidity container.
    ///      - `from_` is the zero address.
    ///      - `amount_` is zero.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    ///      - The pool is not the rebalancer of `from_` (`Unauthorized`).
    ///      - `amount_` exceeds the balance of `from_` (`InsufficientLiquidity`).
    function transferLiquidity(
        address from_,
        uint256 amount_
    ) external override givenEnabled onlyAdminRole {
        _requireLiquidityContainer();
        if (from_ == address(0)) revert CCIPTokenPoolConfig_InvalidAddress("from");
        if (amount_ == 0) revert CCIPTokenPoolConfig_ZeroAmount();

        ICCIPLockReleaseTokenPool(address(_POOL)).transferLiquidity(from_, amount_);

        emit PoolLiquidityTransferred(from_, amount_);
    }

    // ========== ROUTE FUNCTIONS ========== //

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - `validateAddChain` rejects `update_`.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function addChain(
        ICCIPTokenPoolAdmin.ChainUpdate calldata update_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _validateAddChain(update_);

        ICCIPTokenPoolAdmin.ChainUpdate[]
            memory chainsToAdd = new ICCIPTokenPoolAdmin.ChainUpdate[](1);
        chainsToAdd[0] = update_;
        _POOL.applyChainUpdates(new uint64[](0), chainsToAdd);

        emit RouteAdded(update_.remoteChainSelector, update_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - `validateRemoveChain` rejects `chainSelector_`.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function removeChain(
        uint64 chainSelector_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _validateRemoveChain(chainSelector_);

        uint64[] memory chainsToRemove = new uint64[](1);
        chainsToRemove[0] = chainSelector_;
        _POOL.applyChainUpdates(chainsToRemove, new ICCIPTokenPoolAdmin.ChainUpdate[](0));

        emit RouteRemoved(chainSelector_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev The route state is read from the pool before the replacement: the remote pools, both
    ///      rate limiter configurations and both fill levels projected to the current block. The
    ///      replacement is one `applyChainUpdates` call with `chainSelector_` in both the removals
    ///      and the additions, after which both buckets are full. Each fill level is then
    ///      restored by two `setChainRateLimiterConfig` calls in the same transaction: first a
    ///      configuration with `capacity = max(previousTokens, 2)` and `rate = 1`, which clamps
    ///      the bucket down to that level, then the original configuration. A previous fill
    ///      level below two units is therefore restored as two units, the smallest capacity of
    ///      an enabled configuration with a rate of one.
    ///
    ///      The pool emits, in this order: `ChainRemoved(chainSelector)`, without a
    ///      `RemotePoolRemoved` for the dropped remote pools; `RemotePoolAdded` per remote pool
    ///      followed by `ChainAdded`; then two `ConfigChanged` and one `ChainConfigured` per
    ///      `setChainRateLimiterConfig` call, so four `ConfigChanged` and two `ChainConfigured`
    ///      in total. The first `ChainConfigured` carries the temporary configuration
    ///      `{true, max(previousTokens, 2), 1}` and does not reflect the rate limit policy of the
    ///      route; the second carries the original configuration and, together with the
    ///      `RemoteTokenSet` event of this contract, confirms the result. A monitor that tracks
    ///      the accepted remote pools of a route through pool events must re-read
    ///      `getRemotePools` after this operation.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - `validateSetRemoteToken` rejects the arguments.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function setRemoteToken(
        uint64 chainSelector_,
        bytes calldata remoteToken_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _validateSetRemoteToken(chainSelector_, remoteToken_);

        bytes memory previousRemoteToken = _POOL.getRemoteToken(chainSelector_);
        ICCIPRateLimiter.TokenBucket memory outbound = _POOL.getCurrentOutboundRateLimiterState(
            chainSelector_
        );
        ICCIPRateLimiter.TokenBucket memory inbound = _POOL.getCurrentInboundRateLimiterState(
            chainSelector_
        );

        _replaceRoute(chainSelector_, remoteToken_, outbound, inbound);

        // Clamp both buckets down to their previous fill levels, then restore the configurations
        _POOL.setChainRateLimiterConfig(
            chainSelector_,
            _fillRestoreConfig(outbound.tokens),
            _fillRestoreConfig(inbound.tokens)
        );
        _POOL.setChainRateLimiterConfig(chainSelector_, _toConfig(outbound), _toConfig(inbound));

        emit RemoteTokenSet(chainSelector_, previousRemoteToken, remoteToken_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - `validateAddRemotePool` rejects the arguments.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function addRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _validateAddRemotePool(chainSelector_, remotePool_);

        _POOL.addRemotePool(chainSelector_, remotePool_);

        emit RouteRemotePoolAdded(chainSelector_, remotePool_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - The policy is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - `validateRemoveRemotePool` rejects the arguments.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function removeRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _validateRemoveRemotePool(chainSelector_, remotePool_);

        _POOL.removeRemotePool(chainSelector_, remotePool_);

        emit RouteRemotePoolRemoved(chainSelector_, remotePool_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Absent removals, duplicate additions and zero addresses are skipped by the pool
    ///      without an event.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - `validateApplyAllowListUpdates` rejects the arguments.
    ///      - This policy does not own the pool (`OnlyCallableByOwner`).
    function applyAllowListUpdates(
        address[] calldata removes_,
        address[] calldata adds_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _validateApplyAllowListUpdates(removes_, adds_);

        _POOL.applyAllowListUpdates(removes_, adds_);

        emit AllowListUpdated(removes_, adds_);
    }

    // ========== RATE LIMIT FUNCTIONS ========== //

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Setting the current values writes and emits.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller holds neither the bridge rate limiter role nor the admin role and is
    ///        not the config operator.
    ///      - `validateSetChainRateLimits` rejects the arguments.
    ///      - This policy does not own the pool and is not its rate limit admin
    ///        (`Unauthorized`).
    function setChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config calldata outbound_,
        ICCIPRateLimiter.Config calldata inbound_
    ) external override givenEnabled onlyRateLimiterOrConfigOperatorOrAdmin {
        _validateSetChainRateLimits(chainSelector_, outbound_, inbound_);

        ICCIPRateLimiter.Config memory previousOutbound = _toConfig(
            _POOL.getCurrentOutboundRateLimiterState(chainSelector_)
        );
        ICCIPRateLimiter.Config memory previousInbound = _toConfig(
            _POOL.getCurrentInboundRateLimiterState(chainSelector_)
        );

        _POOL.setChainRateLimiterConfig(chainSelector_, outbound_, inbound_);

        emit RouteRateLimitsSet(
            chainSelector_,
            previousOutbound,
            previousInbound,
            outbound_,
            inbound_
        );
    }

    // ========== CONTAINMENT FUNCTIONS ========== //

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Both buckets are written to `{isEnabled: true, capacity: 2, rate: 1}`, which clamps
    ///      each fill level to two units. The policy's enabled state is not checked.
    ///
    ///      Reverts if:
    ///      - The caller holds none of the emergency, admin, bridge admin and bridge rate
    ///        limiter roles.
    ///      - This policy does not own the pool and is not its rate limit admin
    ///        (`Unauthorized`).
    ///      - `chainSelector_` is not a configured route (`NonExistentChain`).
    function disableChain(uint64 chainSelector_) external override onlyContainmentRole {
        ICCIPRateLimiter.Config memory disabledConfig = _disabledRateLimiterConfig();
        _POOL.setChainRateLimiterConfig(chainSelector_, disabledConfig, disabledConfig);

        emit RouteDisabled(chainSelector_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Every configured route is written in one `setChainRateLimiterConfigs` call and one
    ///      `RouteDisabled` event is emitted per route. The policy's enabled state is not
    ///      checked. The order of the routes follows the pool's enumerable set.
    ///
    ///      The cost is linear in the number of configured routes: one `getSupportedChains`
    ///      read and one `setChainRateLimiterConfigs` call, plus, per route, the storage writes
    ///      of both buckets, two `ConfigChanged` and one `ChainConfigured` event of the pool and
    ///      one `RouteDisabled` event of this contract. `disableChain` contains one route per
    ///      call.
    ///
    ///      Reverts if:
    ///      - The caller holds none of the emergency, admin, bridge admin and bridge rate
    ///        limiter roles.
    ///      - At least one route is configured and this policy does not own the pool and is not
    ///        its rate limit admin (`Unauthorized`).
    function disableAllChains() external override onlyContainmentRole {
        uint64[] memory chainSelectors = _POOL.getSupportedChains();
        uint256 length = chainSelectors.length;
        if (length == 0) return;

        ICCIPRateLimiter.Config memory disabledConfig = _disabledRateLimiterConfig();
        ICCIPRateLimiter.Config[] memory outboundConfigs = new ICCIPRateLimiter.Config[](length);
        ICCIPRateLimiter.Config[] memory inboundConfigs = new ICCIPRateLimiter.Config[](length);
        for (uint256 i; i < length; ++i) {
            outboundConfigs[i] = disabledConfig;
            inboundConfigs[i] = disabledConfig;
        }

        _POOL.setChainRateLimiterConfigs(chainSelectors, outboundConfigs, inboundConfigs);

        for (uint256 i; i < length; ++i) {
            emit RouteDisabled(chainSelectors[i]);
        }
    }

    // ========== VALIDATION FUNCTIONS ========== //

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev The checks run in the order in which the pool would perform its own.
    ///
    ///      Reverts if:
    ///      - Either rate limiter configuration is disabled.
    ///      - Either rate limiter configuration has a zero rate or a rate that is not below its
    ///        capacity (`InvalidRateLimitRate`).
    ///      - The remote token is empty (`ZeroAddressNotAllowed`).
    ///      - The route already exists (`ChainAlreadyExists`).
    ///      - The remote pool list is empty.
    ///      - A remote pool entry is empty (`ZeroAddressNotAllowed`).
    ///      - A remote pool entry is duplicated (`PoolAlreadyAdded`).
    function validateAddChain(
        ICCIPTokenPoolAdmin.ChainUpdate calldata update_
    ) external view override {
        _validateAddChain(update_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - `chainSelector_` is not a configured route (`NonExistentChain`).
    function validateRemoveChain(uint64 chainSelector_) external view override {
        _validateRemoveChain(chainSelector_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - `chainSelector_` is not a configured route (`NonExistentChain`).
    ///      - `remoteToken_` is empty.
    ///      - `remoteToken_` equals the current remote token of the route.
    ///      - Either current bucket of the route is disabled.
    function validateSetRemoteToken(
        uint64 chainSelector_,
        bytes calldata remoteToken_
    ) external view override {
        _validateSetRemoteToken(chainSelector_, remoteToken_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - `chainSelector_` is not a configured route (`NonExistentChain`).
    ///      - `remotePool_` is empty (`ZeroAddressNotAllowed`).
    ///      - `remotePool_` is already accepted for the route (`PoolAlreadyAdded`).
    function validateAddRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external view override {
        _validateAddRemotePool(chainSelector_, remotePool_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - `chainSelector_` is not a configured route (`NonExistentChain`).
    ///      - `remotePool_` is not accepted for the route (`InvalidRemotePoolForChain`).
    ///      - `remotePool_` is the only accepted remote pool of the route.
    function validateRemoveRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) external view override {
        _validateRemoveRemotePool(chainSelector_, remotePool_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - The pool was deployed without an allowlist (`AllowListNotEnabled`).
    ///      - Both `removes_` and `adds_` are empty.
    function validateApplyAllowListUpdates(
        address[] calldata removes_,
        address[] calldata adds_
    ) external view override {
        _validateApplyAllowListUpdates(removes_, adds_);
    }

    /// @inheritdoc ICCIPTokenPoolConfig
    /// @dev Reverts if:
    ///      - `chainSelector_` is not a configured route (`NonExistentChain`).
    ///      - Either configuration is disabled.
    ///      - Either configuration has a zero rate or a rate that is not below its capacity
    ///        (`InvalidRateLimitRate`).
    function validateSetChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config calldata outbound_,
        ICCIPRateLimiter.Config calldata inbound_
    ) external view override {
        _validateSetChainRateLimits(chainSelector_, outbound_, inbound_);
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

    // ========== CONFIG OPERATOR HOOKS ========== //

    /// @inheritdoc ConfigOperatorSingleStep
    /// @dev Setting the current operator writes and emits, and setting the zero address revokes
    ///      the operator; the mix-in setter accepts both. The hook reverts on failure, so the
    ///      mix-in never reports `ConfigOperator_Unauthorized` through this policy.
    ///
    ///      Reverts if:
    ///      - The policy is disabled.
    ///      - The caller does not hold the admin role.
    function _authorizeSetConfigOperator()
        internal
        view
        override
        givenEnabled
        onlyAdminRole
        returns (bool authorized)
    {
        return true;
    }

    // ========== INTERNAL VALIDATION ========== //

    /// @notice Validates the arguments of `addChain`. See `validateAddChain`.
    /// @param  update_ The chain configuration to validate.
    function _validateAddChain(ICCIPTokenPoolAdmin.ChainUpdate calldata update_) internal view {
        _validateRateLimiterConfig(update_.outboundRateLimiterConfig);
        _validateRateLimiterConfig(update_.inboundRateLimiterConfig);
        if (update_.remoteTokenAddress.length == 0) {
            revert ICCIPTokenPoolAdmin.ZeroAddressNotAllowed();
        }
        if (_POOL.isSupportedChain(update_.remoteChainSelector)) {
            revert ICCIPTokenPoolAdmin.ChainAlreadyExists(update_.remoteChainSelector);
        }

        uint256 length = update_.remotePoolAddresses.length;
        if (length == 0) revert CCIPTokenPoolConfig_RemotePoolsEmpty();
        for (uint256 i; i < length; ++i) {
            bytes calldata remotePool = update_.remotePoolAddresses[i];
            if (remotePool.length == 0) revert ICCIPTokenPoolAdmin.ZeroAddressNotAllowed();

            bytes32 remotePoolHash = keccak256(remotePool);
            for (uint256 j; j < i; ++j) {
                if (keccak256(update_.remotePoolAddresses[j]) == remotePoolHash) {
                    revert ICCIPTokenPoolAdmin.PoolAlreadyAdded(
                        update_.remoteChainSelector,
                        remotePool
                    );
                }
            }
        }
    }

    /// @notice Validates the arguments of `removeChain`. See `validateRemoveChain`.
    /// @param  chainSelector_ The chain selector of the route.
    function _validateRemoveChain(uint64 chainSelector_) internal view {
        _requireSupportedChain(chainSelector_);
    }

    /// @notice Validates the arguments of `setRemoteToken`. See `validateSetRemoteToken`.
    /// @param  chainSelector_ The chain selector of the route.
    /// @param  remoteToken_ The new remote token address.
    function _validateSetRemoteToken(
        uint64 chainSelector_,
        bytes calldata remoteToken_
    ) internal view {
        _requireSupportedChain(chainSelector_);
        if (remoteToken_.length == 0) revert CCIPTokenPoolConfig_RemoteTokenEmpty();
        if (keccak256(remoteToken_) == keccak256(_POOL.getRemoteToken(chainSelector_))) {
            revert CCIPTokenPoolConfig_RemoteTokenUnchanged();
        }
        if (
            !_POOL.getCurrentOutboundRateLimiterState(chainSelector_).isEnabled ||
            !_POOL.getCurrentInboundRateLimiterState(chainSelector_).isEnabled
        ) revert CCIPTokenPoolConfig_RateLimiterDisabled();
    }

    /// @notice Validates the arguments of `addRemotePool`. See `validateAddRemotePool`.
    /// @param  chainSelector_ The chain selector of the route.
    /// @param  remotePool_ The remote pool address to add.
    function _validateAddRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) internal view {
        _requireSupportedChain(chainSelector_);
        if (remotePool_.length == 0) revert ICCIPTokenPoolAdmin.ZeroAddressNotAllowed();
        if (_POOL.isRemotePool(chainSelector_, remotePool_)) {
            revert ICCIPTokenPoolAdmin.PoolAlreadyAdded(chainSelector_, remotePool_);
        }
    }

    /// @notice Validates the arguments of `removeRemotePool`. See `validateRemoveRemotePool`.
    /// @param  chainSelector_ The chain selector of the route.
    /// @param  remotePool_ The remote pool address to remove.
    function _validateRemoveRemotePool(
        uint64 chainSelector_,
        bytes calldata remotePool_
    ) internal view {
        _requireSupportedChain(chainSelector_);
        if (!_POOL.isRemotePool(chainSelector_, remotePool_)) {
            revert ICCIPTokenPoolAdmin.InvalidRemotePoolForChain(chainSelector_, remotePool_);
        }
        if (_POOL.getRemotePools(chainSelector_).length == 1) {
            revert CCIPTokenPoolConfig_LastRemotePool(chainSelector_);
        }
    }

    /// @notice Validates the arguments of `applyAllowListUpdates`. See
    ///         `validateApplyAllowListUpdates`.
    /// @param  removes_ The addresses to remove.
    /// @param  adds_ The addresses to add.
    function _validateApplyAllowListUpdates(
        address[] calldata removes_,
        address[] calldata adds_
    ) internal view {
        if (!_POOL.getAllowListEnabled()) revert ICCIPTokenPoolAdmin.AllowListNotEnabled();
        if (removes_.length == 0 && adds_.length == 0) {
            revert CCIPTokenPoolConfig_AllowListUpdatesEmpty();
        }
    }

    /// @notice Validates the arguments of `setChainRateLimits`. See
    ///         `validateSetChainRateLimits`.
    /// @param  chainSelector_ The chain selector of the route.
    /// @param  outbound_ The outbound rate limiter configuration.
    /// @param  inbound_ The inbound rate limiter configuration.
    function _validateSetChainRateLimits(
        uint64 chainSelector_,
        ICCIPRateLimiter.Config calldata outbound_,
        ICCIPRateLimiter.Config calldata inbound_
    ) internal view {
        _requireSupportedChain(chainSelector_);
        _validateRateLimiterConfig(outbound_);
        _validateRateLimiterConfig(inbound_);
    }

    /// @notice Validates a rate limiter configuration supplied to the pool.
    /// @dev    Reverts if:
    ///         - `config_` is disabled.
    ///         - `config_` has a zero rate or a rate that is not below its capacity
    ///           (`InvalidRateLimitRate`).
    function _validateRateLimiterConfig(ICCIPRateLimiter.Config memory config_) internal pure {
        if (!config_.isEnabled) revert CCIPTokenPoolConfig_RateLimiterDisabled();
        if (config_.rate == 0 || config_.rate >= config_.capacity) {
            revert ICCIPRateLimiter.InvalidRateLimitRate(config_);
        }
    }

    /// @notice Reverts with `NonExistentChain` unless `chainSelector_` is a configured route.
    function _requireSupportedChain(uint64 chainSelector_) internal view {
        if (!_POOL.isSupportedChain(chainSelector_)) {
            revert ICCIPTokenPoolAdmin.NonExistentChain(chainSelector_);
        }
    }

    /// @notice Reverts with `CCIPTokenPoolConfig_NotLiquidityContainer` unless the pool advertises
    ///         the liquidity container interface.
    function _requireLiquidityContainer() internal view {
        if (!_IS_LIQUIDITY_CONTAINER) revert CCIPTokenPoolConfig_NotLiquidityContainer();
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Replaces a route in one `applyChainUpdates` call, keeping its remote pools and
    ///         rate limiter configurations and setting a new remote token.
    /// @param  chainSelector_ The chain selector of the route.
    /// @param  remoteToken_ The new remote token address.
    /// @param  outbound_ The outbound bucket read before the replacement.
    /// @param  inbound_ The inbound bucket read before the replacement.
    function _replaceRoute(
        uint64 chainSelector_,
        bytes calldata remoteToken_,
        ICCIPRateLimiter.TokenBucket memory outbound_,
        ICCIPRateLimiter.TokenBucket memory inbound_
    ) internal {
        uint64[] memory chainsToRemove = new uint64[](1);
        chainsToRemove[0] = chainSelector_;

        ICCIPTokenPoolAdmin.ChainUpdate[]
            memory chainsToAdd = new ICCIPTokenPoolAdmin.ChainUpdate[](1);
        chainsToAdd[0] = ICCIPTokenPoolAdmin.ChainUpdate({
            remoteChainSelector: chainSelector_,
            remotePoolAddresses: _POOL.getRemotePools(chainSelector_),
            remoteTokenAddress: remoteToken_,
            outboundRateLimiterConfig: _toConfig(outbound_),
            inboundRateLimiterConfig: _toConfig(inbound_)
        });

        _POOL.applyChainUpdates(chainsToRemove, chainsToAdd);
    }

    /// @notice Returns the temporary configuration that clamps a full bucket down to a previous
    ///         fill level: `capacity = max(previousTokens_, _MIN_ENABLED_CAPACITY)` and
    ///         `rate = _MIN_ENABLED_RATE`.
    /// @param  previousTokens_ The fill level to restore, in token base units.
    /// @return config The temporary configuration.
    function _fillRestoreConfig(
        uint128 previousTokens_
    ) internal pure returns (ICCIPRateLimiter.Config memory config) {
        return
            ICCIPRateLimiter.Config({
                isEnabled: true,
                capacity: previousTokens_ < _MIN_ENABLED_CAPACITY
                    ? _MIN_ENABLED_CAPACITY
                    : previousTokens_,
                rate: _MIN_ENABLED_RATE
            });
    }

    /// @notice Returns the disabled rate limiter configuration.
    /// @return config The configuration `{isEnabled: true, capacity: 2, rate: 1}`.
    function _disabledRateLimiterConfig()
        internal
        pure
        returns (ICCIPRateLimiter.Config memory config)
    {
        return
            ICCIPRateLimiter.Config({
                isEnabled: true,
                capacity: _DISABLED_RATE_LIMIT_CAPACITY,
                rate: _DISABLED_RATE_LIMIT_RATE
            });
    }

    /// @notice Returns whether a bucket holds the disabled rate limiter configuration, comparing
    ///         `isEnabled`, `capacity` and `rate` only.
    /// @param  bucket_ The bucket to inspect.
    /// @return disabled True if the bucket is contained.
    function _isDisabledBucket(
        ICCIPRateLimiter.TokenBucket memory bucket_
    ) internal pure returns (bool disabled) {
        return
            bucket_.isEnabled &&
            bucket_.capacity == _DISABLED_RATE_LIMIT_CAPACITY &&
            bucket_.rate == _DISABLED_RATE_LIMIT_RATE;
    }

    /// @notice Extracts the configuration fields of a bucket.
    /// @param  bucket_ The bucket.
    /// @return config The `isEnabled`, `capacity` and `rate` of the bucket.
    function _toConfig(
        ICCIPRateLimiter.TokenBucket memory bucket_
    ) internal pure returns (ICCIPRateLimiter.Config memory config) {
        return
            ICCIPRateLimiter.Config({
                isEnabled: bucket_.isEnabled,
                capacity: bucket_.capacity,
                rate: bucket_.rate
            });
    }

    // ========== VERSION ========== //

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    /// @dev Adds `ICCIPTokenPoolConfig`, `IConfigOperator` and `IVersioned` to the interfaces
    ///      advertised by the bases.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(ICCIPTokenPoolConfig).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
