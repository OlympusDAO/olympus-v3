// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "modules/LQREG/OlympusLiquidityRegistry.sol";
import "src/Kernel.sol";

contract LQREGTest is Test {
    using ModuleTestFixtureGenerator for OlympusLiquidityRegistry;

    address public godmode;

    Kernel internal kernel;
    OlympusLiquidityRegistry internal lqreg;

    function setUp() public {
        // Deploy Kernel and modules
        {
            kernel = new Kernel();
            lqreg = new OlympusLiquidityRegistry(kernel);
        }

        // Generate fixtures
        {
            godmode = lqreg.generateGodmodeFixture(type(OlympusLiquidityRegistry).name);
        }

        // Install modules and policies on Kernel
        {
            kernel.executeAction(Actions.InstallModule, address(lqreg));
            kernel.executeAction(Actions.ActivatePolicy, godmode);
        }
    }

    /// [X]  Module Data
    ///     [X]  KEYCODE returns correctly
    ///     [X]  VERSION returns correctly

    function test_KEYCODE() public {
        assertEq("LQREG", fromKeycode(lqreg.KEYCODE()));
    }

    function test_VERSION() public {
        (uint8 major, uint8 minor) = lqreg.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    /// [X]  addVault
    ///     [X]  Unapproved address cannot call
    ///     [X]  Approved address can add vault

    function testCorrectness_unapprovedAddressCannotAddVault(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to add vault as unapproved user
        vm.prank(user_);
        lqreg.addVault(address(0));
    }

    function testCorrectness_approvedAddressCanAddVault() public {
        // Verify initial state
        assertEq(lqreg.activeVaultCount(), 0);

        vm.prank(godmode);
        lqreg.addVault(address(0));

        // Verify vault was added
        assertEq(lqreg.activeVaultCount(), 1);
        assertEq(lqreg.activeVaults(0), address(0));
    }

    /// [X]  removeVault
    ///     [X]  Unapproved address cannot call
    ///     [X]  Approved address can remove vault

    function _removeVaultSetup() internal {
        vm.prank(godmode);
        lqreg.addVault(address(0));
    }

    function testCorrectness_unapprovedAddressCannotRemoveVault(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to add vault as unapproved user
        vm.prank(user_);
        lqreg.removeVault(address(0));
    }

    function testCorrectness_approvedAddressCanRemoveVault() public {
        _removeVaultSetup();

        // Add second vault
        vm.prank(godmode);
        lqreg.addVault(address(1));

        // Verify initial state
        assertEq(lqreg.activeVaultCount(), 2);
        assertEq(lqreg.activeVaults(0), address(0));
        assertEq(lqreg.activeVaults(1), address(1));

        vm.prank(godmode);
        lqreg.removeVault(address(0));

        // Verify vault was removed
        assertEq(lqreg.activeVaultCount(), 1);
        assertEq(lqreg.activeVaults(0), address(1));
    }
}
