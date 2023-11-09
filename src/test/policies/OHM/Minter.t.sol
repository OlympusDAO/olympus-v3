// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";

import "src/Kernel.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Minter} from "policies/OHM/Minter.sol";

// solhint-disable-next-line max-states-count
contract MinterTest is Test {
    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;

    MockOhm internal ohm;

    Kernel internal kernel;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;

    RolesAdmin internal rolesAdmin;
    Minter internal minter;

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
            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);

            // Label modules
            vm.label(address(MINTR), "MINTR");
            vm.label(address(ROLES), "ROLES");
        }

        {
            // Deploy policies
            rolesAdmin = new RolesAdmin(kernel);
            minter = new Minter(kernel);

            // Label policies
            vm.label(address(rolesAdmin), "RolesAdmin");
            vm.label(address(minter), "Minter");
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(minter));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            // Configure access control

            // Minter roles
            rolesAdmin.grantRole("minter_admin", guardian);
        }

        // Add some basic categories to the minter for testing
        vm.startPrank(guardian);
        minter.addCategory("TEST_CATEGORY_1");
        minter.addCategory("TEST_CATEGORY_2");
        minter.addCategory("TEST_CATEGORY_3");
        vm.stopPrank();
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("MINTR");
        expectedDeps[1] = toKeycode("ROLES");

        Keycode[] memory deps = minter.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](2);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPerms[1] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        Permissions[] memory perms = minter.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // ========== EVENTS FOR TESTING ========== //

    event Mint(address indexed to, bytes32 indexed category, uint256 amount);
    event CategoryAdded(bytes32 category);
    event CategoryRemoved(bytes32 category);

    // ========== MINT FUNCTION TESTS ========== //
    // [X] Mint to address
    //      [X] Mint valid with correct amount and approved category (fuzz amounts)
    //      [X] Mint invalid with zero amount
    //      [X] Mint invalid with invalid category
    //      [X] Cannot mint unless minter_admin

    function testFuzz_mint(uint256 amount_) public {
        // Check balances before burn
        vm.assume(amount_ != 0 && amount_ < type(uint256).max - ohm.totalSupply());
        uint256 aliceBalance = ohm.balanceOf(alice);

        // Burn from alice (expect event with category)
        vm.expectEmit(true, true, false, true);
        emit Mint(alice, "TEST_CATEGORY_1", amount_);
        vm.prank(guardian);
        minter.mint(alice, amount_, "TEST_CATEGORY_1");

        // Check balances after burn
        assertEq(ohm.balanceOf(alice), aliceBalance + amount_);
    }

    function testRevert_mint_zeroAmount() public {
        // Attempt to burn zero tokens from user and expect revert
        bytes memory err = abi.encodeWithSignature("MINTR_ZeroAmount()");
        vm.expectRevert(err);
        vm.prank(guardian);
        minter.mint(alice, 0, "TEST_CATEGORY_1");
    }

    function testRevert_mint_invalidCategory() public {
        // Attempt to burn with invalid category and expect revert
        bytes memory err = abi.encodeWithSignature("Minter_CategoryNotApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        minter.mint(alice, 1, "INVALID_CATEGORY");
    }

    function testRevert_burnFrom_accessControl() public {
        // Attempt to burn without burner_admin role and expect revert
        bytes memory err = abi.encodeWithSignature(
            "ROLES_RequireRole(bytes32)",
            bytes32("minter_admin")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        minter.mint(alice, 1, "TEST_CATEGORY_1");
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
        assertTrue(!minter.categoryApproved(category_));

        // Add category that has not been approved
        vm.expectEmit(false, false, false, true);
        emit CategoryAdded(category_);
        vm.prank(guardian);
        minter.addCategory(category_);

        // Confirm category is approved
        assertTrue(minter.categoryApproved(category_));
        // Confirm category added to categories array
        assertEq(minter.categories(3), category_);
    }

    function testRevert_addCategory_categoryApproved() public {
        // Attempt to add category that is already approved and expect revert
        bytes memory err = abi.encodeWithSignature("Minter_CategoryApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        minter.addCategory("TEST_CATEGORY_1");
    }

    function test_removeCategory() public {
        // Confirm category is approved
        assertTrue(minter.categoryApproved("TEST_CATEGORY_1"));

        // Remove category that is approved
        vm.expectEmit(false, false, false, true);
        emit CategoryRemoved("TEST_CATEGORY_1");
        vm.prank(guardian);
        minter.removeCategory("TEST_CATEGORY_1");

        // Confirm category is not approved
        assertTrue(!minter.categoryApproved("TEST_CATEGORY_1"));
        // Confirm category removed from categories array
        assertEq(minter.categories(0), "TEST_CATEGORY_3");
    }

    function testRevert_removeCategory_categoryNotApproved() public {
        // Attempt to remove category that is not approved and expect revert
        bytes memory err = abi.encodeWithSignature("Minter_CategoryNotApproved()");
        vm.expectRevert(err);
        vm.prank(guardian);
        minter.removeCategory("INVALID_CATEGORY");
    }

    // ========== VIEW FUNCTION TESTS ========= //

    // [X] Get Categories

    function test_getCategories() public {
        bytes32[] memory categories = minter.getCategories();

        assertEq(categories.length, 3);
        assertEq(categories[0], "TEST_CATEGORY_1");
        assertEq(categories[1], "TEST_CATEGORY_2");
        assertEq(categories[2], "TEST_CATEGORY_3");
    }
}
