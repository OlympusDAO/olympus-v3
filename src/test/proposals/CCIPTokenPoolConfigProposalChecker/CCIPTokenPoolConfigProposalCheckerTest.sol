// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

// Interfaces
import {IBurnMintERC20} from "@chainlink-ccip-1.6.0/shared/token/ERC20/IBurnMintERC20.sol";
import {IERC20} from "@chainlink-ccip-1.6.0/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ICCIPRateLimiter} from "src/external/bridge/ICCIPRateLimiter.sol";
import {ICCIPTokenPoolAdmin} from "src/external/bridge/ICCIPTokenPoolAdmin.sol";
import {ICCIPTokenPoolConfigProposalChecker} from "src/proposals/interfaces/ICCIPTokenPoolConfigProposalChecker.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";

import {BurnMintTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/BurnMintTokenPool.sol";
import {LockReleaseTokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/LockReleaseTokenPool.sol";
import {TokenAdminRegistry} from "@chainlink-ccip-1.6.0/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {CCIPTokenPoolConfig} from "src/policies/bridge/CCIPTokenPoolConfig.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {CCIPTokenPoolConfigProposalChecker} from "src/proposals/CCIPTokenPoolConfigProposalChecker.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockCCIPRouter} from "src/test/policies/bridge/mocks/MockCCIPRouter.sol";
import {MockRMNProxy} from "src/test/policies/bridge/mocks/MockRMNProxy.sol";

/// @notice Shared rig of the `CCIPTokenPoolConfigProposalChecker` suites: the Kernel stack, a
///         real Chainlink lock/release pool over MockOhm owned by the DAO MS, the config policy
///         and the config timelock active in the Kernel, a real TokenAdminRegistry with OHM
///         administered by the DAO MS and the pool registered, and the checker bound to all of
///         them.
/// @dev    Default state after setUp: the mainnet state after Phase B. The OCG timelock holds
///         `admin`; the DAO MS owns the pool, has proposed the config policy as its new owner
///         and has nominated the OCG timelock as the OHM administrator; both policies are
///         disabled, the config operator is unset, the pool rebalancer and rate limit admin
///         are zero, the pool serves no route and holds exactly the minimum backing; the DAO
///         MS does not hold `bridge_admin`. The desired rebalancer is the OCG timelock and the
///         desired rate limit admin is zero, so every conditional action except the rate limit
///         admin setter is included in the Phase B expectations.
///
///         Prank convention: read every contract handle and address needed for a pranked call
///         before vm.prank, because any external view call placed between the prank and the
///         target call consumes the prank.
abstract contract CCIPTokenPoolConfigProposalCheckerTest is Test {
    // ========== KERNEL STACK ========== //

    Kernel internal kernel;
    OlympusRoles internal rolesModule;
    RolesAdmin internal rolesAdmin;

    // ========== POOL RIG ========== //

    MockOhm internal ohm;
    MockCCIPRouter internal ccipRouter;
    MockRMNProxy internal rmnProxy;
    LockReleaseTokenPool internal pool;
    TokenAdminRegistry internal registry;

    // ========== POLICIES ========== //

    CCIPTokenPoolConfig internal config;
    CCIPTokenPoolConfigTimelock internal timelock;

    // ========== CHECKER UNDER TEST ========== //

    CCIPTokenPoolConfigProposalChecker internal checker;

    // ========== ACCOUNTS ========== //

    address internal ocgTimelock;
    address internal daoMS;
    address internal stranger;

    // ========== CONSTANTS ========== //

    uint32 internal constant GRACE_PERIOD = 3 days;
    uint48 internal constant TIMELOCK_DELAY = 1 days;
    uint8 internal constant OHM_DECIMALS = 9;

    uint64 internal constant CHAIN_SELECTOR_A = 1111;
    uint64 internal constant CHAIN_SELECTOR_B = 2222;

    /// @notice The minimum backing the Phase B expectations carry, in OHM base units
    ///         (9 decimals): 100 OHM, which setUp mints to the pool.
    uint256 internal constant MIN_BACKING = 100_000_000_000;

    /// @notice Rate limiter constants of the routes the rig adds, in OHM base units.
    uint128 internal constant ROUTE_CAPACITY = 10_000;
    uint128 internal constant ROUTE_RATE = 100;

    // ========== SETUP ========== //

    function setUp() public virtual {
        ocgTimelock = makeAddr("ocgTimelock");
        daoMS = makeAddr("daoMS");
        stranger = makeAddr("stranger");

        ohm = new MockOhm("Olympus", "OHM", OHM_DECIMALS);
        vm.label(address(ohm), "ohm");
        ccipRouter = new MockCCIPRouter();
        vm.label(address(ccipRouter), "ccipRouter");
        rmnProxy = new MockRMNProxy();
        vm.label(address(rmnProxy), "rmnProxy");

        // The DAO MS deploys and therefore owns the pool
        vm.prank(daoMS);
        pool = new LockReleaseTokenPool(
            IERC20(address(ohm)),
            OHM_DECIMALS,
            new address[](0),
            address(rmnProxy),
            true,
            address(ccipRouter)
        );
        vm.label(address(pool), "pool");

        kernel = new Kernel();
        vm.label(address(kernel), "kernel");
        rolesModule = new OlympusRoles(kernel);
        vm.label(address(rolesModule), "rolesModule");
        rolesAdmin = new RolesAdmin(kernel);
        vm.label(address(rolesAdmin), "rolesAdmin");
        kernel.executeAction(Actions.InstallModule, address(rolesModule));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        rolesAdmin.grantRole(ADMIN_ROLE, ocgTimelock);

        config = new CCIPTokenPoolConfig(kernel, address(pool), GRACE_PERIOD);
        vm.label(address(config), "config");
        timelock = new CCIPTokenPoolConfigTimelock(
            kernel,
            address(config),
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );
        vm.label(address(timelock), "timelock");
        kernel.executeAction(Actions.ActivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));

        // The registry: OHM administered by the DAO MS, the pool registered
        registry = new TokenAdminRegistry();
        vm.label(address(registry), "registry");
        registry.proposeAdministrator(address(ohm), daoMS);
        _daoAcceptAdminRole();
        _daoSetPool(address(pool));

        // Phase B: the pool ownership proposed, the OHM administrator nominated
        _daoProposePoolOwner(address(config));
        _daoNominateRegistryAdmin(ocgTimelock);

        // The funding
        ohm.mint(address(pool), MIN_BACKING);

        checker = _newChecker(
            address(kernel),
            address(config),
            address(timelock),
            address(pool),
            address(ohm),
            address(registry),
            address(rolesModule),
            ocgTimelock,
            daoMS
        );
        vm.label(address(checker), "checker");
    }

    // ========== DEPLOY HELPERS ========== //

    function _newChecker(
        address kernel_,
        address config_,
        address configTimelock_,
        address pool_,
        address ohm_,
        address registry_,
        address roles_,
        address ocgTimelock_,
        address daoMS_
    ) internal returns (CCIPTokenPoolConfigProposalChecker newChecker) {
        return
            new CCIPTokenPoolConfigProposalChecker(
                kernel_,
                config_,
                configTimelock_,
                pool_,
                ohm_,
                registry_,
                roles_,
                ocgTimelock_,
                daoMS_
            );
    }

    /// @notice A second lock/release pool over the rig's token, owned by the test contract.
    function _newLockReleasePool() internal returns (LockReleaseTokenPool newPool) {
        newPool = new LockReleaseTokenPool(
            IERC20(address(ohm)),
            OHM_DECIMALS,
            new address[](0),
            address(rmnProxy),
            true,
            address(ccipRouter)
        );
        vm.label(address(newPool), "otherPool");
        return newPool;
    }

    /// @notice A burn/mint pool over the rig's token, owned by the test contract.
    function _newBurnMintPool() internal returns (BurnMintTokenPool newPool) {
        newPool = new BurnMintTokenPool(
            IBurnMintERC20(address(ohm)),
            OHM_DECIMALS,
            new address[](0),
            address(rmnProxy),
            address(ccipRouter)
        );
        vm.label(address(newPool), "burnMintPool");
        return newPool;
    }

    /// @notice A fresh, unactivated config policy over a pool, on the rig's Kernel.
    function _newConfig(address pool_) internal returns (CCIPTokenPoolConfig newConfig) {
        newConfig = new CCIPTokenPoolConfig(kernel, pool_, GRACE_PERIOD);
        vm.label(address(newConfig), "otherConfig");
        return newConfig;
    }

    /// @notice A fresh, unactivated timelock bound to a config policy, on the rig's Kernel.
    function _newTimelockFor(
        address config_
    ) internal returns (CCIPTokenPoolConfigTimelock newTimelock) {
        newTimelock = new CCIPTokenPoolConfigTimelock(
            kernel,
            config_,
            TIMELOCK_DELAY,
            GRACE_PERIOD
        );
        vm.label(address(newTimelock), "otherTimelock");
        return newTimelock;
    }

    // ========== EXPECTATION FACTORIES ========== //

    /// @notice The expectations of a build on the default state: every conditional action
    ///         included except the rate limit admin setter, both routes to add, the minimum
    ///         backing.
    function _phaseBExpectations()
        internal
        view
        returns (ICCIPTokenPoolConfigProposalChecker.Expectations memory expectations)
    {
        uint64[] memory routes = new uint64[](2);
        routes[0] = CHAIN_SELECTOR_A;
        routes[1] = CHAIN_SELECTOR_B;
        return
            ICCIPTokenPoolConfigProposalChecker.Expectations({
                acceptAdminRole: true,
                grantBridgeAdmin: true,
                enableConfig: true,
                acceptPoolOwnership: true,
                setConfigOperator: true,
                setRebalancer: true,
                setRateLimitAdmin: false,
                enableTimelock: true,
                rebalancer: ocgTimelock,
                rateLimitAdmin: address(0),
                routesToAdd: routes,
                minimumPoolBacking: MIN_BACKING
            });
    }

    /// @notice The expectations of the end state the proposal leaves: nothing included, no
    ///         route to add, the same desired values and minimum backing.
    function _endStateExpectations()
        internal
        view
        returns (ICCIPTokenPoolConfigProposalChecker.Expectations memory expectations)
    {
        return
            ICCIPTokenPoolConfigProposalChecker.Expectations({
                acceptAdminRole: false,
                grantBridgeAdmin: false,
                enableConfig: false,
                acceptPoolOwnership: false,
                setConfigOperator: false,
                setRebalancer: false,
                setRateLimitAdmin: false,
                enableTimelock: false,
                rebalancer: ocgTimelock,
                rateLimitAdmin: address(0),
                routesToAdd: new uint64[](0),
                minimumPoolBacking: MIN_BACKING
            });
    }

    // ========== STATE TRANSITIONS ========== //

    /// @notice The DAO MS accepts the OHM administrator role.
    function _daoAcceptAdminRole() internal {
        address ohmAddress = address(ohm);
        vm.prank(daoMS);
        registry.acceptAdminRole(ohmAddress);
    }

    /// @notice The DAO MS, as the OHM administrator, registers a pool for OHM.
    function _daoSetPool(address pool_) internal {
        address ohmAddress = address(ohm);
        vm.prank(daoMS);
        registry.setPool(ohmAddress, pool_);
    }

    /// @notice The DAO MS, as the OHM administrator, nominates another administrator.
    function _daoNominateRegistryAdmin(address nominee_) internal {
        address ohmAddress = address(ohm);
        vm.prank(daoMS);
        registry.transferAdminRole(ohmAddress, nominee_);
    }

    /// @notice The OCG timelock accepts the OHM administrator role.
    function _ocgAcceptAdminRole() internal {
        address ohmAddress = address(ohm);
        vm.prank(ocgTimelock);
        registry.acceptAdminRole(ohmAddress);
    }

    /// @notice The DAO MS, as the pool owner, proposes another pool owner.
    function _daoProposePoolOwner(address newOwner_) internal {
        vm.prank(daoMS);
        pool.transferOwnership(newOwner_);
    }

    /// @notice The DAO MS, as the pool owner, sets the pool rebalancer directly.
    function _daoSetRebalancer(address rebalancer_) internal {
        vm.prank(daoMS);
        pool.setRebalancer(rebalancer_);
    }

    /// @notice The DAO MS, as the pool owner, sets the native rate limit admin directly.
    function _daoSetRateLimitAdmin(address rateLimitAdmin_) internal {
        vm.prank(daoMS);
        pool.setRateLimitAdmin(rateLimitAdmin_);
    }

    /// @notice The DAO MS, as the pool owner, adds a route directly on the pool.
    function _daoAddRoute(uint64 chainSelector_) internal {
        uint64[] memory removals = new uint64[](0);
        ICCIPTokenPoolAdmin.ChainUpdate[] memory additions = new ICCIPTokenPoolAdmin.ChainUpdate[](
            1
        );
        additions[0] = _chainUpdate(chainSelector_);
        vm.prank(daoMS);
        ICCIPTokenPoolAdmin(address(pool)).applyChainUpdates(removals, additions);
    }

    /// @notice The OCG timelock enables the config policy.
    function _ocgEnableConfig() internal {
        vm.prank(ocgTimelock);
        config.enable("");
    }

    /// @notice The OCG timelock enables the config timelock.
    function _ocgEnableTimelock() internal {
        vm.prank(ocgTimelock);
        timelock.enable("");
    }

    /// @notice The OCG timelock accepts the pool ownership through the enabled config policy.
    function _ocgAcceptPoolOwnership() internal {
        vm.prank(ocgTimelock);
        config.acceptPoolOwnership();
    }

    /// @notice The OCG timelock sets the config operator of the enabled config policy.
    function _ocgSetConfigOperator(address operator_) internal {
        vm.prank(ocgTimelock);
        config.setConfigOperator(operator_);
    }

    /// @notice The OCG timelock sets the pool rebalancer through the enabled config policy,
    ///         which must own the pool.
    function _ocgSetRebalancer(address rebalancer_) internal {
        vm.prank(ocgTimelock);
        config.setRebalancer(rebalancer_);
    }

    /// @notice The OCG timelock adds a route through the enabled config policy, which must own
    ///         the pool.
    function _ocgAddRoute(uint64 chainSelector_) internal {
        ICCIPTokenPoolAdmin.ChainUpdate memory update = _chainUpdate(chainSelector_);
        vm.prank(ocgTimelock);
        config.addChain(update);
    }

    /// @notice The whole handover the proposal performs on the default state, in the proposal's
    ///         order, so that the end-state expectations hold afterwards.
    function _executeHandover() internal {
        _ocgAcceptAdminRole();
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, daoMS);
        _ocgEnableConfig();
        _ocgAcceptPoolOwnership();
        _ocgSetConfigOperator(address(timelock));
        _ocgSetRebalancer(ocgTimelock);
        _ocgEnableTimelock();
    }

    // ========== FACTORIES ========== //

    /// @notice A route toward the chain selector with EVM-shaped remote addresses and enabled
    ///         limiters of the rig's constants.
    function _chainUpdate(
        uint64 chainSelector_
    ) internal returns (ICCIPTokenPoolAdmin.ChainUpdate memory update) {
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(makeAddr("remotePool"));
        return
            ICCIPTokenPoolAdmin.ChainUpdate({
                remoteChainSelector: chainSelector_,
                remotePoolAddresses: remotePools,
                remoteTokenAddress: abi.encode(makeAddr("remoteToken")),
                outboundRateLimiterConfig: ICCIPRateLimiter.Config({
                    isEnabled: true,
                    capacity: ROUTE_CAPACITY,
                    rate: ROUTE_RATE
                }),
                inboundRateLimiterConfig: ICCIPRateLimiter.Config({
                    isEnabled: true,
                    capacity: ROUTE_CAPACITY,
                    rate: ROUTE_RATE
                })
            });
    }

    // ========== REVERT EXPECTATION HELPERS ========== //

    function _expectRevertZeroAddress(string memory parameter_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_ZeroAddress
                    .selector,
                parameter_
            )
        );
    }

    function _expectRevertBindingMismatch(
        string memory binding_,
        address actual_,
        address expected_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_BindingMismatch
                    .selector,
                binding_,
                actual_,
                expected_
            )
        );
    }

    function _expectRevertPolicyNotActive(address policy_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_PolicyNotActive
                    .selector,
                policy_
            )
        );
    }

    function _expectRevertOhmAdministratorMismatch(
        address administrator_,
        address pendingAdministrator_,
        bool acceptIncluded_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_OhmAdministratorMismatch
                    .selector,
                administrator_,
                pendingAdministrator_,
                acceptIncluded_
            )
        );
    }

    function _expectRevertBridgeAdminRoleMismatch(bool held_, bool grantIncluded_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_BridgeAdminRoleMismatch
                    .selector,
                held_,
                grantIncluded_
            )
        );
    }

    function _expectRevertConfigEnabledMismatch(bool enabled_, bool enableIncluded_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_ConfigEnabledMismatch
                    .selector,
                enabled_,
                enableIncluded_
            )
        );
    }

    function _expectRevertPoolOwnerMismatch(address owner_, address expected_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_PoolOwnerMismatch
                    .selector,
                owner_,
                expected_
            )
        );
    }

    function _expectRevertConfigOperatorMismatch(
        address configOperator_,
        address desired_,
        bool setIncluded_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_ConfigOperatorMismatch
                    .selector,
                configOperator_,
                desired_,
                setIncluded_
            )
        );
    }

    function _expectRevertRebalancerMismatch(
        address rebalancer_,
        address desired_,
        bool setIncluded_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_RebalancerMismatch
                    .selector,
                rebalancer_,
                desired_,
                setIncluded_
            )
        );
    }

    function _expectRevertRateLimitAdminMismatch(
        address rateLimitAdmin_,
        address desired_,
        bool setIncluded_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_RateLimitAdminMismatch
                    .selector,
                rateLimitAdmin_,
                desired_,
                setIncluded_
            )
        );
    }

    function _expectRevertTimelockEnabledMismatch(bool enabled_, bool enableIncluded_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_TimelockEnabledMismatch
                    .selector,
                enabled_,
                enableIncluded_
            )
        );
    }

    function _expectRevertRouteAlreadyExists(uint64 chainSelector_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_RouteAlreadyExists
                    .selector,
                chainSelector_
            )
        );
    }

    function _expectRevertBackingTooLow(uint256 balance_, uint256 minimum_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigProposalChecker
                    .CCIPTokenPoolConfigProposalChecker_BackingTooLow
                    .selector,
                balance_,
                minimum_
            )
        );
    }
}
