// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockVaultManager} from "test/mocks/MockBLVaultManager.sol";

import "src/Submodules.sol";
import {SupplyConfig} from "policies/OCA/SupplyConfig.sol";
import {OlympusSupply, SPPLYv1, Category as SupplyCategory, SupplySubmodule} from "modules/SPPLY/OlympusSupply.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {BLVaultSupply} from "src/modules/SPPLY/submodules/BLVaultSupply.sol";

// Tests for SupplyConfig v1.0.0
//
// SupplyConfig Setup and Permissions
// [X] configureDependencies
// [X] requestPermissions
//
// SPPLYv1 Configuration
// [X] addAsset
//     [X] only "supplyconfig_policy" role can call
//     [X] inputs to TRSRY.addAsset are correct
// [X] addAssetLocation
//     [X] only "supplyconfig_policy" role can call
//     [X] inputs to TRSRY.addAssetLocation are correct
// [X] removeAssetLocation
//     [X] only "supplyconfig_policy" role can call
//     [X] inputs to TRSRY.removeAssetLocation are correct
// [X] addAssetCategoryGroup
//     [X] only "supplyconfig_policy" role can call
//     [X] inputs to TRSRY.addAssetCategoryGroup are correct
// [X] addAssetCategory
//     [X] only "supplyconfig_policy" role can call
//     [X] inputs to TRSRY.addAssetCategory are correct
// [X] categorize
//     [X] only "supplyconfig_policy" role can call
//     [X] inputs to TRSRY.categorize are correct
// [X] installSubmodule
//     [X] only "supplyconfig_admin" role can call
//     [X] inputs to SPPLYv1.installSubmodule are correct
// [X] upgradeSubmodule
//     [X] inputs to SPPLYv1.upgradeSubmodule are correct

type Category is bytes32;
type CategoryGroup is bytes32;

contract MockUpgradedSubmoduleSupply is SupplySubmodule {
    constructor(Module parent_) Submodule(parent_) {}

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.BLV");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    function getCollateralizedOhm() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedBorrowableOhm() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedLiquidityOhm() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedTreasuryOhm() external view override returns (uint256) {
        return 0;
    }

    function getSourceCount() external view override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        return new SPPLYv1.Reserves[](0);
    }
}

contract SupplyConfigTest is Test {
    MockERC20 internal ohm;
    MockGohm internal gohm;
    MockERC20 internal reserve;
    MockERC20 internal weth;

    Kernel internal kernel;
    SupplyConfig internal supplyConfig;
    OlympusSupply internal SPPLY;
    RolesAdmin internal rolesAdmin;
    OlympusRoles internal ROLES;

    address internal admin;
    address internal policy;

    int256 internal constant CHANGE_DECIMALS = 1e4;
    uint256 internal constant GOHM_INDEX = 300000000000;
    uint8 internal constant DECIMALS = 18;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Create accounts
        UserFactory userFactory = new UserFactory();
        address[] memory users = userFactory.create(2);
        admin = users[0];
        policy = users[1];

        // Tokens
        gohm = new MockGohm(GOHM_INDEX);
        ohm = new MockERC20("Olympus", "OHM", 9);
        reserve = new MockERC20("Reserve", "RSV", 18);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        address[2] memory olympusTokens = [address(ohm), address(gohm)];

        // Deploy system contracts
        kernel = new Kernel();
        ROLES = new OlympusRoles(kernel);
        SPPLY = new OlympusSupply(kernel, olympusTokens, 0);
        supplyConfig = new SupplyConfig(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        // Install contracts on kernel
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(SPPLY));
        kernel.executeAction(Actions.ActivatePolicy, address(supplyConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Configure permissioned roles
        rolesAdmin.grantRole("supplyconfig_admin", admin);
        rolesAdmin.grantRole("supplyconfig_policy", policy);
    }

    /* ========== SupplyConfig Setup and Permissions ========== */

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("ROLES");
        expectedDeps[1] = toKeycode("SPPLY");

        Keycode[] memory deps = supplyConfig.configureDependencies();
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](6);
        Keycode SPPLY_KEYCODE = toKeycode("SPPLY");
        // SPPLY Permissions
        expectedPerms[0] = Permissions(SPPLY_KEYCODE, SPPLY.addCategory.selector);
        expectedPerms[1] = Permissions(SPPLY_KEYCODE, SPPLY.removeCategory.selector);
        expectedPerms[2] = Permissions(SPPLY_KEYCODE, SPPLY.categorize.selector);
        expectedPerms[3] = Permissions(SPPLY_KEYCODE, SPPLY.installSubmodule.selector);
        expectedPerms[4] = Permissions(SPPLY_KEYCODE, SPPLY.upgradeSubmodule.selector);
        expectedPerms[5] = Permissions(SPPLY_KEYCODE, SPPLY.execOnSubmodule.selector);

        Permissions[] memory perms = supplyConfig.requestPermissions();
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    /* ========== Submodule Installation/Upgrade ========== */

    function testRevert_installSubmodule_onlyAdmin(address user_) public {
        vm.assume(user_ != admin);

        // Create vault managers
        MockVaultManager vaultManager1 = new MockVaultManager(1000e9);
        MockVaultManager[] memory vaultManagers = new MockVaultManager[](1);
        address[] memory vaultManagerAddresses = new address[](1);
        vaultManagers[0] = vaultManager1;
        vaultManagerAddresses[0] = address(vaultManager1);

        // Create new submodule to install
        BLVaultSupply supplyBLV = new BLVaultSupply(SPPLY, vaultManagerAddresses);

        // Confirm submodule is not installed on SPPLY
        address submodule = address(SPPLY.getSubmoduleForKeycode(supplyBLV.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Try to install submodule with non-admin account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("supplyconfig_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        supplyConfig.installSubmodule(supplyBLV);

        // Confirm submodule was installed
        submodule = address(SPPLY.getSubmoduleForKeycode(supplyBLV.SUBKEYCODE()));
        assertEq(submodule, address(0));
    }

    function test_installSubmodule_SPPLY() public {
        // Create vault managers
        MockVaultManager vaultManager1 = new MockVaultManager(1000e9);
        MockVaultManager[] memory vaultManagers = new MockVaultManager[](1);
        address[] memory vaultManagerAddresses = new address[](1);
        vaultManagers[0] = vaultManager1;
        vaultManagerAddresses[0] = address(vaultManager1);

        // Create new submodule to install
        BLVaultSupply supplyBLV = new BLVaultSupply(SPPLY, vaultManagerAddresses);

        // Confirm submodule is not installed on SPPLY
        address submodule = address(SPPLY.getSubmoduleForKeycode(supplyBLV.SUBKEYCODE()));
        assertEq(submodule, address(0));

        // Install new submodule with admin account
        vm.prank(admin);
        supplyConfig.installSubmodule(supplyBLV);

        // Confirm submodule was installed
        submodule = address(SPPLY.getSubmoduleForKeycode(supplyBLV.SUBKEYCODE()));
        assertEq(submodule, address(supplyBLV));
    }

    function testRevert_upgradeSubmodule_onlyAdmin(address user_) public {
        vm.assume(user_ != admin);

        // Create vault managers
        MockVaultManager vaultManager1 = new MockVaultManager(1000e9);
        MockVaultManager[] memory vaultManagers = new MockVaultManager[](1);
        address[] memory vaultManagerAddresses = new address[](1);
        vaultManagers[0] = vaultManager1;
        vaultManagerAddresses[0] = address(vaultManager1);

        // Create new submodule to install
        BLVaultSupply supplyBLV = new BLVaultSupply(SPPLY, vaultManagerAddresses);

        // Install new submodule with admin account
        vm.prank(admin);
        supplyConfig.installSubmodule(supplyBLV);

        // Confirm BLV submodule is installed on SPPLY and the version is 1.0
        address submodule = address(SPPLY.getSubmoduleForKeycode(toSubKeycode("SPPLY.BLV")));
        assertEq(submodule, address(supplyBLV));
        (uint8 major, uint8 minor) = Submodule(submodule).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Create mock upgrade for BLV submodule
        MockUpgradedSubmoduleSupply newBLV = new MockUpgradedSubmoduleSupply(SPPLY);

        // Try to upgrade submodule with non-admin account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("supplyconfig_admin")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        supplyConfig.upgradeSubmodule(newBLV);

        // Confirm submodule was not upgraded
        submodule = address(SPPLY.getSubmoduleForKeycode(toSubKeycode("SPPLY.BLV")));
        assertEq(submodule, address(supplyBLV));
        (major, minor) = Submodule(submodule).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_upgradeSubmodule_SPPLY() public {
        // Create vault managers
        MockVaultManager vaultManager1 = new MockVaultManager(1000e9);
        MockVaultManager[] memory vaultManagers = new MockVaultManager[](1);
        address[] memory vaultManagerAddresses = new address[](1);
        vaultManagers[0] = vaultManager1;
        vaultManagerAddresses[0] = address(vaultManager1);

        // Create new submodule to install
        BLVaultSupply supplyBLV = new BLVaultSupply(SPPLY, vaultManagerAddresses);

        // Install new submodule with admin account
        vm.prank(admin);
        supplyConfig.installSubmodule(supplyBLV);

        // Confirm BLV submodule is installed on SPPLY and the version is 1.0
        address submodule = address(SPPLY.getSubmoduleForKeycode(toSubKeycode("SPPLY.BLV")));
        assertEq(submodule, address(supplyBLV));
        (uint8 major, uint8 minor) = Submodule(submodule).VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);

        // Create mock upgrade for BLV submodule
        MockUpgradedSubmoduleSupply newBLV = new MockUpgradedSubmoduleSupply(SPPLY);

        // Upgrade BLV submodule with admin account, expect success
        vm.prank(admin);
        supplyConfig.upgradeSubmodule(newBLV);

        // Confirm BLV submodule was upgraded
        submodule = address(SPPLY.getSubmoduleForKeycode(toSubKeycode("SPPLY.BLV")));
        assertEq(submodule, address(newBLV));
        (major, minor) = Submodule(submodule).VERSION();
        assertEq(major, 2);
        assertEq(minor, 0);
    }

    /* ========== SPPLYv1 Configuration ========== */

    function testRevert_addSupplyCategory_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to add category to SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("supplyconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        supplyConfig.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );
    }

    function test_addSupplyCategory() public {
        SupplyCategory[] memory initCategories = SPPLY.getCategories();

        vm.prank(policy);
        supplyConfig.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );

        // Check SPPLY categories
        SupplyCategory[] memory postCategories = SPPLY.getCategories();
        assertEq(initCategories.length + 1, postCategories.length);
        assertEq(
            SupplyCategory.unwrap(postCategories[postCategories.length - 1]),
            bytes32("test_supply_category")
        );
    }

    function testRevert_removeSupplyCategory_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("supplyconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        supplyConfig.removeSupplyCategory(SupplyCategory.wrap("test_supply_category"));
    }

    function test_removeSupplyCategory(address user_) public {
        SupplyCategory[] memory initCategories = SPPLY.getCategories();

        vm.startPrank(policy);
        supplyConfig.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );
        supplyConfig.removeSupplyCategory(SupplyCategory.wrap("test_supply_category"));

        // Check SPPLY categories
        SupplyCategory[] memory postCategories = SPPLY.getCategories();
        assertEq(initCategories.length, postCategories.length);
    }

    function testRevert_categorizeSupply_onlyPolicy(address user_) public {
        vm.assume(user_ != policy);

        // Try to remove category from SPPLYv1 with non-policy account, expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("supplyconfig_policy")
        );
        vm.expectRevert(err);
        vm.prank(user_);
        supplyConfig.categorizeSupply(address(0), SupplyCategory.wrap("test_supply_category"));
    }

    function test_categorizeSupply(address user_) public {
        vm.startPrank(policy);
        supplyConfig.addSupplyCategory(
            SupplyCategory.wrap("test_supply_category"),
            false,
            bytes4(0),
            bytes4(0)
        );
        supplyConfig.categorizeSupply(address(1), SupplyCategory.wrap("test_supply_category"));

        // Check SPPLY category locations
        address[] memory locations = SPPLY.getLocationsByCategory(
            SupplyCategory.wrap("test_supply_category")
        );
        assertEq(locations.length, 1);
        assertEq(locations[0], address(1));
    }
}
