// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
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

    /// [X]  addAMO
    ///     [X]  Unapproved address cannot call
    ///     [X]  Approved address can add AMO

    function testCorrectness_unapprovedAddressCannotAddAMO(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to add AMO as unapproved user
        vm.prank(user_);
        lqreg.addAMO(address(0));
    }

    function testCorrectness_approvedAddressCanAddAMO() public {
        // Verify initial state
        assertEq(lqreg.activeAMOCount(), 0);

        vm.prank(godmode);
        lqreg.addAMO(address(0));

        // Verify AMO was added
        assertEq(lqreg.activeAMOCount(), 1);
        assertEq(lqreg.activeAMOs(0), address(0));
    }

    /// [X]  removeAMO
    ///     [X]  Unapproved address cannot call
    ///     [X]  Fails if AMO at passed index doesn't match passed AMO
    ///     [X]  Approved address can remove AMO

    function _removeAMOSetup() internal {
        vm.prank(godmode);
        lqreg.addAMO(address(0));
    }

    function testCorrectness_unapprovedAddressCannotRemoveAMO(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to add AMO as unapproved user
        vm.prank(user_);
        lqreg.removeAMO(0, address(0));
    }

    function testCorrectness_removeAMOFailsWithSanityCheck() public {
        _removeAMOSetup();

        // Expected error
        bytes memory err = abi.encodeWithSignature("LQREG_RemovalMismatch()");
        vm.expectRevert(err);

        // Try to remove AMO with mismatched address
        vm.prank(godmode);
        lqreg.removeAMO(0, address(1));
    }

    function testCorrectness_approvedAddressCanRemoveAMO() public {
        _removeAMOSetup();

        // Add second AMO
        vm.prank(godmode);
        lqreg.addAMO(address(1));

        // Verify initial state
        assertEq(lqreg.activeAMOCount(), 2);
        assertEq(lqreg.activeAMOs(0), address(0));
        assertEq(lqreg.activeAMOs(1), address(1));

        vm.prank(godmode);
        lqreg.removeAMO(0, address(0));

        // Verify AMO was removed
        assertEq(lqreg.activeAMOCount(), 1);
        assertEq(lqreg.activeAMOs(0), address(1));
    }
}
