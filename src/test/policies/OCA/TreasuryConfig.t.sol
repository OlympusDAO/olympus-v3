// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {OlympusTreasury, TRSRYv1_1, CategoryGroup as AssetCategoryGroup, Category as AssetCategory} from "src/modules/TRSRY/OlympusTreasury.sol";
import {ROLESv1, OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {TreasuryConfig} from "src/policies/OCA/TreasuryConfig.sol";

import "src/Kernel.sol";

contract TreasuryConfigTest is Test {
    address internal randomWallet;
    address internal guardian;

    Kernel internal kernel;

    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;
    TreasuryConfig internal custodian;
    RolesAdmin internal rolesAdmin;

    MockERC20 public ngmi;

    function setUp() public {
        address[] memory users = (new UserFactory()).create(2);
        randomWallet = users[0];
        guardian = users[1];

        ngmi = new MockERC20("not gonna make it", "NGMI", 18);

        kernel = new Kernel(); // this contract will be the executor

        TRSRY = new OlympusTreasury(kernel);
        ROLES = new OlympusRoles(kernel);

        custodian = new TreasuryConfig(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        kernel.executeAction(Actions.ActivatePolicy, address(custodian));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        /// Configure access control
        rolesAdmin.grantRole("treasuryconfig_policy", guardian);
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("TRSRY");
        expectedDeps[1] = toKeycode("ROLES");

        Keycode[] memory deps = custodian.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](6);
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");

        expectedPerms[0] = Permissions(TRSRY_KEYCODE, TRSRY.addAsset.selector);
        expectedPerms[1] = Permissions(TRSRY_KEYCODE, TRSRY.addAssetLocation.selector);
        expectedPerms[2] = Permissions(TRSRY_KEYCODE, TRSRY.removeAssetLocation.selector);
        expectedPerms[3] = Permissions(TRSRY_KEYCODE, TRSRY.addCategoryGroup.selector);
        expectedPerms[4] = Permissions(TRSRY_KEYCODE, TRSRY.addCategory.selector);
        expectedPerms[5] = Permissions(TRSRY_KEYCODE, TRSRY.categorize.selector);

        Permissions[] memory perms = custodian.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    /* ========== TRSRYv1.1 Configuration ========== */

    function testRevert_addAsset_onlyPolicy(address user_) public {
        vm.assume(user_ != guardian);
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        // Try to add category to SPPLYv1 with non-guardian account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("treasuryconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        custodian.addAsset(address(ngmi), locations);
    }

    function test_addAsset() public {
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        vm.prank(guardian);
        custodian.addAsset(address(ngmi), locations);

        // Check TRSRY assets
        address[] memory assets = TRSRY.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(ngmi));

        // Check TRSRY asset locations
        TRSRYv1_1.Asset memory assetData = TRSRY.getAssetData(address(ngmi));
        assertEq(assetData.locations.length, 2);
        assertEq(assetData.locations[0], address(1));
        assertEq(assetData.locations[1], address(2));
        assertEq(assetData.approved, true);
        assertEq(assetData.updatedAt, uint48(block.timestamp));
    }

    function testRevert_addAssetLocation_onlyPolicy(address user_) public {
        vm.assume(user_ != guardian);

        // Try to remove category from SPPLYv1 with non-guardian account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("treasuryconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        custodian.addAssetLocation(address(ngmi), address(2));
    }

    function test_addAssetLocation() public {
        address[] memory locations = new address[](1);
        locations[0] = address(1);

        vm.prank(guardian);
        custodian.addAsset(address(ngmi), locations);

        // Cache TRSRY asset locations
        TRSRYv1_1.Asset memory initAssetData = TRSRY.getAssetData(address(ngmi));

        vm.prank(guardian);
        custodian.addAssetLocation(address(ngmi), address(2));

        // Check TRSRY asset locations
        TRSRYv1_1.Asset memory postAssetData = TRSRY.getAssetData(address(ngmi));
        assertEq(initAssetData.locations.length + 1, postAssetData.locations.length);
        assertEq(postAssetData.locations[1], address(2));
    }

    function testRevert_removeAssetLocation_onlyPolicy(address user_) public {
        vm.assume(user_ != guardian);

        // Try to remove category from SPPLYv1 with non-guardian account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("treasuryconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        custodian.removeAssetLocation(address(ngmi), address(0));
    }

    function test_removeAssetLocation() public {
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        vm.prank(guardian);
        custodian.addAsset(address(ngmi), locations);

        // Cache TRSRY asset locations
        TRSRYv1_1.Asset memory initAssetData = TRSRY.getAssetData(address(ngmi));

        vm.prank(guardian);
        custodian.removeAssetLocation(address(ngmi), address(2));

        // Check TRSRY asset locations
        TRSRYv1_1.Asset memory postAssetData = TRSRY.getAssetData(address(ngmi));
        assertEq(initAssetData.locations.length - 1, postAssetData.locations.length);
    }

    function testRevert_addAssetCategoryGroup_onlyPolicy(address user_) public {
        vm.assume(user_ != guardian);

        // Try to remove category from SPPLYv1 with non-guardian account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("treasuryconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        custodian.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));
    }

    function test_addAssetCategoryGroup(address user_) public {
        vm.prank(guardian);
        custodian.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));

        // Check TRSRY asset category groups
        AssetCategoryGroup group0 = TRSRY.categoryGroups(0);
        assertEq(AssetCategoryGroup.unwrap(group0), bytes32("liquidity-preference"));
        AssetCategoryGroup group1 = TRSRY.categoryGroups(1);
        assertEq(AssetCategoryGroup.unwrap(group1), bytes32("value-baskets"));
        AssetCategoryGroup group2 = TRSRY.categoryGroups(2);
        assertEq(AssetCategoryGroup.unwrap(group2), bytes32("market-sensitivity"));
        AssetCategoryGroup group3 = TRSRY.categoryGroups(3);
        assertEq(AssetCategoryGroup.unwrap(group3), bytes32("test-asset-category-group"));
    }

    function testRevert_addAssetCategory_onlyPolicy(address user_) public {
        vm.assume(user_ != guardian);

        // Try to remove category from SPPLYv1 with non-guardian account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("treasuryconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        custodian.addAssetCategory(
            AssetCategory.wrap("test-asset-category"),
            AssetCategoryGroup.wrap("test-asset-category-group")
        );
    }

    function test_addAssetCategory(address user_) public {
        vm.startPrank(guardian);
        custodian.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));
        custodian.addAssetCategory(
            AssetCategory.wrap("test-asset-category"),
            AssetCategoryGroup.wrap("test-asset-category-group")
        );

        // Check TRSRY asset category for a given category group
        AssetCategoryGroup group = TRSRY.categoryToGroup(AssetCategory.wrap("test-asset-category"));
        assertEq(AssetCategoryGroup.unwrap(group), bytes32("test-asset-category-group"));
    }

    function testRevert_categorizeAsset_onlyPolicy(address user_) public {
        vm.assume(user_ != guardian);

        // Try to remove category from SPPLYv1 with non-guardian account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("treasuryconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        custodian.categorizeAsset(address(ngmi), AssetCategory.wrap("test-asset-category"));
    }

    function test_categorizeAsset() public {
        address[] memory locations = new address[](2);
        locations[0] = address(1);
        locations[1] = address(2);

        vm.startPrank(guardian);
        custodian.addAssetCategoryGroup(AssetCategoryGroup.wrap("test-asset-category-group"));
        custodian.addAssetCategory(
            AssetCategory.wrap("test-asset-category"),
            AssetCategoryGroup.wrap("test-asset-category-group")
        );
        custodian.addAsset(address(ngmi), locations);
        custodian.categorizeAsset(address(ngmi), AssetCategory.wrap("test-asset-category"));

        // Check TRSRY asset by category
        address[] memory assets = TRSRY.getAssetsByCategory(
            AssetCategory.wrap("test-asset-category")
        );
        assertEq(assets.length, 1);
        assertEq(assets[0], address(ngmi));
    }
}