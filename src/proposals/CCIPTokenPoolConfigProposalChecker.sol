// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPLockReleaseTokenPool} from "src/external/bridge/ICCIPLockReleaseTokenPool.sol";
import {ICCIPTokenAdminRegistry} from "src/external/bridge/ICCIPTokenAdminRegistry.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ICCIPTokenPoolConfigProposalChecker} from "src/proposals/interfaces/ICCIPTokenPoolConfigProposalChecker.sol";

// Constants
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title  CCIPTokenPoolConfigProposalChecker
/// @notice Read-only checker of the preconditions of the CCIP bridge activation proposal
///         (`CCIPTokenPoolConfigProposal`), called as the first action of that proposal. It is
///         bound at construction to the Kernel, the config policy, the config timelock, the
///         lock/release pool, OHM, the TokenAdminRegistry, the ROLES module, the OCG timelock
///         and the DAO MS of one chain, and holds no state beyond those bindings.
/// @dev    The constructor rejects a zero address and a set of contracts that are not bound to
///         each other the way the proposal requires. `check` reads the live state only; a call
///         into it from the OCG timelock returns normally when every expectation holds and
///         reverts with the named error of the first one that does not, which reverts the whole
///         execution before any handover action runs and leaves the proposal queued.
contract CCIPTokenPoolConfigProposalChecker is ICCIPTokenPoolConfigProposalChecker {
    // ========== IMMUTABLES ========== //

    /// @notice The Kernel both policies are active in.
    Kernel public immutable KERNEL;

    /// @notice The config policy that owns the pool after the handover.
    ICCIPTokenPoolConfig public immutable CONFIG;

    /// @notice The config timelock that is the config operator after the handover.
    ICCIPTokenPoolConfigTimelock public immutable CONFIG_TIMELOCK;

    /// @notice The lock/release pool of OHM.
    ICCIPTokenPoolAdmin public immutable POOL;

    /// @notice The OHM token.
    IERC20 public immutable OHM;

    /// @notice The Chainlink TokenAdminRegistry of the chain.
    ICCIPTokenAdminRegistry public immutable REGISTRY;

    /// @notice The ROLES module of the Kernel.
    ROLESv1 public immutable ROLES;

    /// @notice The OCG timelock: the OHM administrator after the handover and the holder of
    ///         `admin`.
    address public immutable OCG_TIMELOCK;

    /// @notice The DAO MS: the pool owner before the handover and the holder of `bridge_admin`
    ///         after it.
    address public immutable DAO_MS;

    // ========== CONSTRUCTOR ========== //

    /// @notice Binds the checker to the contracts of one chain.
    /// @dev    Reverts if:
    ///         - Any argument is the zero address (`CCIPTokenPoolConfigProposalChecker_ZeroAddress`).
    ///         - `config_` does not report `pool_` as its pool, `configTimelock_` does not report
    ///           `config_` as its config, either policy does not report `kernel_` as its Kernel,
    ///           `kernel_` does not report `roles_` as its ROLES module, or `pool_` does not
    ///           report `ohm_` as its token
    ///           (`CCIPTokenPoolConfigProposalChecker_BindingMismatch`).
    ///         - `config_` reports that `pool_` is not a liquidity container
    ///           (`CCIPTokenPoolConfigProposalChecker_NotLiquidityContainer`).
    /// @param  kernel_ The Kernel.
    /// @param  config_ The config policy.
    /// @param  configTimelock_ The config timelock.
    /// @param  pool_ The lock/release pool.
    /// @param  ohm_ The OHM token.
    /// @param  registry_ The TokenAdminRegistry.
    /// @param  roles_ The ROLES module.
    /// @param  ocgTimelock_ The OCG timelock.
    /// @param  daoMS_ The DAO MS.
    // Every argument is rejected when zero by _requireNonZero, which the lint does not see
    // through
    // forge-lint: disable-next-item(missing-zero-check)
    constructor(
        address kernel_,
        address config_,
        address configTimelock_,
        address pool_,
        address ohm_,
        address registry_,
        address roles_,
        address ocgTimelock_,
        address daoMS_
    ) {
        _requireNonZero(kernel_, "kernel");
        _requireNonZero(config_, "config");
        _requireNonZero(configTimelock_, "configTimelock");
        _requireNonZero(pool_, "pool");
        _requireNonZero(ohm_, "ohm");
        _requireNonZero(registry_, "registry");
        _requireNonZero(roles_, "roles");
        _requireNonZero(ocgTimelock_, "ocgTimelock");
        _requireNonZero(daoMS_, "daoMS");

        _requireBinding("CCIPTokenPoolConfig pool", ICCIPTokenPoolConfig(config_).pool(), pool_);
        _requireBinding(
            "CCIPTokenPoolConfigTimelock config",
            ICCIPTokenPoolConfigTimelock(configTimelock_).config(),
            config_
        );
        _requireBinding("CCIPTokenPoolConfig kernel", address(Policy(config_).kernel()), kernel_);
        _requireBinding(
            "CCIPTokenPoolConfigTimelock kernel",
            address(Policy(configTimelock_).kernel()),
            kernel_
        );
        _requireBinding(
            "ROLES module",
            address(Kernel(kernel_).getModuleForKeycode(toKeycode("ROLES"))),
            roles_
        );
        _requireBinding("pool token", ICCIPTokenPoolAdmin(pool_).getToken(), ohm_);
        if (!ICCIPTokenPoolConfig(config_).isLiquidityContainer()) {
            revert CCIPTokenPoolConfigProposalChecker_NotLiquidityContainer(pool_);
        }

        KERNEL = Kernel(kernel_);
        CONFIG = ICCIPTokenPoolConfig(config_);
        CONFIG_TIMELOCK = ICCIPTokenPoolConfigTimelock(configTimelock_);
        POOL = ICCIPTokenPoolAdmin(pool_);
        OHM = IERC20(ohm_);
        REGISTRY = ICCIPTokenAdminRegistry(registry_);
        ROLES = ROLESv1(roles_);
        OCG_TIMELOCK = ocgTimelock_;
        DAO_MS = daoMS_;
    }

    // ========== CHECK ========== //

    /// @inheritdoc ICCIPTokenPoolConfigProposalChecker
    /// @dev    Reverts if, in this order:
    ///         - The config policy or the config timelock is not active in the Kernel
    ///           (`CCIPTokenPoolConfigProposalChecker_PolicyNotActive`).
    ///         - The Kernel does not report the bound ROLES module
    ///           (`CCIPTokenPoolConfigProposalChecker_BindingMismatch`).
    ///         - The pool registered for OHM in the TokenAdminRegistry is not the bound pool
    ///           (`CCIPTokenPoolConfigProposalChecker_RegisteredPoolMismatch`).
    ///         - The OCG timelock does not hold `admin`
    ///           (`CCIPTokenPoolConfigProposalChecker_MissingRole`).
    ///         - The OCG timelock is not the pending OHM administrator while `acceptAdminRole`
    ///           is set, or not the OHM administrator while it is not
    ///           (`CCIPTokenPoolConfigProposalChecker_OhmAdministratorMismatch`).
    ///         - The DAO MS holds `bridge_admin` while `grantBridgeAdmin` is set, or lacks it
    ///           while it is not (`CCIPTokenPoolConfigProposalChecker_BridgeAdminRoleMismatch`).
    ///         - The config policy is enabled while `enableConfig` is set, or disabled while
    ///           it is not (`CCIPTokenPoolConfigProposalChecker_ConfigEnabledMismatch`).
    ///         - The pool owner is not the DAO MS while `acceptPoolOwnership` is set, or not
    ///           the config policy while it is not
    ///           (`CCIPTokenPoolConfigProposalChecker_PoolOwnerMismatch`).
    ///         - The config operator is the config timelock while `setConfigOperator` is set,
    ///           or is not while it is not
    ///           (`CCIPTokenPoolConfigProposalChecker_ConfigOperatorMismatch`).
    ///         - The pool rebalancer equals `rebalancer` while `setRebalancer` is set, or
    ///           differs from it while it is not
    ///           (`CCIPTokenPoolConfigProposalChecker_RebalancerMismatch`).
    ///         - The native rate limit admin equals `rateLimitAdmin` while `setRateLimitAdmin`
    ///           is set, or differs from it while it is not
    ///           (`CCIPTokenPoolConfigProposalChecker_RateLimitAdminMismatch`).
    ///         - The config timelock is enabled while `enableTimelock` is set, or disabled
    ///           while it is not (`CCIPTokenPoolConfigProposalChecker_TimelockEnabledMismatch`).
    ///         - The pool supports a chain selector of `routesToAdd`, the first one in list
    ///           order (`CCIPTokenPoolConfigProposalChecker_RouteAlreadyExists`).
    ///         - The OHM balance of the pool is below `minimumPoolBacking`
    ///           (`CCIPTokenPoolConfigProposalChecker_BackingTooLow`).
    // One check per proposal action, in action order; a split would hide the order in which
    // the errors are reported
    // forge-lint: disable-next-item(cyclomatic-complexity)
    function check(Expectations calldata expectations_) external view override {
        // Bindings every action relies on
        _requireActive(address(CONFIG));
        _requireActive(address(CONFIG_TIMELOCK));
        _requireBinding(
            "ROLES module",
            address(KERNEL.getModuleForKeycode(toKeycode("ROLES"))),
            address(ROLES)
        );
        ICCIPTokenAdminRegistry.TokenConfig memory tokenConfig = REGISTRY.getTokenConfig(
            address(OHM)
        );
        if (tokenConfig.tokenPool != address(POOL)) {
            revert CCIPTokenPoolConfigProposalChecker_RegisteredPoolMismatch(
                tokenConfig.tokenPool,
                address(POOL)
            );
        }
        if (!ROLES.hasRole(OCG_TIMELOCK, ADMIN_ROLE)) {
            revert CCIPTokenPoolConfigProposalChecker_MissingRole(ADMIN_ROLE, OCG_TIMELOCK);
        }

        // The OHM administrator: pending to the OCG timelock before the acceptance, the OCG
        // timelock after it
        address administrator = expectations_.acceptAdminRole
            ? tokenConfig.pendingAdministrator
            : tokenConfig.administrator;
        if (administrator != OCG_TIMELOCK) {
            revert CCIPTokenPoolConfigProposalChecker_OhmAdministratorMismatch(
                tokenConfig.administrator,
                tokenConfig.pendingAdministrator,
                expectations_.acceptAdminRole
            );
        }

        // bridge_admin: not held before the grant, held after it
        bool bridgeAdminHeld = ROLES.hasRole(DAO_MS, BRIDGE_ADMIN_ROLE);
        if (bridgeAdminHeld == expectations_.grantBridgeAdmin) {
            revert CCIPTokenPoolConfigProposalChecker_BridgeAdminRoleMismatch(
                bridgeAdminHeld,
                expectations_.grantBridgeAdmin
            );
        }

        // The config policy: disabled before its enable, enabled after it
        bool configEnabled = IEnabler(address(CONFIG)).isEnabled();
        if (configEnabled == expectations_.enableConfig) {
            revert CCIPTokenPoolConfigProposalChecker_ConfigEnabledMismatch(
                configEnabled,
                expectations_.enableConfig
            );
        }

        // The pool owner: the DAO MS before the acceptance, the config policy after it. The
        // pending owner has no read, so the acceptance precondition stops at the owner.
        address expectedOwner = expectations_.acceptPoolOwnership ? DAO_MS : address(CONFIG);
        address owner = POOL.owner();
        if (owner != expectedOwner) {
            revert CCIPTokenPoolConfigProposalChecker_PoolOwnerMismatch(owner, expectedOwner);
        }

        // Each setter is included exactly when the live value differs from the desired one,
        // since the config policy rejects a setter call that carries the value already held
        address configOperator = IConfigOperator(address(CONFIG)).configOperator();
        bool operatorSet = configOperator == address(CONFIG_TIMELOCK);
        if (operatorSet == expectations_.setConfigOperator) {
            revert CCIPTokenPoolConfigProposalChecker_ConfigOperatorMismatch(
                configOperator,
                address(CONFIG_TIMELOCK),
                expectations_.setConfigOperator
            );
        }

        address rebalancer = ICCIPLockReleaseTokenPool(address(POOL)).getRebalancer();
        bool rebalancerSet = rebalancer == expectations_.rebalancer;
        if (rebalancerSet == expectations_.setRebalancer) {
            revert CCIPTokenPoolConfigProposalChecker_RebalancerMismatch(
                rebalancer,
                expectations_.rebalancer,
                expectations_.setRebalancer
            );
        }

        address rateLimitAdmin = POOL.getRateLimitAdmin();
        bool rateLimitAdminSet = rateLimitAdmin == expectations_.rateLimitAdmin;
        if (rateLimitAdminSet == expectations_.setRateLimitAdmin) {
            revert CCIPTokenPoolConfigProposalChecker_RateLimitAdminMismatch(
                rateLimitAdmin,
                expectations_.rateLimitAdmin,
                expectations_.setRateLimitAdmin
            );
        }

        // The config timelock: disabled before its enable, enabled after it
        bool timelockEnabled = IEnabler(address(CONFIG_TIMELOCK)).isEnabled();
        if (timelockEnabled == expectations_.enableTimelock) {
            revert CCIPTokenPoolConfigProposalChecker_TimelockEnabledMismatch(
                timelockEnabled,
                expectations_.enableTimelock
            );
        }

        // The routes the proposal opens are absent from the pool
        _requireRoutesAbsent(expectations_.routesToAdd);

        // The backing
        uint256 balance = OHM.balanceOf(address(POOL));
        if (balance < expectations_.minimumPoolBacking) {
            revert CCIPTokenPoolConfigProposalChecker_BackingTooLow(
                balance,
                expectations_.minimumPoolBacking
            );
        }
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Reverts unless the policy is active in the Kernel.
    function _requireActive(address policy_) internal view {
        if (!KERNEL.isPolicyActive(Policy(policy_))) {
            revert CCIPTokenPoolConfigProposalChecker_PolicyNotActive(policy_);
        }
    }

    /// @notice Reverts on the first chain selector of the list that the pool supports.
    // The list holds the handful of selectors one proposal opens, each read once from the pool,
    // and the first one the pool supports is the named failure
    // forge-lint: disable-next-item(calls-loop,require-revert-in-loop)
    function _requireRoutesAbsent(uint64[] calldata chainSelectors_) internal view {
        for (uint256 i = 0; i < chainSelectors_.length; ++i) {
            if (POOL.isSupportedChain(chainSelectors_[i])) {
                revert CCIPTokenPoolConfigProposalChecker_RouteAlreadyExists(chainSelectors_[i]);
            }
        }
    }

    /// @notice Reverts when the address is zero.
    function _requireNonZero(address value_, string memory parameter_) internal pure {
        if (value_ == address(0)) {
            revert CCIPTokenPoolConfigProposalChecker_ZeroAddress(parameter_);
        }
    }

    /// @notice Reverts unless the value a bound contract reports equals the argument.
    function _requireBinding(
        string memory binding_,
        address actual_,
        address expected_
    ) internal pure {
        if (actual_ != expected_) {
            revert CCIPTokenPoolConfigProposalChecker_BindingMismatch(binding_, actual_, expected_);
        }
    }
}
