// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel, Module, Policy} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {RevenueDistributorHarness} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorHarness.sol";

abstract contract RevenueDistributorTest is Test {
    address internal admin;
    address internal emergency;
    address internal alice;
    address internal bob;

    Kernel internal kernel;
    OlympusRoles internal roles;
    OlympusTreasury internal treasury;
    RolesAdmin internal rolesAdmin;
    RevenueDistributorHarness internal distributor;
    RevenueDistributorConfigTimelock internal configTimelock;
    MockERC20 internal token;

    function setUp() public virtual {
        admin = makeAddr("admin");
        emergency = makeAddr("emergency");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(admin);
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        treasury = new OlympusTreasury(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        distributor = new RevenueDistributorHarness(kernel);
        configTimelock = new RevenueDistributorConfigTimelock(kernel, distributor);
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        kernel.executeAction(Actions.ActivatePolicy, address(configTimelock));
        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(EMERGENCY_ROLE, emergency);
        distributor.enable("");
        configTimelock.enable("");
        distributor.setConfigOperator(address(configTimelock));
        vm.stopPrank();

        token = new MockERC20("Test Revenue", "REV", 18);
        vm.label(address(kernel), "Kernel");
        vm.label(address(roles), "ROLES");
        vm.label(address(treasury), "TRSRY");
        vm.label(address(rolesAdmin), "Roles admin");
        vm.label(address(distributor), "Revenue distributor");
        vm.label(address(configTimelock), "Revenue distributor config timelock");
        vm.label(address(token), "Revenue token");
    }

    // Finite scenario loops must inspect each asset ledger independently.
    // forge-lint: disable-start(calls-loop)
    function _assertPendingPayouts(
        address asset_,
        address assetRouteRecipient_,
        uint256 expectedAssetRoute_,
        uint256 expectedRepurchase_,
        uint256 expectedTreasury_
    ) internal view {
        assertEq(
            distributor.pendingAssetRouteForTest(asset_, assetRouteRecipient_),
            expectedAssetRoute_,
            "pending asset route matches expected balance"
        );
        assertEq(
            distributor.pendingRepurchaseForTest(asset_),
            expectedRepurchase_,
            "pending repurchase matches expected balance"
        );
        assertEq(
            distributor.pendingTreasuryForTest(asset_),
            expectedTreasury_,
            "pending Treasury matches expected balance"
        );
        assertEq(
            distributor.totalPendingForTest(asset_),
            expectedAssetRoute_ + expectedRepurchase_ + expectedTreasury_,
            "aggregate pending matches expected balance"
        );
    }

    // forge-lint: disable-end(calls-loop)

    // Use a non-round share so payout tests also exercise Treasury rounding dust.
    // Keep the fixture setup in a given modifier to match the condition tree.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenAliceConfiguredAsRecipient() {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_333});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        _;
    }

    // Finite lifecycle seed loops use these state-setup calls.
    // forge-lint: disable-start(calls-loop)
    function _disableDistributor() internal {
        vm.prank(admin);
        distributor.disable("");
    }

    function _setPolicyActive(address policy_, bool active_) internal {
        if (kernel.isPolicyActive(Policy(policy_)) != active_) {
            vm.prank(admin);
            kernel.executeAction(
                active_ ? Actions.ActivatePolicy : Actions.DeactivatePolicy,
                policy_
            );
        }
    }

    // forge-lint: disable-end(calls-loop)

    function _expectNotEnabled() internal {
        vm.expectRevert(IEnabler.NotEnabled.selector);
    }

    function _expectPolicyInactive() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
                address(distributor)
            )
        );
    }

    function _expectInvalidData() internal {
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_InvalidData.selector);
    }

    function _seedLifecycleRevenue() internal {
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, new IRevenueDistributor.AssetRoute[](0));
        distributor.seedPendingForTest(address(token), alice, 2, 3, 5);
        token.mint(address(distributor), 10);
    }

    function _assertLifecycleRevenue() internal view {
        _assertPendingPayouts(address(token), alice, 2, 3, 5);
        assertEq(token.balanceOf(address(distributor)), 10, "Lifecycle preserves custody");
        assertEq(distributor.getActiveAssetCount(), 1, "Lifecycle preserves asset registry");
        assertTrue(distributor.pendingAssetMemberForTest(address(token)), "Pending asset retained");
        assertTrue(
            distributor.pendingRouteMemberForTest(address(token), alice),
            "Pending recipient retained"
        );
        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "Selected authority retained"
        );
    }

    function _grantReEnableCaller(address caller_, bool adminRole_, bool revenueRole_) internal {
        vm.assume(caller_ != address(0));
        vm.assume(caller_ != admin);
        vm.assume(adminRole_ || revenueRole_);
        vm.startPrank(admin);
        if (adminRole_) rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (revenueRole_) rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, caller_);
        vm.stopPrank();
    }

    function _setRevenuePolicyLifecycle(address policy_, bool active_, bool enabled_) internal {
        if (!enabled_) _disablePolicy(policy_, admin);
        _setPolicyActive(policy_, active_);
    }

    /// @dev Independent snapshot of route/custody/raw obligations and both stored indexes.
    ///      Excludes lifecycle and module pointers so their documented changes can be asserted separately.
    function _revenueFundsDigest() internal view returns (bytes32) {
        bytes32 obligations = keccak256(
            abi.encode(
                distributor.pendingAssetRouteForTest(address(token), alice),
                distributor.pendingRepurchaseForTest(address(token)),
                distributor.pendingTreasuryForTest(address(token)),
                distributor.totalPendingForTest(address(token)),
                distributor.pendingAssetMemberForTest(address(token)),
                distributor.pendingRouteMemberForTest(address(token), alice),
                distributor.getPendingPayoutAssets()
            )
        );
        bytes32 custody = keccak256(
            abi.encode(
                token.balanceOf(address(distributor)),
                token.balanceOf(alice),
                token.balanceOf(bob),
                token.balanceOf(admin),
                token.balanceOf(address(treasury)),
                token.allowance(admin, address(distributor)),
                token.totalSupply()
            )
        );
        return
            keccak256(
                abi.encode(
                    obligations,
                    custody,
                    distributor.getActiveAssets(),
                    distributor.assetDistributionHash(address(token)),
                    distributor.yieldRecipient()
                )
            );
    }

    function _grantLifecycleAuthority(
        address caller_,
        bytes32 secondaryRole_,
        bool secondaryOnly_,
        bool overlap_
    ) internal {
        vm.assume(caller_ != address(0));
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, secondaryRole_));
        vm.startPrank(admin);
        if (!secondaryOnly_ || overlap_) rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (secondaryOnly_ || overlap_) rolesAdmin.grantRole(secondaryRole_, caller_);
        vm.stopPrank();
    }

    function _seedLifecycleQueue() internal returns (uint64 id) {
        _seedLifecycleRevenue();
        vm.prank(admin);
        return configTimelock.queueRescuePendingPayout(address(token), alice, bob, 1);
    }

    function _queuedLifecycleDigest(uint64 id_) internal view returns (bytes32) {
        (address target, bytes4 selector, bytes memory payload) = configTimelock.getQueuedSubAction(
            id_,
            0
        );
        (bytes32 key, bytes32 expected) = configTimelock.getQueuedConfigState(id_, 0, 0);
        return
            keccak256(
                abi.encode(
                    configTimelock.getQueuedAction(id_),
                    target,
                    selector,
                    payload,
                    configTimelock.nextActionId(),
                    configTimelock.getQueuedActionLength(id_),
                    configTimelock.getQueuedConfigStateCount(id_, 0),
                    configTimelock.getQueuedConfigDestination(id_, 0),
                    key,
                    expected,
                    configTimelock.pendingActionId(key)
                )
            );
    }

    function _distributorStateDigest(uint64 queueId_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _revenueAccountingDigest(),
                    _queuedLifecycleDigest(queueId_),
                    distributor.gracePeriod(),
                    address(distributor.ROLES()),
                    distributor.treasury(),
                    configTimelock.isEnabled(),
                    configTimelock.lastTransitionAt()
                )
            );
    }

    function _timelockStateDigest(uint64 queueId_) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _revenueAccountingDigest(),
                    _queuedLifecycleDigest(queueId_),
                    configTimelock.distributor(),
                    configTimelock.gracePeriod(),
                    configTimelock.timelockDelay(),
                    address(configTimelock.ROLES()),
                    distributor.isEnabled(),
                    distributor.lastTransitionAt()
                )
            );
    }

    address internal _proposerSeed;

    modifier givenProposer(
        address seed_,
        bool revenueOnly_,
        bool overlap_
    ) {
        vm.assume(seed_ != address(0));
        vm.assume(!roles.hasRole(seed_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(seed_, REVENUE_DISTRIBUTOR_ADMIN_ROLE));
        _proposerSeed = seed_;
        _grantLifecycleAuthority(seed_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        _;
    }

    function _revenueAccountingDigest() internal view returns (bytes32) {
        return keccak256(abi.encode(_revenueFundsDigest(), distributor.configOperator()));
    }

    function _grantConfigurationAuthority(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) internal {
        if (_configurationSeed == caller_ && caller_ != address(0)) return;
        vm.assume(caller_ != address(0));
        vm.assume(caller_ != distributor.configOperator());
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.startPrank(admin);
        if (!operatorOnly_ || overlap_) rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (operatorOnly_ || overlap_) distributor.setConfigOperator(caller_);
        vm.stopPrank();
    }

    address internal _configurationSeed;

    function _configurationCaller() internal view returns (address) {
        return _configurationSeed == address(0) ? address(configTimelock) : _configurationSeed;
    }

    function _timelockControlDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    configTimelock.nextActionId(),
                    configTimelock.isActive(),
                    configTimelock.isEnabled(),
                    configTimelock.lastTransitionAt(),
                    configTimelock.gracePeriod(),
                    configTimelock.timelockDelay(),
                    configTimelock.distributor(),
                    address(configTimelock.ROLES())
                )
            );
    }

    function _enablePolicy(address policy_) internal {
        vm.prank(admin);
        IEnabler(policy_).enable("");
    }

    // Finite scenario fixtures use this transition inside their explicit boundary loops.
    // forge-lint: disable-start(calls-loop)
    function _disablePolicy(address policy_, address caller_) internal {
        vm.prank(caller_);
        IEnabler(policy_).disable("");
    }

    // forge-lint: disable-end(calls-loop)

    function _installModule(Kernel kernel_, Module module_) internal {
        vm.prank(kernel_.executor());
        kernel_.executeAction(Actions.InstallModule, address(module_));
    }

    function _upgradeModule(Module module_) internal {
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(module_));
    }
}
