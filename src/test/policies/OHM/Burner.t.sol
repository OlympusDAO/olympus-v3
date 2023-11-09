// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";

import "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter, OHM} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Burner} from "policies/OHM/Burner.sol";

// solhint-disable-next-line max-states-count
contract BurnerTest is Test {
    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;

    MockOhm internal ohm;

    Kernel internal kernel;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;

    RolesAdmin internal rolesAdmin;
    Burner internal burner;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            // Create users
            address[] memory users = userCreator.create(3);
            alice = users[0];
            bob = users[1];
            guardian = users[2];

            // Label users
            vm.label(alice, "alice");
            vm.label(bob, "bob");
            vm.label(guardian, "guardian");
        }

        {
            // Deploy mock OHM
            ohm = new MockOhm("Olympus", "OHM", 9);
            vm.label(address(ohm), "OHM");
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor
            vm.label(address(kernel), "Kernel");

            // Deploy modules
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);

            // Label modules
            vm.label(address(TRSRY), "TRSRY");
            vm.label(address(MINTR), "MINTR");
            vm.label(address(ROLES), "ROLES");
        }

        {
            // Deploy policies
            rolesAdmin = new RolesAdmin(kernel);
            burner = new Burner(kernel, ohm);

            // Label policies
            vm.label(address(rolesAdmin), "RolesAdmin");
            vm.label(address(burner), "Burner");
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(burner));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            // Configure access control

            // Burner ROLES
            rolesAdmin.grantRole("burner_admin", guardian);
        }

        // Mint tokens to users, TRSRY, and burner for testing
        uint256 testOhm = 1_000_000 * 1e9;

        ohm.mint(alice, testOhm);
        ohm.mint(address(TRSRY), testOhm);
        ohm.mint(address(burner), testOhm);

        // Approve burner to burn ohm from alice
        vm.prank(alice);
        ohm.approve(address(burner), type(uint256).max);

        // Add some basic categories to the burner for testing
        vm.startPrank(guardian);
        burner.addCategory("TEST_CATEGORY_1");
        burner.addCategory("TEST_CATEGORY_2");
        burner.addCategory("TEST_CATEGORY_3");
        vm.stopPrank();
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](3);
        expectedDeps[0] = toKeycode("TRSRY");
        expectedDeps[1] = toKeycode("MINTR");
        expectedDeps[2] = toKeycode("ROLES");

        Keycode[] memory deps = burner.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](3);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPerms[1] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        expectedPerms[2] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);

        Permissions[] memory perms = burner.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // ========== HELPER FUNCTIONS ========== //

    // ========== EVENTS FOR TESTING ========== //

    event Burn(address indexed from, bytes32 indexed category, uint256 amount);
    event CategoryAdded(bytes32 category);
    event CategoryRemoved(bytes32 category);

    // ========== BURN FUNCTION TESTS ========== //

    // [X] Burn from Treasury
    //      [X] Burn valid with correct amount and approved category (fuzz amounts)
    //      [X] Burn invalid with zero amount
    //      [X] Burn invalid with amount larger than balance
    //      [X] Burn invalid with invalid category
    //      [X] Cannot burn unless burner_admin
    // [X] Burn from address
    //      [X] Burn valid with correct amount and approved category (fuzz amounts)
    //      [X] Burn invalid with zero amount
    //      [X] Burn invalid with amount larger than balance
    //      [X] Burn invalid with amount larger than approval
    //      [X] Burn invalid with invalid category
    //      [X] Cannot burn unless burner_admin
    // [X] Burn from Burner
    //      [X] Burn valid with correct amount and approved category (fuzz amounts)
    //      [X] Burn invalid with zero amount
    //      [X] Burn invalid with amount larger than balance
    //      [X] Burn invalid with invalid category
    //      [X] Cannot burn unless burner_admin

    function testFuzz_burnFromTreasury(uint256 amount_) public {
        // Check balances before burn
        uint256 treasuryBalance = ohm.balanceOf(address(TRSRY));
        vm.assume(amount_ <= treasuryBalance && amount_ != 0);
        uint256 burnerBalance = ohm.balanceOf(address(burner));

        // Burn from TRSRY (expect event with category)
        vm.expectEmit(true, true, false, true);
        emit Burn(address(TRSRY), "TEST_CATEGORY_1", amount_);
        vm.prank(guardian);
        burner.burnFromTreasury(amount_, "TEST_CATEGORY_1");

        // Check balances after burn
        assertEq(ohm.balanceOf(address(TRSRY)), treasuryBalance - amount_);
        assertEq(ohm.balanceOf(address(burner)), burnerBalance);
    }

    function testRevert_burnFromTreasury_zeroAmount() public {
        // Attempt to burn zero tokens from TRSRY and expect revert
        bytes memory err = abi.encodeWithSignature("MINTR_ZeroAmount()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burnFromTreasury(0, "TEST_CATEGORY_1");
    }

    function testRevert_burnFromTreasury_exceedsBalance() public {
        uint256 balance = ohm.balanceOf(address(TRSRY));

        // Attempt to burn more than TRSRY balance and expect revert
        bytes memory err = abi.encodePacked("TRANSFER_FAILED");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burnFromTreasury(balance + 1, "TEST_CATEGORY_1");
    }

    function testRevert_burnFromTreasury_invalidCategory() public {
        // Attempt to burn with invalid category and expect revert
        bytes memory err = abi.encodeWithSignature("Burner_CategoryNotApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burnFromTreasury(1, "INVALID_CATEGORY");
    }

    function testRevert_burnFromTreasury_accessControl() public {
        // Attempt to burn without burner_admin role and expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("burner_admin")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        burner.burnFromTreasury(1, "TEST_CATEGORY_1");
    }

    function testFuzz_burnFrom(uint256 amount_) public {
        // Check balances before burn
        uint256 aliceBalance = ohm.balanceOf(alice);
        vm.assume(amount_ <= aliceBalance && amount_ != 0);
        uint256 burnerBalance = ohm.balanceOf(address(burner));

        // Burn from alice (expect event with category)
        vm.expectEmit(true, true, false, true);
        emit Burn(alice, "TEST_CATEGORY_1", amount_);
        vm.prank(guardian);
        burner.burnFrom(alice, amount_, "TEST_CATEGORY_1");

        // Check balances after burn
        assertEq(ohm.balanceOf(alice), aliceBalance - amount_);
        assertEq(ohm.balanceOf(address(burner)), burnerBalance);
    }

    function testRevert_burnFrom_zeroAmount() public {
        // Attempt to burn zero tokens from user and expect revert
        bytes memory err = abi.encodeWithSignature("MINTR_ZeroAmount()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burnFrom(alice, 0, "TEST_CATEGORY_1");
    }

    function testRevert_burnFrom_exceedsBalance() public {
        uint256 balance = ohm.balanceOf(alice);

        // Attempt to burn more than alice's balance and expect revert
        bytes memory err = abi.encodePacked("TRANSFER_FROM_FAILED");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burnFrom(alice, balance + 1, "TEST_CATEGORY_1");
    }

    function testRevert_burnFrom_exceedsAllowance() public {
        uint256 balance = ohm.balanceOf(alice);

        // Approve less than balance on burner
        vm.prank(alice);
        ohm.approve(address(burner), balance - 1);

        // Attempt to burn more than alice's approval and expect revert
        bytes memory err = abi.encodePacked("TRANSFER_FROM_FAILED");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burnFrom(alice, balance, "TEST_CATEGORY_1");
    }

    function testRevert_burnFrom_invalidCategory() public {
        // Attempt to burn with invalid category and expect revert
        bytes memory err = abi.encodeWithSignature("Burner_CategoryNotApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burnFrom(alice, 1, "INVALID_CATEGORY");
    }

    function testRevert_burnFrom_accessControl() public {
        // Attempt to burn without burner_admin role and expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("burner_admin")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        burner.burnFrom(alice, 1, "TEST_CATEGORY_1");
    }

    function testFuzz_burn(uint256 amount_) public {
        // Check balances before burn
        uint256 burnerBalance = ohm.balanceOf(address(burner));
        vm.assume(amount_ <= burnerBalance && amount_ != 0);

        // Burn from burner (expect event with category)
        vm.expectEmit(true, true, false, true);
        emit Burn(address(burner), "TEST_CATEGORY_1", amount_);
        vm.prank(guardian);
        burner.burn(amount_, "TEST_CATEGORY_1");

        // Check balances after burn
        assertEq(ohm.balanceOf(address(burner)), burnerBalance - amount_);
    }

    function testRevert_burn_zeroAmount() public {
        // Attempt to burn zero tokens from burner and expect revert
        bytes memory err = abi.encodeWithSignature("MINTR_ZeroAmount()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burn(0, "TEST_CATEGORY_1");
    }

    function testRevert_burn_exceedsBalance() public {
        uint256 balance = ohm.balanceOf(address(burner));

        // Attempt to burn more than burner balance and expect revert
        bytes memory err = abi.encodePacked("ERC20: burn amount exceeds balance");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burn(balance + 1, "TEST_CATEGORY_1");
    }

    function testRevert_burn_invalidCategory() public {
        // Attempt to burn with invalid category and expect revert
        bytes memory err = abi.encodeWithSignature("Burner_CategoryNotApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.burn(1, "INVALID_CATEGORY");
    }

    function testRevert_burn_accessControl() public {
        // Attempt to burn without burner_admin role and expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("burner_admin")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        burner.burn(1, "TEST_CATEGORY_1");
    }

    // ========== CATEGORY FUNCTION TESTS ========== //

    // [X] Add Category
    //      [X] Add category that has not been approved
    //      [X] Cannot add category that is already approved
    // [X] Remove Category
    //      [X] Remove category that is approved
    //      [X] Cannot remove category that has not been approved

    function testFuzz_addCategory(bytes32 category_) public {
        vm.assume(
            category_ != "TEST_CATEGORY_1" &&
                category_ != "TEST_CATEGORY_2" &&
                category_ != "TEST_CATEGORY_3"
        );

        // Confirm category is not approved
        assertTrue(!burner.categoryApproved(category_));

        // Add category that has not been approved
        vm.expectEmit(false, false, false, true);
        emit CategoryAdded(category_);
        vm.prank(guardian);
        burner.addCategory(category_);

        // Confirm category is approved
        assertTrue(burner.categoryApproved(category_));
        // Confirm category added to categories array
        assertEq(burner.categories(3), category_);
    }

    function testRevert_addCategory_categoryApproved() public {
        // Attempt to add category that is already approved and expect revert
        bytes memory err = abi.encodeWithSignature("Burner_CategoryApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.addCategory("TEST_CATEGORY_1");
    }

    function test_removeCategory() public {
        // Confirm category is approved
        assertTrue(burner.categoryApproved("TEST_CATEGORY_1"));

        // Remove category that is approved
        vm.expectEmit(false, false, false, true);
        emit CategoryRemoved("TEST_CATEGORY_1");
        vm.prank(guardian);
        burner.removeCategory("TEST_CATEGORY_1");

        // Confirm category is not approved
        assertTrue(!burner.categoryApproved("TEST_CATEGORY_1"));
        // Confirm category removed from categories array
        assertEq(burner.categories(0), "TEST_CATEGORY_3");
    }

    function testRevert_removeCategory_categoryNotApproved() public {
        // Attempt to remove category that is not approved and expect revert
        bytes memory err = abi.encodeWithSignature("Burner_CategoryNotApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        burner.removeCategory("INVALID_CATEGORY");
    }

    // ========== VIEW FUNCTION TESTS ========= //

    // [X] Get Categories

    function test_getCategories() public {
        bytes32[] memory categories = burner.getCategories();

        assertEq(categories.length, 3);
        assertEq(categories[0], "TEST_CATEGORY_1");
        assertEq(categories[1], "TEST_CATEGORY_2");
        assertEq(categories[2], "TEST_CATEGORY_3");
    }
}
