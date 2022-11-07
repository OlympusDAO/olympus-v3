// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";
import {Quabi} from "test/lib/quabi/Quabi.sol";
import {MockLegacyAuthority} from "test/mocks/MockLegacyAuthority.sol";

import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import "modules/MINTR/OlympusMinter.sol";
import "src/Kernel.sol";

contract MINTRTest is Test {
    using ModuleTestFixtureGenerator for OlympusMinter;
    using larping for *;

    Kernel internal kernel;
    OlympusMinter internal MINTR;
    IOlympusAuthority internal auth;
    OlympusERC20Token internal ohm;

    address[] public users;
    address public godmode;
    address public dummy;

    function setUp() public {
        kernel = new Kernel();
        auth = new MockLegacyAuthority(address(0x0));
        ohm = new OlympusERC20Token(address(auth));
        MINTR = new OlympusMinter(kernel, address(ohm));

        // Set vault in authority to MINTR module
        auth.vault.larp(address(MINTR));

        // Create dummy user
        users = (new UserFactory()).create(3);

        kernel.executeAction(Actions.InstallModule, address(MINTR));

        godmode = MINTR.generateGodmodeFixture(type(OlympusMinter).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        dummy = MINTR.generateDummyFixture();
        kernel.executeAction(Actions.ActivatePolicy, dummy);
    }

    function test_KEYCODE() public {
        assertEq("MINTR", fromKeycode(MINTR.KEYCODE()));
    }

    function test_ApprovedAddressMintsOhm(address to_, uint256 amount_) public {
        // Will test mint not working against zero-address separately
        vm.assume(to_ != address(0x0));
        vm.assume(amount_ != 0);

        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_);

        vm.prank(godmode);
        MINTR.mintOhm(to_, amount_);

        assertEq(ohm.balanceOf(to_), amount_);
    }

    function testRevert_ApprovedAddressCannotMintToZeroAddress(uint256 amount_) public {
        vm.assume(amount_ != 0);

        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_);

        bytes memory err = abi.encodePacked("ERC20: mint to the zero address");
        vm.expectRevert(err);
        vm.prank(godmode);
        MINTR.mintOhm(address(0x0), amount_);
    }

    function testRevert_UnapprovedAddressCannotMintOhm(address to_, uint256 amount_) public {
        // Have user try to mint
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            users[0]
        );
        vm.expectRevert(err);
        vm.prank(users[0]);
        MINTR.mintOhm(to_, amount_);
    }

    function testCorrectness_ApprovedAddressBurnsOhm(address from_, uint256 amount_) public {
        vm.assume(from_ != address(0x0));
        vm.assume(amount_ != 0);

        // Setup: mint ohm into user0
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_);

        vm.prank(godmode);
        MINTR.mintOhm(from_, amount_);
        assertEq(ohm.balanceOf(from_), amount_);

        vm.prank(from_);
        ohm.approve(address(MINTR), amount_);

        vm.prank(godmode);
        MINTR.burnOhm(from_, amount_);

        assertEq(ohm.balanceOf(from_), 0);
    }

    function testRevert_ApprovedAddressCannotBurnFromAddressWithoutApproval(uint256 amount_)
        public
    {
        vm.assume(amount_ != 0);

        // Setup: mint ohm into user0
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_);
        vm.prank(godmode);
        MINTR.mintOhm(users[0], amount_);

        assertEq(ohm.balanceOf(users[0]), amount_);

        bytes memory err = abi.encodePacked("ERC20: burn amount exceeds allowance");
        vm.expectRevert(err);
        vm.prank(godmode);
        MINTR.burnOhm(users[0], amount_);
    }

    // Removed burn from zero address test because the functionality cannot be tested.
    // The OlympusERC20 requires the address to have approved a token before a burn (which is checked first).
    // It's not possible to reach the burn error in a burnFrom call.

    function testRevert_UnapprovedAddressCannotBurnOhm(uint256 amount_) public {
        vm.assume(amount_ != 0);

        // Setup: mint ohm into user0
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_);

        vm.prank(godmode);
        MINTR.mintOhm(users[1], amount_);
        assertEq(ohm.balanceOf(users[1]), amount_);

        vm.prank(users[1]);
        ohm.approve(users[0], amount_);

        // Have user try to burn, expect revert
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            users[0]
        );
        vm.expectRevert(err);
        vm.prank(users[0]);
        MINTR.burnOhm(users[1], amount_);
    }

    function testCorrectness_ApprovedAddressCanOnlyMintUpToApprovalLimit(uint256 approval_) public {
        vm.assume(approval_ != 0 && approval_ != type(uint256).max);

        // Approve address to mint approval_ amount
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, approval_);

        // Mint approval_ amount to user0
        vm.prank(godmode);
        MINTR.mintOhm(users[0], approval_);

        assertEq(ohm.balanceOf(users[0]), approval_);

        // Try to mint 1 more OHM and expect revert
        bytes memory err = abi.encodeWithSignature("MINTR_NotApproved()");
        vm.expectRevert(err);
        vm.prank(godmode);
        MINTR.mintOhm(users[1], 1);

        assertEq(ohm.balanceOf(users[1]), 0);
    }

    function testCorrectness_IncreaseMinterApprovalAllowsMoreMinting(uint256 amount_) public {
        vm.assume(amount_ != 0);

        // Check that test fixture has no mintApproval to start with
        assertEq(MINTR.mintApproval(godmode), 0);

        // Approve test fixture to mint amount_
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_);

        // Check that test fixture has mintApproval of amount_
        assertEq(MINTR.mintApproval(godmode), amount_);

        // Increase test fixture's mintApproval by max uint256, expect approval to be max uint256
        // This should work because the increase function will not overflow
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, type(uint256).max);

        // Check that test fixture has mintApproval of max uint256
        assertEq(MINTR.mintApproval(godmode), type(uint256).max);

        // Increase test fixture's mintApproval by 1, expect nothing to happen since it's already max uint256
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, 1);

        // Check that test fixture has mintApproval of max uint256
        assertEq(MINTR.mintApproval(godmode), type(uint256).max);
    }

    function testCorrectness_DecreaseMinterApprovalAllowsLessMinting(uint256 amount_) public {
        vm.assume(amount_ > 1);

        // Approve test fixture to mint amount_
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_);

        // Check that test fixture has mintApproval of amount_
        assertEq(MINTR.mintApproval(godmode), amount_);

        // Decrease test fixture's mintApproval to 0
        vm.prank(godmode);
        MINTR.decreaseMintApproval(godmode, amount_);

        // Check that test fixture has mintApproval of 0
        assertEq(MINTR.mintApproval(godmode), 0);

        // Decrease test fixture's mintApproval to 0 again, expect nothing to happen since it's already 0
        vm.prank(godmode);
        MINTR.decreaseMintApproval(godmode, amount_);

        // Increase test fixture's mintApproval to less than amount_
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, amount_ - 1);

        // Check that test fixture has mintApproval of less than amount_
        assertLt(MINTR.mintApproval(godmode), amount_);

        // Decrease test fixture's mintApproval to 0 by calling with amount_
        // This should work since the decrease function should decrease to 0 if the amount is greater than the current approval
        vm.prank(godmode);
        MINTR.decreaseMintApproval(godmode, amount_);

        // Check that test fixture has mintApproval of 0
        assertEq(MINTR.mintApproval(godmode), 0);
    }

    function testRevert_CannotMintOrBurnZero() public {
        // Approve test fixture to mint max uint256
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, type(uint256).max);

        // Try to mint 0 OHM and expect revert
        bytes memory err = abi.encodeWithSignature("MINTR_ZeroAmount()");
        vm.expectRevert(err);
        vm.prank(godmode);
        MINTR.mintOhm(users[0], 0);

        // Mint 1 OHM to user0 so balance isn't 0
        vm.prank(godmode);
        MINTR.mintOhm(users[0], 1);

        // Try to burn 0 OHM and expect revert
        vm.expectRevert(err);
        vm.prank(godmode);
        MINTR.burnOhm(users[0], 0);
    }

    function testCorrectness_Shutdown(uint256 amount_) public {
        vm.assume(amount_ != 0);

        // Approve test fixture to mint max uint256
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, type(uint256).max);

        // Mint amount_ OHM to user0 so balance isn't 0
        vm.prank(godmode);
        MINTR.mintOhm(users[0], amount_);

        // Shutdown the system
        vm.prank(godmode);
        MINTR.deactivate();

        // Try to mint amount_ OHM and expect revert
        bytes memory err = abi.encodeWithSignature("MINTR_NotActive()");
        vm.expectRevert(err);
        vm.prank(godmode);
        MINTR.mintOhm(users[0], amount_);

        // Try to burn 1 OHM and expect revert
        vm.expectRevert(err);
        vm.prank(godmode);
        MINTR.burnOhm(users[0], amount_);

        // Check balance still the same
        assertEq(ohm.balanceOf(users[0]), amount_);

        // Reactivate the system
        vm.prank(godmode);
        MINTR.activate();

        // Approve test fixture to mint max uint256 again (since no infinite approval)
        vm.prank(godmode);
        MINTR.increaseMintApproval(godmode, type(uint256).max);

        // Approve MINTR to burn ohm from user0
        vm.prank(users[0]);
        ohm.approve(address(MINTR), amount_);

        // Burn amount_ OHM from user0
        vm.prank(godmode);
        MINTR.burnOhm(users[0], amount_);

        // Check balance is 0
        assertEq(ohm.balanceOf(users[0]), 0);

        // Mint amount_ OHM to user1
        vm.prank(godmode);
        MINTR.mintOhm(users[0], amount_);

        // Check balance of user1
        assertEq(ohm.balanceOf(users[0]), amount_);
    }

    function testRevert_AddressWithPermCannotShutdownOrRestart() public {
        // Check status of MINTR
        assertEq(MINTR.active(), true);

        // Try to deactivate with non-approved user
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            users[0]
        );
        vm.expectRevert(err);
        vm.prank(users[0]);
        MINTR.deactivate();

        assertEq(MINTR.active(), true);

        // Deactivate with approved user
        vm.prank(godmode);
        MINTR.deactivate();

        assertEq(MINTR.active(), false);

        // Call deactivate again and expect nothing to happen since it's already deactivated
        vm.prank(godmode);
        MINTR.deactivate();

        assertEq(MINTR.active(), false);

        // Try to reactivate with non-approved user
        vm.expectRevert(err);
        vm.prank(users[0]);
        MINTR.activate();

        assertEq(MINTR.active(), false);

        // Reactivate with approved user
        vm.prank(godmode);
        MINTR.activate();

        assertEq(MINTR.active(), true);

        // Call activate again and expect nothing to happen since it's already activated
        vm.prank(godmode);
        MINTR.activate();

        assertEq(MINTR.active(), true);
    }
}
