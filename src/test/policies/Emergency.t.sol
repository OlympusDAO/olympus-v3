// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";
import {MockLegacyAuthority} from "test/mocks/MockLegacyAuthority.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter, OHM} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Emergency} from "policies/Emergency.sol";

// solhint-disable-next-line max-states-count
contract EmergencyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusMinter;
    using ModuleTestFixtureGenerator for OlympusTreasury;
    using larping for *;

    UserFactory public userCreator;
    address internal alice;
    address internal guardian;
    address internal emergencyMS;

    OlympusERC20Token internal ohm;
    MockERC20 internal reserve;

    Kernel internal kernel;
    IOlympusAuthority internal authority;
    OlympusTreasury internal TRSRY;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;

    Emergency internal emergency;
    RolesAdmin internal rolesAdmin;

    address internal treasuryAdmin;
    address internal minterAdmin;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            // Create test accounts
            address[] memory users = userCreator.create(3);
            alice = users[0];
            guardian = users[1];
            emergencyMS = users[2];
        }

        {
            // Deploy mock legacy authority
            authority = new MockLegacyAuthority(address(0x0));

            // Deploy mock tokens
            ohm = new OlympusERC20Token(address(authority));
            reserve = new MockERC20("Reserve", "RSV", 18);
        }

        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy modules (some mocks)
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);
        }

        {
            // Deploy emergency policy
            emergency = new Emergency(kernel);

            // Deploy ROLES administrator
            rolesAdmin = new RolesAdmin(kernel);

            // Deploy authorized policy to call MINTR and TRSRY functions
            treasuryAdmin = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);
            minterAdmin = MINTR.generateGodmodeFixture(type(OlympusMinter).name);
        }

        {
            // Initialize system and kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(emergency));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, treasuryAdmin);
            kernel.executeAction(Actions.ActivatePolicy, minterAdmin);
        }
        {
            // Configure access control

            // Emergency ROLES
            rolesAdmin.grantRole("emergency_shutdown", emergencyMS);
            rolesAdmin.grantRole("emergency_restart", guardian);
        }

        // Larp MINTR as legacy vault
        authority.vault.larp(address(MINTR));

        // Mint tokens to TRSRY for testing
        reserve.mint(address(TRSRY), 1_000_000 * 1e18);

        // Approve minterAdmin for unlimited minting
        vm.prank(minterAdmin);
        MINTR.increaseMintApproval(address(minterAdmin), type(uint256).max);

        // Approve treasuryAdmin for unlimited withdrawals and debt of reserve token
        vm.prank(treasuryAdmin);
        TRSRY.increaseWithdrawApproval(address(treasuryAdmin), reserve, type(uint256).max);

        vm.prank(treasuryAdmin);
        TRSRY.increaseDebtorApproval(address(treasuryAdmin), reserve, type(uint256).max);
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](3);
        expectedDeps[0] = toKeycode("TRSRY");
        expectedDeps[1] = toKeycode("MINTR");
        expectedDeps[2] = toKeycode("ROLES");

        Keycode[] memory deps = emergency.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](4);
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        expectedPerms[0] = Permissions(TRSRY_KEYCODE, TRSRY.deactivate.selector);
        expectedPerms[1] = Permissions(TRSRY_KEYCODE, TRSRY.activate.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.deactivate.selector);
        expectedPerms[3] = Permissions(MINTR_KEYCODE, MINTR.activate.selector);

        Permissions[] memory perms = emergency.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // ========= TESTS ========= //
    // DONE
    // [X] Shutdown
    //    [X] Shutdown MINTR
    //    [X] Shutdown TRSRY
    //    [X] Shutdown both
    //    [X] Only emergency_shutdown can shutdown
    // [X] Restart
    //    [X] Restart MINTR
    //    [X] Restart TRSRY
    //    [X] Restart both
    //    [X] Only emergency_restart can restart

    function testCorrectness_ShutdownMINTR() public {
        // Check that MINTR is active initially
        assertTrue(MINTR.active());

        // Try minting OHM and expect to pass
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 2e9);
        assertEq(ohm.balanceOf(alice), 2e9);

        // Try burning OHM and expect to pass
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);
        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);
        assertEq(ohm.balanceOf(alice), 1e9);

        // Shutdown MINTR
        vm.prank(emergencyMS);
        emergency.shutdownMinting();

        // Check that MINTR is inactive
        assertTrue(!MINTR.active());

        // Try minting OHM and expect to fail
        bytes memory err = abi.encodeWithSignature("MINTR_NotActive()");
        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Check that no OHM was minted
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try burning OHM and expect to fail
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);

        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);

        // Check that no OHM was burned
        assertEq(ohm.balanceOf(alice), 1e9);
    }

    function testCorrectness_ShutdownTRSRY() public {
        // Check that TRSRY is active initially
        assertTrue(TRSRY.active());

        // Try withdrawing reserve and expect to pass
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);

        // Check that reserve was withdrawn
        assertEq(reserve.balanceOf(alice), 1e18);

        // Try incurring debt and expect to pass
        vm.prank(treasuryAdmin);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that reserves are borrowed
        assertEq(reserve.balanceOf(treasuryAdmin), 1e18);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 1e18);

        // Shutdown TRSRY
        vm.prank(emergencyMS);
        emergency.shutdownWithdrawals();

        // Check that TRSRY is inactive
        assertTrue(!TRSRY.active());

        // Try withdrawing reserve and expect to fail
        bytes memory err = abi.encodeWithSignature("TRSRY_NotActive()");
        vm.expectRevert(err);
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);

        // Check that no reserve was withdrawn
        assertEq(reserve.balanceOf(alice), 1e18);

        // Try to incur debt and expect to fail
        vm.prank(treasuryAdmin);
        vm.expectRevert(err);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that no debt was incurred
        assertEq(reserve.balanceOf(treasuryAdmin), 1e18);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 1e18);
    }

    function testCorrectness_Shutdown() public {
        // Check that MINTR and TRSRY are active initially
        assertTrue(MINTR.active());
        assertTrue(TRSRY.active());

        // Try minting OHM expect to pass
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 2e9);
        assertEq(ohm.balanceOf(alice), 2e9);

        // Try burning OHM and expect to pass
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);

        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try withdrawing reserve and expect to pass
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);
        assertEq(reserve.balanceOf(alice), 1e18);

        // Try incurring debt and expect to pass
        vm.prank(treasuryAdmin);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that reserves are borrowed
        assertEq(reserve.balanceOf(treasuryAdmin), 1e18);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 1e18);

        // Shutdown both
        vm.prank(emergencyMS);
        emergency.shutdown();

        // Check that MINTR and TRSRY are inactive
        assertTrue(!MINTR.active());
        assertTrue(!TRSRY.active());

        // Try minting OHM and expect to fail
        bytes memory err = abi.encodeWithSignature("MINTR_NotActive()");
        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Check that no OHM was minted
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try burning OHM and expect to fail
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);

        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);

        // Check that no OHM was burned
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try withdrawing reserve and expect to fail
        err = abi.encodeWithSignature("TRSRY_NotActive()");
        vm.expectRevert(err);
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);

        // Check that no reserve was withdrawn
        assertEq(reserve.balanceOf(alice), 1e18);

        // Try to incur debt and expect to fail
        vm.prank(treasuryAdmin);
        vm.expectRevert(err);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that no debt was incurred
        assertEq(reserve.balanceOf(treasuryAdmin), 1e18);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 1e18);
    }

    function testCorrectness_OnlyPermissionedAddressCanShutdown() public {
        // Check that MINTR and TRSRY are active initially
        assertTrue(MINTR.active());
        assertTrue(TRSRY.active());

        // Try to shutdown with non-permissioned address and expect to fail
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_shutdown")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        emergency.shutdown();

        // Check that MINTR and TRSRY are still active
        assertTrue(MINTR.active());
        assertTrue(TRSRY.active());

        // Shutdown with permissioned address
        vm.prank(emergencyMS);
        emergency.shutdown();

        // Check that MINTR and TRSRY are inactive
        assertTrue(!MINTR.active());
        assertTrue(!TRSRY.active());
    }

    function testCorrectness_OnlyPermissionedAddressCanShutdownMinting() public {
        // Check that MINTR is active initially
        assertTrue(MINTR.active());

        // Try to shutdown with non-permissioned address and expect to fail
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_shutdown")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        emergency.shutdownMinting();

        // Check that MINTR is still active
        assertTrue(MINTR.active());

        // Shutdown with permissioned address
        vm.prank(emergencyMS);
        emergency.shutdownMinting();

        // Check that MINTR is inactive
        assertTrue(!MINTR.active());
    }

    function testCorrectness_OnlyPermissionedAddressCanShutdownWithdrawals() public {
        // Check that TRSRY is active initially
        assertTrue(TRSRY.active());

        // Try to shutdown with non-permissioned address and expect to fail
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_shutdown")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        emergency.shutdownWithdrawals();

        // Check that TRSRY is still active
        assertTrue(TRSRY.active());

        // Shutdown with permissioned address
        vm.prank(emergencyMS);
        emergency.shutdownWithdrawals();

        // Check that TRSRY is inactive
        assertTrue(!TRSRY.active());
    }

    function testCorrectness_RestartMINTR() public {
        // Mint some OHM initially so balance isn't zero
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Shutdown Minting
        vm.prank(emergencyMS);
        emergency.shutdownMinting();

        // Check that MINTR is inactive
        assertTrue(!MINTR.active());

        // Try minting OHM and expect to fail
        bytes memory err = abi.encodeWithSignature("MINTR_NotActive()");
        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Check that no OHM was minted
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try burning OHM and expect to fail
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);

        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);

        // Check that no OHM was burned
        assertEq(ohm.balanceOf(alice), 1e9);

        // Restart MINTR
        vm.prank(guardian);
        emergency.restartMinting();

        // Check that MINTR is active
        assertTrue(MINTR.active());

        // Try minting OHM and expect to succeed
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Check that OHM was minted
        assertEq(ohm.balanceOf(alice), 2e9);

        // Try burning OHM and expect to succeed
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);

        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);

        // Check that OHM was burned
        assertEq(ohm.balanceOf(alice), 1e9);
    }

    function testCorrectness_RestartTRSRY() public {
        // Shutdown Withdrawals
        vm.prank(emergencyMS);
        emergency.shutdownWithdrawals();

        // Check that TRSRY is inactive
        assertTrue(!TRSRY.active());

        // Try withdrawing reserve and expect to fail
        bytes memory err = abi.encodeWithSignature("TRSRY_NotActive()");
        vm.expectRevert(err);
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);

        // Check that no reserve was withdrawn
        assertEq(reserve.balanceOf(alice), 0);

        // Try incuring debt and expect to fail
        vm.prank(treasuryAdmin);
        vm.expectRevert(err);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that no debt was incurred
        assertEq(reserve.balanceOf(treasuryAdmin), 0);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 0);

        // Restart TRSRY
        vm.prank(guardian);
        emergency.restartWithdrawals();

        // Check that TRSRY is active
        assertTrue(TRSRY.active());

        // Try withdrawing reserve and expect to succeed
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);

        // Check that reserve was withdrawn
        assertEq(reserve.balanceOf(alice), 1e18);

        // Try incuring debt and expect to succeed
        vm.prank(treasuryAdmin);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that debt was incurred
        assertEq(reserve.balanceOf(treasuryAdmin), 1e18);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 1e18);
    }

    function testCorrectness_Restart() public {
        // Mint some OHM initially so balance isn't zero
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Shutdown Minting and Withdrawals
        vm.prank(emergencyMS);
        emergency.shutdown();

        // Check that MINTR and TRSRY are inactive
        assertTrue(!MINTR.active());
        assertTrue(!TRSRY.active());

        // Try minting OHM and expect to fail
        bytes memory err = abi.encodeWithSignature("MINTR_NotActive()");
        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Check that no OHM was minted
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try burning OHM and expect to fail
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);

        vm.expectRevert(err);
        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);

        // Check that no OHM was burned
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try withdrawing reserve and expect to fail
        err = abi.encodeWithSignature("TRSRY_NotActive()");
        vm.expectRevert(err);
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);

        // Check that no reserve was withdrawn
        assertEq(reserve.balanceOf(alice), 0);

        // Try incuring debt and expect to fail
        vm.prank(treasuryAdmin);
        vm.expectRevert(err);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that no debt was incurred
        assertEq(reserve.balanceOf(treasuryAdmin), 0);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 0);

        // Restart Minting and Withdrawals
        vm.prank(guardian);
        emergency.restart();

        // Check that MINTR and TRSRY are active
        assertTrue(MINTR.active());
        assertTrue(TRSRY.active());

        // Try minting OHM and expect to succeed
        vm.prank(minterAdmin);
        MINTR.mintOhm(alice, 1e9);

        // Check that OHM was minted
        assertEq(ohm.balanceOf(alice), 2e9);

        // Try burning OHM and expect to succeed
        vm.prank(alice);
        ohm.approve(address(MINTR), 1e9);

        vm.prank(minterAdmin);
        MINTR.burnOhm(alice, 1e9);

        // Check that OHM was burned
        assertEq(ohm.balanceOf(alice), 1e9);

        // Try withdrawing reserve and expect to succeed
        vm.prank(treasuryAdmin);
        TRSRY.withdrawReserves(alice, reserve, 1e18);

        // Check that reserve was withdrawn
        assertEq(reserve.balanceOf(alice), 1e18);

        // Try incuring debt and expect to succeed
        vm.prank(treasuryAdmin);
        TRSRY.incurDebt(reserve, 1e18);

        // Check that debt was incurred
        assertEq(reserve.balanceOf(treasuryAdmin), 1e18);
        assertEq(TRSRY.reserveDebt(reserve, treasuryAdmin), 1e18);
    }

    function testCorrectness_OnlyPermissionedAddressCanRestart() public {
        // Shutdown Minting and Withdrawals
        vm.prank(emergencyMS);
        emergency.shutdown();

        // Check that MINTR and TRSRY are inactive
        assertTrue(!MINTR.active());
        assertTrue(!TRSRY.active());

        // Try restarting with non-permissioned address and expect to fail
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_restart")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        emergency.restart();

        // Check that MINTR and TRSRY are still inactive
        assertTrue(!MINTR.active());
        assertTrue(!TRSRY.active());

        // Try restarting with permissioned address and expect to succeed
        vm.prank(guardian);
        emergency.restart();

        // Check that MINTR and TRSRY are active
        assertTrue(MINTR.active());
        assertTrue(TRSRY.active());
    }

    function testCorrectness_OnlyPermissionedAddressCanRestartMinting() public {
        // Shutdown Minting
        vm.prank(emergencyMS);
        emergency.shutdownMinting();

        // Check that MINTR is inactive
        assertTrue(!MINTR.active());

        // Try restarting with non-permissioned address and expect to fail
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_restart")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        emergency.restartMinting();

        // Check that MINTR is still inactive
        assertTrue(!MINTR.active());

        // Try restarting with permissioned address and expect to succeed
        vm.prank(guardian);
        emergency.restartMinting();

        // Check that MINTR is active
        assertTrue(MINTR.active());
    }

    function testCorrectness_OnlyPermissionedAddressCanRestartWithdrawals() public {
        // Shutdown Withdrawals
        vm.prank(emergencyMS);
        emergency.shutdownWithdrawals();

        // Check that TRSRY is inactive
        assertTrue(!TRSRY.active());

        // Try restarting with non-permissioned address and expect to fail
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("emergency_restart")
        );
        vm.expectRevert(err);
        vm.prank(alice);
        emergency.restartWithdrawals();

        // Check that TRSRY is still inactive
        assertTrue(!TRSRY.active());

        // Try restarting with permissioned address and expect to succeed
        vm.prank(guardian);
        emergency.restartWithdrawals();

        // Check that TRSRY is active
        assertTrue(TRSRY.active());
    }
}
