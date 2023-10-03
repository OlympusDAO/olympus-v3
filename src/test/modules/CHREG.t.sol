// SPDX-License-Identifier: MAGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "modules/CHREG/OlympusClearinghouseRegistry.sol";
import "src/Kernel.sol";

/// Clearinghouse Registry Tests:
///
/// [X]  Module Data
///     [X]  KEYCODE returns correctly
///     [X]  VERSION returns correctly
/// [X]  activateClearinghouse
///     [X]  Unapproved addresses cannot call
///     [X]  Approved policies can activate clearinghouse
///     [X]  Kernel executor can activate clearinghouse manually
/// [X]  deactivateClearinghouse
///     [X]  Unapproved addresses cannot call
///     [X]  Approved policies can deactivate clearinghouse
///     [X]  Kernel executor can deactivate clearinghouse manually

contract CHREGTest is Test {
    using ModuleTestFixtureGenerator for OlympusClearinghouseRegistry;

    address public godmode;

    Kernel internal kernel;
    OlympusClearinghouseRegistry internal chreg;

    function setUp() public {
        // Deploy Kernel and modules
        kernel = new Kernel();
        chreg = new OlympusClearinghouseRegistry(kernel);

        // Generate fixtures
        godmode = chreg.generateGodmodeFixture(type(OlympusClearinghouseRegistry).name);

        // Install modules and policies on Kernel
        kernel.executeAction(Actions.InstallModule, address(chreg));
        kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    function test_KEYCODE() public {
        assertEq("CHREG", fromKeycode(chreg.KEYCODE()));
    }

    function test_VERSION() public {
        (uint8 major, uint8 minor) = chreg.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function testCorrectness_unapprovedAddressCannotActivateClearinghouse(address user_) public {
        vm.assume(user_ != godmode && user_ != kernel.executor());

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to activate clearinghouse as unapproved user
        vm.prank(user_);
        chreg.activateClearinghouse(address(1));

        // Expected error
        bytes memory err2 = abi.encodeWithSelector(
            CHREGv1.Module_OnlyKernelExecutor.selector,
            user_
        );
        vm.expectRevert(err2);

        // Try to activate clearinghouse as unapproved user
        vm.prank(user_);
        chreg.manuallyActivateClearinghouse(address(1));
    }

    function testCorrectness_approvedAddressCanActivateClearinghouse() public {
        // Verify initial state
        assertEq(chreg.activeCount(), 0);

        vm.prank(godmode);
        chreg.activateClearinghouse(address(1));

        // Verify clearinghouse was activateed
        assertEq(chreg.activeCount(), 1);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.registry(0), address(1));

        vm.prank(kernel.executor());
        chreg.manuallyActivateClearinghouse(address(2));

        // Verify clearinghouse was activateed
        assertEq(chreg.activeCount(), 2);
        assertEq(chreg.active(1), address(2));
        assertEq(chreg.registry(1), address(2));
    }

    function _deactivateClearinghouseSetup() internal {
        vm.startPrank(godmode);
        chreg.activateClearinghouse(address(1));
        chreg.activateClearinghouse(address(2));
        chreg.activateClearinghouse(address(3));
        vm.stopPrank();
    }

    function testCorrectness_unapprovedAddressCannotDeactivateClearinghouse(address user_) public {
        vm.assume(user_ != godmode && user_ != kernel.executor());

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to activate clearinghouse as unapproved user
        vm.prank(user_);
        chreg.deactivateClearinghouse(address(1));

        // Expected error
        bytes memory err2 = abi.encodeWithSelector(
            CHREGv1.Module_OnlyKernelExecutor.selector,
            user_
        );
        vm.expectRevert(err2);

        // Try to activate clearinghouse as unapproved user
        vm.prank(user_);
        chreg.manuallyDeactivateClearinghouse(address(1));
    }

    function testCorrectness_approvedAddressCanDeactivateClearinghouse() public {
        _deactivateClearinghouseSetup();

        // Verify initial state
        assertEq(chreg.activeCount(), 3);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.active(1), address(2));
        assertEq(chreg.active(2), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));

        vm.prank(godmode);
        chreg.deactivateClearinghouse(address(1));

        // Verify clearinghouse was deactivated
        assertEq(chreg.activeCount(), 2);
        assertEq(chreg.active(1), address(2));
        assertEq(chreg.active(0), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));

        vm.prank(kernel.executor());
        chreg.manuallyDeactivateClearinghouse(address(2));

        // Verify clearinghouse was deactivated
        assertEq(chreg.activeCount(), 1);
        assertEq(chreg.active(0), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));
    }
}
