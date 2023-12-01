// SPDX-License-Identifier: MAGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "modules/CHREG/OlympusClearinghouseRegistry.sol";
import "src/Kernel.sol";

/// Clearinghouse Registry Tests:
///
/// [X]  Constructor
///     [X]  Cannot pass a duplicated address.
///     [X]  Cannot pass the same address as active and inactive.
///     [X]  Storage is properly updated.
/// [X]  Module Data
///     [X]  KEYCODE returns correctly.
///     [X]  VERSION returns correctly.
/// [X]  activateClearinghouse
///     [X]  Unapproved addresses cannot call.
///     [X]  Approved policies can activate clearinghouse.
///     [X]  Address is only registered once.
///     [X]  Storage is properly updated.
///     [X]  Event is emitted.
/// [X]  deactivateClearinghouse
///     [X]  Unapproved addresses cannot call.
///     [X]  Approved policies can deactivate clearinghouse.
///     [X]  Inactive Clearinghouses can't be deactivated.
///     [X]  Storage is properly updated.
///     [X]  Event is emitted.

contract CHREGTest is Test {
    using ModuleTestFixtureGenerator for OlympusClearinghouseRegistry;

    address public godmode;
    address public active;
    address[] public inactive;

    Kernel internal kernel;
    OlympusClearinghouseRegistry internal chreg;

    // Clearinghouse Expected events
    event ClearinghouseActivated(address indexed clearinghouse);
    event ClearinghouseDeactivated(address indexed clearinghouse);

    function setUp() public {
        // Deploy Kernel and modules
        kernel = new Kernel();
        chreg = new OlympusClearinghouseRegistry(kernel, active, inactive);

        // Generate fixtures
        godmode = chreg.generateGodmodeFixture(type(OlympusClearinghouseRegistry).name);

        // Install modules and policies on Kernel
        kernel.executeAction(Actions.InstallModule, address(chreg));
        kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    /// --- AUX FUNCTIONS -------------------------------------------------------------------------

    function _deactivateClearinghouseSetup() internal {
        vm.startPrank(godmode);
        chreg.activateClearinghouse(address(1));
        chreg.activateClearinghouse(address(2));
        chreg.activateClearinghouse(address(3));
        vm.stopPrank();
    }

    /// --- REGISTRY TESTS ------------------------------------------------------------------------

    function test_constructor() public {
        inactive.push(address(1));
        inactive.push(address(2));
        active = address(3);

        chreg = new OlympusClearinghouseRegistry(kernel, active, inactive);

        // Check: Storage
        assertEq(chreg.activeCount(), 1);
        assertEq(chreg.registryCount(), 3);
        assertEq(chreg.active(0), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));
    }

    function testRevert_constructor_duplicateAddress_inactive() public {
        inactive.push(address(1));
        inactive.push(address(1));
        active = address(3);

        // Expected error
        bytes memory err = abi.encodeWithSelector(CHREGv1.CHREG_InvalidConstructor.selector);
        vm.expectRevert(err);

        chreg = new OlympusClearinghouseRegistry(kernel, active, inactive);
    }

    function testRevert_constructor_bothActiveAndInactive() public {
        inactive.push(address(1));
        inactive.push(address(2));
        active = address(2);

        // Expected error
        bytes memory err = abi.encodeWithSelector(CHREGv1.CHREG_InvalidConstructor.selector);
        vm.expectRevert(err);

        chreg = new OlympusClearinghouseRegistry(kernel, active, inactive);
    }

    function test_KEYCODE() public {
        assertEq("CHREG", fromKeycode(chreg.KEYCODE()));
    }

    function test_VERSION() public {
        (uint8 major, uint8 minor) = chreg.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_approvedAddressCanActivateClearinghouse() public {
        // Verify initial state
        assertEq(chreg.activeCount(), 0);

        vm.prank(godmode);

        // Ensure that the event is emitted
        vm.expectEmit(address(chreg));
        emit ClearinghouseActivated(address(1));

        chreg.activateClearinghouse(address(1));

        // Verify clearinghouse was activateed
        assertEq(chreg.activeCount(), 1);
        assertEq(chreg.registryCount(), 1);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.registry(0), address(1));
    }

    function test_addressIsNotRegisteredTwice() public {
        // Verify initial state
        assertEq(chreg.activeCount(), 0);

        vm.startPrank(godmode);

        // Ensure that the event is emitted
        vm.expectEmit(address(chreg));
        emit ClearinghouseActivated(address(1));

        chreg.activateClearinghouse(address(1));

        // Verify clearinghouse was activateed
        assertEq(chreg.activeCount(), 1);
        assertEq(chreg.registryCount(), 1);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.registry(0), address(1));

        chreg.deactivateClearinghouse(address(1));

        // Verify clearinghouse was deactivateed
        assertEq(chreg.activeCount(), 0);
        assertEq(chreg.registryCount(), 1);
        assertEq(chreg.registry(0), address(1));

        // Ensure that the event is emitted
        vm.expectEmit(address(chreg));
        emit ClearinghouseActivated(address(1));

        chreg.activateClearinghouse(address(1));

        // Verify clearinghouse was activateed
        assertEq(chreg.activeCount(), 1);
        assertEq(chreg.registryCount(), 1);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.registry(0), address(1));
        // Verify any element wasn't pushed to registry.
        vm.expectRevert();
        chreg.registry(1);
    }

    function testRevert_unapprovedAddressCannotActivateClearinghouse(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to activate clearinghouse as unapproved user
        vm.prank(user_);
        chreg.activateClearinghouse(address(1));
    }

    function testRevert_cannotActivateTwice() public {
        vm.prank(godmode);
        chreg.activateClearinghouse(address(1));

        // Verify clearinghouse was activateed
        assertEq(chreg.activeCount(), 1);
        assertEq(chreg.registryCount(), 1);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.registry(0), address(1));

        // Expected error
        bytes memory err = abi.encodeWithSelector(
            CHREGv1.CHREG_AlreadyActivated.selector,
            address(1)
        );

        vm.prank(godmode);
        vm.expectRevert(err);
        chreg.activateClearinghouse(address(1));
    }

    function testRevert_unapprovedAddressCannotDeactivateClearinghouse(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to activate clearinghouse as unapproved user
        vm.prank(user_);
        chreg.deactivateClearinghouse(address(1));
    }

    function test_approvedAddressCanDeactivateClearinghouse() public {
        _deactivateClearinghouseSetup();

        // Verify initial state
        assertEq(chreg.activeCount(), 3);
        assertEq(chreg.registryCount(), 3);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.active(1), address(2));
        assertEq(chreg.active(2), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));

        vm.prank(godmode);

        // Ensure that the event is emitted
        vm.expectEmit(address(chreg));
        emit ClearinghouseDeactivated(address(1));

        chreg.deactivateClearinghouse(address(1));

        // Verify clearinghouse was deactivated
        assertEq(chreg.activeCount(), 2);
        assertEq(chreg.registryCount(), 3);
        assertEq(chreg.active(1), address(2));
        assertEq(chreg.active(0), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));
    }

    function testRevert_deactivateInactiveClearinghouse() public {
        _deactivateClearinghouseSetup();

        // Verify initial state
        assertEq(chreg.activeCount(), 3);
        assertEq(chreg.registryCount(), 3);
        assertEq(chreg.active(0), address(1));
        assertEq(chreg.active(1), address(2));
        assertEq(chreg.active(2), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));

        vm.startPrank(godmode);

        // Ensure that the event is emitted
        vm.expectEmit(address(chreg));
        emit ClearinghouseDeactivated(address(1));

        chreg.deactivateClearinghouse(address(1));

        // Verify clearinghouse was deactivated
        assertEq(chreg.activeCount(), 2);
        assertEq(chreg.registryCount(), 3);
        assertEq(chreg.active(1), address(2));
        assertEq(chreg.active(0), address(3));
        assertEq(chreg.registry(0), address(1));
        assertEq(chreg.registry(1), address(2));
        assertEq(chreg.registry(2), address(3));

        // Expected error
        bytes memory err = abi.encodeWithSelector(CHREGv1.CHREG_NotActivated.selector, address(1));
        vm.expectRevert(err);
        chreg.deactivateClearinghouse(address(1));
    }
}
