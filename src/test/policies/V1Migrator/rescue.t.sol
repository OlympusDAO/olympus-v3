// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IV1Migrator} from "src/policies/interfaces/IV1Migrator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {V1Migrator} from "src/policies/V1Migrator.sol";
import {Hashes} from "@openzeppelin-5.3.0/utils/cryptography/Hashes.sol";

import {V1MigratorTest} from "src/test/policies/V1Migrator/V1MigratorTest.sol";

/// @title V1MigratorRescueTest
/// @notice Test suite for the rescue function in V1Migrator
contract V1MigratorRescueTest is V1MigratorTest {
    MockOhm internal randomToken;

    function setUp() public override {
        super.setUp();
        randomToken = new MockOhm("Random Token", "RAND", 18);
    }

    // =========  RESCUE FUNCTION TESTS  ========= //

    // given contract is enabled
    //  given caller is admin
    //    [X] it transfers entire balance to admin

    function test_rescue_givenEnabled_givenAdmin() public {
        // Deal random tokens to migrator
        uint256 amount = 100e18;
        randomToken.mint(address(migrator), amount);

        uint256 balanceBefore = randomToken.balanceOf(adminUser);

        // Rescue as admin
        vm.prank(adminUser);
        migrator.rescue(IERC20(address(randomToken)));

        // Verify balance transferred
        assertEq(
            randomToken.balanceOf(adminUser),
            balanceBefore + amount,
            "Admin should receive rescued tokens"
        );
        assertEq(randomToken.balanceOf(address(migrator)), 0, "Migrator should have zero balance");
    }

    // given contract is enabled
    //  given caller is legacy migration admin
    //    [X] it transfers entire balance to legacy migration admin

    function test_rescue_givenEnabled_givenLegacyMigrationAdmin() public {
        // Deal random tokens to migrator
        uint256 amount = 100e18;
        randomToken.mint(address(migrator), amount);

        uint256 balanceBefore = randomToken.balanceOf(legacyMigrationAdmin);

        // Rescue as legacy migration admin
        vm.prank(legacyMigrationAdmin);
        migrator.rescue(IERC20(address(randomToken)));

        // Verify balance transferred
        assertEq(
            randomToken.balanceOf(legacyMigrationAdmin),
            balanceBefore + amount,
            "Legacy migration admin should receive rescued tokens"
        );
        assertEq(randomToken.balanceOf(address(migrator)), 0, "Migrator should have zero balance");
    }

    // given contract is enabled
    //  given caller is not admin and not legacy migration admin
    //    [X] it reverts

    function test_rescue_givenEnabled_givenUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != adminUser);
        vm.assume(caller_ != legacyMigrationAdmin);

        // Deal random tokens to migrator
        uint256 amount = 100e18;
        randomToken.mint(address(migrator), amount);

        // Expect revert when unauthorized user tries to rescue
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        migrator.rescue(IERC20(address(randomToken)));
    }

    // given contract is enabled
    //  given token is zero address
    //    [X] it reverts

    function test_rescue_givenEnabled_givenZeroToken_reverts() public {
        vm.expectRevert(IV1Migrator.ZeroAddress.selector);
        vm.prank(adminUser);
        migrator.rescue(IERC20(address(0)));
    }

    // given contract is enabled
    //  given contract has no token balance
    //    [X] it reverts

    function test_rescue_givenEnabled_givenZeroBalance_reverts() public {
        // Don't deal any tokens to migrator

        vm.expectRevert(IV1Migrator.ZeroAmount.selector);
        vm.prank(adminUser);
        migrator.rescue(IERC20(address(randomToken)));
    }

    // given contract is disabled
    //  given caller is admin
    //    [X] it reverts

    function test_rescue_givenDisabled_reverts() public {
        // Disable the contract
        vm.prank(emergencyUser);
        migrator.disable("");

        // Deal random tokens to migrator
        uint256 amount = 100e18;
        randomToken.mint(address(migrator), amount);

        // Expect revert when trying to rescue while disabled
        vm.expectRevert();
        vm.prank(adminUser);
        migrator.rescue(IERC20(address(randomToken)));
    }

    // given contract is enabled
    //  given caller is admin
    //  given rescuing OHM v1
    //    [X] it transfers entire balance to admin

    function test_rescue_givenEnabled_givenAdmin_rescuesOHMv1() public {
        // Deal OHM v1 tokens to migrator
        uint256 amount = 100e9;
        ohmV1.mint(address(migrator), amount);

        uint256 balanceBefore = ohmV1.balanceOf(adminUser);

        // Rescue as admin
        vm.prank(adminUser);
        migrator.rescue(IERC20(address(ohmV1)));

        // Verify balance transferred
        assertEq(
            ohmV1.balanceOf(adminUser),
            balanceBefore + amount,
            "Admin should receive rescued OHM v1"
        );
        assertEq(ohmV1.balanceOf(address(migrator)), 0, "Migrator should have zero OHM v1 balance");
    }

    // given contract is enabled
    //  given caller is admin
    //  given rescuing OHM v2
    //    [X] it transfers entire balance to admin

    function test_rescue_givenEnabled_givenAdmin_rescuesOHMv2() public {
        // Deal OHM v2 tokens to migrator
        uint256 amount = 100e9;
        ohmV2.mint(address(migrator), amount);

        uint256 balanceBefore = ohmV2.balanceOf(adminUser);

        // Rescue as admin
        vm.prank(adminUser);
        migrator.rescue(IERC20(address(ohmV2)));

        // Verify balance transferred
        assertEq(
            ohmV2.balanceOf(adminUser),
            balanceBefore + amount,
            "Admin should receive rescued OHM v2"
        );
        assertEq(ohmV2.balanceOf(address(migrator)), 0, "Migrator should have zero OHM v2 balance");
    }

    // given contract is enabled
    //  given caller is admin
    //    [X] it emits Rescued event

    function test_rescue_givenEnabled_givenAdmin_emitsRescuedEvent() public {
        // Deal random tokens to migrator
        uint256 amount = 100e18;
        randomToken.mint(address(migrator), amount);

        // Expect Rescued event
        vm.expectEmit(true, true, false, true);
        emit IV1Migrator.Rescued(address(randomToken), adminUser, amount);

        // Rescue as admin
        vm.prank(adminUser);
        migrator.rescue(IERC20(address(randomToken)));
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable,unwrapped-modifier-logic)
