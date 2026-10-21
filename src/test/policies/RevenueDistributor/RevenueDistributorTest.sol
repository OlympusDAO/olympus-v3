// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RevenueDistributorHarness} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorHarness.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

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
}
