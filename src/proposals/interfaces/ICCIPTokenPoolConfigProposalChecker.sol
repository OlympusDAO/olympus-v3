// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title  ICCIPTokenPoolConfigProposalChecker
/// @notice The interface of the read-only checker that the CCIP bridge activation proposal calls
///         as its first action. The checker is bound at construction to the contracts the
///         proposal acts on and asserts, at execution time, that the live state still matches
///         the state the proposal was built against: the precondition of every handover action
///         the proposal includes, the end state of every handover action it does not include,
///         the absence of every route it opens, and the minimum backing of the pool. It holds
///         no role and changes no state; the first expectation that does not hold reverts with
///         a named error, which fails the whole proposal before any handover action runs.
/// @dev    The pool is an `Ownable2Step` without a getter of its pending owner, so the
///         precondition of the ownership acceptance is narrowed to the current owner: a pending
///         owner repointed after the build is not detected here and surfaces at the acceptance
///         action instead.
interface ICCIPTokenPoolConfigProposalChecker {
    // ========== DATA STRUCTURES ========== //

    /// @notice The expectations of one proposal build. Each `bool` says whether the proposal
    ///         includes the handover action of the same name; the checker asserts the
    ///         precondition the action needs when it is included and the end state the action
    ///         leaves when it is not.
    /// @param acceptAdminRole      The OCG timelock is the pending OHM administrator in the
    ///                             TokenAdminRegistry when true, the OHM administrator otherwise.
    /// @param grantBridgeAdmin     The DAO MS does not hold `bridge_admin` when true, holds it
    ///                             otherwise.
    /// @param enableConfig         The config policy is disabled when true, enabled otherwise.
    /// @param acceptPoolOwnership  The DAO MS owns the pool when true, the config policy
    ///                             otherwise.
    /// @param setConfigOperator    The config operator of the config policy differs from the
    ///                             config timelock when true, is the config timelock otherwise.
    /// @param setRebalancer        The pool rebalancer differs from `rebalancer` when true,
    ///                             equals it otherwise.
    /// @param setRateLimitAdmin    The native rate limit admin of the pool differs from
    ///                             `rateLimitAdmin` when true, equals it otherwise.
    /// @param enableTimelock       The config timelock is disabled when true, enabled otherwise.
    /// @param rebalancer           The desired pool rebalancer.
    /// @param rateLimitAdmin       The desired native rate limit admin of the pool.
    /// @param routesToAdd          The chain selectors of the routes the proposal opens, none of
    ///                             which the pool supports.
    /// @param minimumPoolBacking   The OHM balance the pool holds at least, in OHM base units.
    struct Expectations {
        bool acceptAdminRole;
        bool grantBridgeAdmin;
        bool enableConfig;
        bool acceptPoolOwnership;
        bool setConfigOperator;
        bool setRebalancer;
        bool setRateLimitAdmin;
        bool enableTimelock;
        address rebalancer;
        address rateLimitAdmin;
        uint64[] routesToAdd;
        uint256 minimumPoolBacking;
    }

    // ========== ERRORS ========== //

    /// @notice Thrown when a constructor argument is the zero address.
    /// @param parameter The name of the argument.
    error CCIPTokenPoolConfigProposalChecker_ZeroAddress(string parameter);

    /// @notice Thrown when a constructor argument is not bound to another one the way the
    ///         proposal requires, or when the Kernel no longer reports the bound ROLES module
    ///         at check time.
    /// @param binding The name of the binding.
    /// @param actual The value the bound contract reports.
    /// @param expected The bound value it was compared with.
    error CCIPTokenPoolConfigProposalChecker_BindingMismatch(
        string binding,
        address actual,
        address expected
    );

    /// @notice Thrown when the config policy reports that the pool is not a liquidity container,
    ///         so the pool has no rebalancer to check.
    /// @param pool The pool.
    error CCIPTokenPoolConfigProposalChecker_NotLiquidityContainer(address pool);

    /// @notice Thrown when a policy is not active in the Kernel.
    /// @param policy The policy.
    error CCIPTokenPoolConfigProposalChecker_PolicyNotActive(address policy);

    /// @notice Thrown when the pool registered for OHM in the TokenAdminRegistry is not the
    ///         bound pool.
    /// @param registered The registered pool.
    /// @param expected The bound pool.
    error CCIPTokenPoolConfigProposalChecker_RegisteredPoolMismatch(
        address registered,
        address expected
    );

    /// @notice Thrown when an account does not hold a required role.
    /// @param role The role.
    /// @param account The account.
    error CCIPTokenPoolConfigProposalChecker_MissingRole(bytes32 role, address account);

    /// @notice Thrown when the OHM administrator position in the TokenAdminRegistry does not
    ///         match the expectation: the OCG timelock is not the pending administrator while
    ///         the acceptance is included, or is not the administrator while it is not.
    /// @param administrator The administrator read.
    /// @param pendingAdministrator The pending administrator read.
    /// @param acceptIncluded Whether the acceptance is included in the proposal.
    error CCIPTokenPoolConfigProposalChecker_OhmAdministratorMismatch(
        address administrator,
        address pendingAdministrator,
        bool acceptIncluded
    );

    /// @notice Thrown when the DAO MS holds `bridge_admin` while the grant is included, or
    ///         lacks it while the grant is not.
    /// @param held Whether the DAO MS holds the role.
    /// @param grantIncluded Whether the grant is included in the proposal.
    error CCIPTokenPoolConfigProposalChecker_BridgeAdminRoleMismatch(bool held, bool grantIncluded);

    /// @notice Thrown when the config policy is enabled while its `enable` is included, or
    ///         disabled while it is not.
    /// @param enabled Whether the config policy is enabled.
    /// @param enableIncluded Whether the `enable` is included in the proposal.
    error CCIPTokenPoolConfigProposalChecker_ConfigEnabledMismatch(
        bool enabled,
        bool enableIncluded
    );

    /// @notice Thrown when the pool owner is not the expected one: the DAO MS while the
    ///         ownership acceptance is included, the config policy while it is not.
    /// @param owner The pool owner read.
    /// @param expected The expected owner.
    error CCIPTokenPoolConfigProposalChecker_PoolOwnerMismatch(address owner, address expected);

    /// @notice Thrown when the config operator of the config policy is the config timelock
    ///         while the rotation is included, or is not while the rotation is not.
    /// @param configOperator The config operator read.
    /// @param desired The config timelock.
    /// @param setIncluded Whether the rotation is included in the proposal.
    error CCIPTokenPoolConfigProposalChecker_ConfigOperatorMismatch(
        address configOperator,
        address desired,
        bool setIncluded
    );

    /// @notice Thrown when the pool rebalancer equals the desired one while the setter is
    ///         included, or differs from it while the setter is not.
    /// @param rebalancer The rebalancer read.
    /// @param desired The desired rebalancer.
    /// @param setIncluded Whether the setter is included in the proposal.
    error CCIPTokenPoolConfigProposalChecker_RebalancerMismatch(
        address rebalancer,
        address desired,
        bool setIncluded
    );

    /// @notice Thrown when the native rate limit admin of the pool equals the desired one while
    ///         the setter is included, or differs from it while the setter is not.
    /// @param rateLimitAdmin The rate limit admin read.
    /// @param desired The desired rate limit admin.
    /// @param setIncluded Whether the setter is included in the proposal.
    error CCIPTokenPoolConfigProposalChecker_RateLimitAdminMismatch(
        address rateLimitAdmin,
        address desired,
        bool setIncluded
    );

    /// @notice Thrown when the config timelock is enabled while its `enable` is included, or
    ///         disabled while it is not.
    /// @param enabled Whether the config timelock is enabled.
    /// @param enableIncluded Whether the `enable` is included in the proposal.
    error CCIPTokenPoolConfigProposalChecker_TimelockEnabledMismatch(
        bool enabled,
        bool enableIncluded
    );

    /// @notice Thrown when the pool already supports a route the proposal opens.
    /// @param chainSelector The chain selector of the route.
    error CCIPTokenPoolConfigProposalChecker_RouteAlreadyExists(uint64 chainSelector);

    /// @notice Thrown when the pool holds less OHM than the minimum backing.
    /// @param balance The OHM balance of the pool, in OHM base units.
    /// @param minimum The minimum backing, in OHM base units.
    error CCIPTokenPoolConfigProposalChecker_BackingTooLow(uint256 balance, uint256 minimum);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Asserts the expectations against the live state and returns normally when every
    ///         one of them holds. Intended to be the first action of the CCIP bridge activation
    ///         proposal, so that a precondition that no longer holds at execution fails the
    ///         proposal with a named error before any handover action runs; callable by anyone
    ///         at any time, since it reads only.
    /// @dev    The checks run in the order of the proposal actions, after the bindings that every
    ///         action relies on (both policies active in the Kernel, the Kernel reporting the
    ///         bound ROLES module, the bound pool registered for OHM, the OCG timelock holding
    ///         `admin`), and the first failing one reverts.
    ///         The pool owner is compared with the expected one only: the pool exposes no read
    ///         of its pending owner.
    /// @param  expectations_ The expectations of the proposal build.
    function check(Expectations calldata expectations_) external view;
}
