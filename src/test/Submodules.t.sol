// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Submodules.sol";

// Tests for ModuleWithSubmodules
// [X] installSubmodule
//     [X] Submodule must be a contract
//     [X] Submodule parent must match the module it is being installed on
//     [X] Submodule must have a valid SubKeycode
//         [X] SubKeycode must have the parent Keycode as its first 5 bytes (Modules are limited to A-Z)
//         [X] SubKeycode must have . as the 6th byte
//         [X] SubKeycode must only contain A-Z, _, or blank characters after the first 6 bytes
//     [X] Submodule must not already be installed
//     [X] Only permissioned contracts can install submodules
//     [X] Submodule is stored on the Module correctly
//     [X] Submodule's INIT function is called on install
// [X] upgradeSubmodule
//     [X] Submodule must be a contract
//     [X] Submodule parent must match the module it is being installed on
//     [X] Submodule must have a valid SubKeycode
//         [X] SubKeycode must have the parent Keycode as its first 5 bytes (Modules are limited to A-Z)
//         [X] SubKeycode must have . as the 6th byte
//         [X] SubKeycode must only contain A-Z, _, or blank characters after the first 6 bytes
//     [X] Another submodule at the same SubKeycode must already be installed
//     [X] New submodule cannot be the same as the old submodule
//     [X] Only permissioned contracts can upgrade submodules
//     [X] Submodule is stored on the Module correctly
//     [X] Submodule's INIT function is called on upgrade
// [X] execOnSubmodule
//     [X] Submodule must be installed
//     [X] Only permissioned contracts can call this function
//     [X] Submodule function reverts are caught and an error is thrown
//     [X] Submodule function return data is passed on to caller
//
// Tests for Submodule
// [ ] constructor
//     [ ] cannot be deployed with a parent whose Keycode doesn't match PARENT()
//     [ ] parent is stored when deployed
// [ ] PARENT - returns the parent Keycode
// [ ] SUBKEYCODE - returns the SubKeycode for the submodule
// [ ] VERSION - returns the version of the submodule
// [ ] INIT - can only be called by the parent Module

contract MockModuleWithSubmodules is ModuleWithSubmodules {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external override onlyKernel {
        // do nothing
    }
}

contract MockWrongModule is ModuleWithSubmodules {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("WRONG");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external override onlyKernel {
        // do nothing
    }
}

contract MockSubmodule is Submodule {
    error MockSubmodule_mockRevert();
    bool public theTruth;

    constructor(Module parent_) Submodule(parent_) {}

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function SUBKEYCODE() public pure virtual override returns (SubKeycode) {
        return toSubKeycode("MOCKY.SUBMODUL3_NICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external override onlyParent {
        theTruth = true;
    }

    function mockFunction() external view onlyParent returns (uint256) {
        return 42;
    }

    function mockRevert() external view onlyParent {
        revert MockSubmodule_mockRevert();
    }
}

contract MockUpgradedSubmodule is Submodule {
    bool public theTruth;

    constructor(Module parent_) Submodule(parent_) {}

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("MOCKY.SUBMODUL3_NICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    function INIT() external override onlyParent {
        theTruth = true;
    }
}

contract MockWrongParent is Submodule {
    bool public theTruth;

    constructor(Module parent_) Submodule(parent_) {}

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("WRONG");
    }

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("WRONG.SUBMODUL3_NICE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external virtual override onlyParent {
        theTruth = true;
    }
}

contract MockInvalidSubKeycodeOne is Submodule {
    bool public theTruth;

    constructor(Module parent_) Submodule(parent_) {}

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("WRONG.SUBMODULE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external override onlyParent {
        theTruth = true;
    }
}

contract MockInvalidSubKeycodeTwo is Submodule {
    bool public theTruth;

    constructor(Module parent_) Submodule(parent_) {}

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("MOCKYASUBMODULE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external override onlyParent {
        theTruth = true;
    }
}

contract MockInvalidSubKeycodeThree is Submodule {
    bool public theTruth;

    constructor(Module parent_) Submodule(parent_) {}

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("MOCKY.SUBMODULE!");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external override onlyParent {
        theTruth = true;
    }
}

contract MockInvalidSubKeycodeFour is Submodule {
    bool public theTruth;

    constructor(Module parent_) Submodule(parent_) {}

    function PARENT() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("MOCKY.S");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    function INIT() external override onlyParent {
        theTruth = true;
    }
}

contract MockPolicy is Policy {
    MockModuleWithSubmodules internal MOCKY;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("MOCKY");

        MOCKY = MockModuleWithSubmodules(getModuleAddress(dependencies[0]));
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](3);
        requests[0] = Permissions(toKeycode("MOCKY"), MOCKY.installSubmodule.selector);
        requests[1] = Permissions(toKeycode("MOCKY"), MOCKY.upgradeSubmodule.selector);
        requests[2] = Permissions(toKeycode("MOCKY"), MOCKY.execOnSubmodule.selector);
    }
}

contract SubmodulesTest is Test {
    using ModuleTestFixtureGenerator for MockModuleWithSubmodules;

    Kernel internal kernel;
    MockModuleWithSubmodules internal module;
    MockSubmodule internal submodule;
    address internal writer;

    function setUp() public {
        // Deploy contracts
        kernel = new Kernel();
        module = new MockModuleWithSubmodules(kernel);
        submodule = new MockSubmodule(module);
        writer = address(new MockPolicy(kernel));

        // Install contracts on kernel
        kernel.executeAction(Actions.InstallModule, address(module));
        kernel.executeAction(Actions.ActivatePolicy, writer);
    }

    function _installSubmodule() internal {
        vm.prank(writer);
        module.installSubmodule(submodule);
    }

    /* ========== MODULE WITH SUBMODULES TESTS ========== */

    function testRevert_installSubmodule_mustBeContract() public {
        MockSubmodule notAContract = MockSubmodule(
            address(uint160(uint256(keccak256(abi.encodePacked("alice")))))
        );

        bytes memory err = abi.encodeWithSignature(
            "TargetNotAContract(address)",
            address(notAContract)
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.installSubmodule(notAContract);
    }

    function testRevert_installSubmodule_parentKeycodeMustMatch() public {
        MockWrongModule wrongModule = new MockWrongModule(kernel);
        kernel.executeAction(Actions.InstallModule, address(wrongModule));
        MockWrongParent wrongParent = new MockWrongParent(wrongModule);

        bytes memory err = abi.encodeWithSignature("Module_InvalidSubmodule()");
        vm.expectRevert(err);
        vm.prank(writer);
        module.installSubmodule(wrongParent);
    }

    function testRevert_installSubmodule_invalidSubKeycode() public {
        // Case 1: First 5 bytes don't match parent
        MockInvalidSubKeycodeOne invalidSubKeycodeOne = new MockInvalidSubKeycodeOne(module);
        bytes memory err = abi.encodeWithSignature(
            "InvalidSubKeycode(bytes20)",
            invalidSubKeycodeOne.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.installSubmodule(invalidSubKeycodeOne);

        // Case 2: 6th byte is not .
        MockInvalidSubKeycodeTwo invalidSubKeycodeTwo = new MockInvalidSubKeycodeTwo(module);
        err = abi.encodeWithSignature(
            "InvalidSubKeycode(bytes20)",
            invalidSubKeycodeTwo.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.installSubmodule(invalidSubKeycodeTwo);

        // Case 3: SubKeycode contains invalid characters
        MockInvalidSubKeycodeThree invalidSubKeycodeThree = new MockInvalidSubKeycodeThree(module);
        err = abi.encodeWithSignature(
            "InvalidSubKeycode(bytes20)",
            invalidSubKeycodeThree.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.installSubmodule(invalidSubKeycodeThree);

        // Case 4: SubKeycode is too short (must be 3 non-blank characters after the period)
        MockInvalidSubKeycodeFour invalidSubKeycodeFour = new MockInvalidSubKeycodeFour(module);
        err = abi.encodeWithSignature(
            "InvalidSubKeycode(bytes20)",
            invalidSubKeycodeFour.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.installSubmodule(invalidSubKeycodeFour);
    }

    function testRevert_installSubmodule_alreadyInstalled() public {
        _installSubmodule();

        bytes memory err = abi.encodeWithSignature(
            "Module_SubmoduleAlreadyInstalled(bytes20)",
            submodule.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.installSubmodule(submodule);
    }

    function testRevert_installSubmodule_onlyPermissioned(address other_) public {
        vm.assume(other_ != writer);

        // Try to install submodule with non-permissioned address, expect revert
        bytes memory err = abi.encodeWithSignature("Module_PolicyNotPermitted(address)", other_);
        vm.expectRevert(err);
        vm.prank(other_);
        module.installSubmodule(submodule);

        // Install with permissioned address, expect success
        vm.prank(writer);
        module.installSubmodule(submodule);
    }

    function test_installSubmodule_stored() public {
        // Check that no submodule is installed on the module yet
        assertEq(module.getSubmodules().length, 0);
        assertEq(address(module.getSubmoduleForKeycode(submodule.SUBKEYCODE())), address(0));

        // Install submodule
        vm.prank(writer);
        module.installSubmodule(submodule);

        // Check that submodule is installed on the module
        assertEq(module.getSubmodules().length, 1);
        assertEq(fromSubKeycode(module.submodules(0)), fromSubKeycode(submodule.SUBKEYCODE()));
        assertEq(
            address(module.getSubmoduleForKeycode(submodule.SUBKEYCODE())),
            address(submodule)
        );
    }

    function test_installSubmodule_INIT() public {
        // Check that the INIT function on the mock submodule has not been called yet
        assertFalse(submodule.theTruth());

        // Install submodule
        vm.prank(writer);
        module.installSubmodule(submodule);

        // Check that the INIT function on the mock submodule has been called
        assertTrue(submodule.theTruth());
    }

    function testRevert_upgradeSubmodule_mustBeContract() public {
        // Install submodule so we can upgrade it
        _installSubmodule();

        // Create a non-contract submodule
        MockSubmodule notAContract = MockSubmodule(
            address(uint160(uint256(keccak256(abi.encodePacked("alice")))))
        );

        bytes memory err = abi.encodeWithSignature(
            "TargetNotAContract(address)",
            address(notAContract)
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.upgradeSubmodule(notAContract);
    }

    function testRevert_upgradeSubmodule_parentKeycodeMustMatch() public {
        // Install submodule so we can upgrade it
        _installSubmodule();

        // Create a submodule with a parent that doesn't match the module
        MockWrongModule wrongModule = new MockWrongModule(kernel);
        kernel.executeAction(Actions.InstallModule, address(wrongModule));
        MockWrongParent wrongParent = new MockWrongParent(wrongModule);

        bytes memory err = abi.encodeWithSignature("Module_InvalidSubmodule()");
        vm.expectRevert(err);
        vm.prank(writer);
        module.upgradeSubmodule(wrongParent);
    }

    function testRevert_upgradeSubmodule_invalidSubKeycode() public {
        // Install submodule so we can upgrade it
        _installSubmodule();

        // Case 1: First 5 bytes don't match parent
        MockInvalidSubKeycodeOne invalidSubKeycodeOne = new MockInvalidSubKeycodeOne(module);
        bytes memory err = abi.encodeWithSignature(
            "InvalidSubKeycode(bytes20)",
            invalidSubKeycodeOne.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.upgradeSubmodule(invalidSubKeycodeOne);

        // Case 2: 6th byte is not .
        MockInvalidSubKeycodeTwo invalidSubKeycodeTwo = new MockInvalidSubKeycodeTwo(module);
        err = abi.encodeWithSignature(
            "InvalidSubKeycode(bytes20)",
            invalidSubKeycodeTwo.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.upgradeSubmodule(invalidSubKeycodeTwo);

        // Case 3: SubKeycode contains invalid characters
        MockInvalidSubKeycodeThree invalidSubKeycodeThree = new MockInvalidSubKeycodeThree(module);
        err = abi.encodeWithSignature(
            "InvalidSubKeycode(bytes20)",
            invalidSubKeycodeThree.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.upgradeSubmodule(invalidSubKeycodeThree);
    }

    function testRevert_upgradeSubmodule_notInstalled() public {
        // Confirm that no submodule is installed
        address currentSubmodule = address(module.getSubmoduleForKeycode(submodule.SUBKEYCODE()));
        assertEq(currentSubmodule, address(0));

        // Try to upgrade submodule, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Module_InvalidSubmoduleUpgrade(bytes20)",
            submodule.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.upgradeSubmodule(submodule);
    }

    function testRevert_upgradeSubmodule_sameAsInstalled() public {
        // Install submodule so we can upgrade it
        _installSubmodule();

        // Try to upgrade submodule to the same submodule, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Module_InvalidSubmoduleUpgrade(bytes20)",
            submodule.SUBKEYCODE()
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.upgradeSubmodule(submodule);
    }

    function testRevert_upgradeSubmodule_onlyPermissioned(address other_) public {
        vm.assume(other_ != writer);

        // Install submodule so we can upgrade it
        _installSubmodule();

        // Create upgraded submodule to upgrade to
        MockUpgradedSubmodule upgradedSubmodule = new MockUpgradedSubmodule(module);

        // Try to upgrade submodule with non-permissioned address, expect revert
        bytes memory err = abi.encodeWithSignature("Module_PolicyNotPermitted(address)", other_);
        vm.expectRevert(err);
        vm.prank(other_);
        module.upgradeSubmodule(upgradedSubmodule);

        // Upgrade submodule with permissioned address, expect success
        vm.prank(writer);
        module.upgradeSubmodule(upgradedSubmodule);
    }

    function test_upgradeSubmodule_stored() public {
        // Install submodule so we can upgrade it
        _installSubmodule();

        // Create upgraded submodule to upgrade to
        MockUpgradedSubmodule upgradedSubmodule = new MockUpgradedSubmodule(module);

        // Confirm that new submodule is not installed
        Submodule currentSubmodule = module.getSubmoduleForKeycode(upgradedSubmodule.SUBKEYCODE());
        (uint8 major_, uint8 minor_) = currentSubmodule.VERSION();
        assertEq(major_, 1);
        assertEq(minor_, 0);

        // Upgrade submodule with permissioned address, expect success
        vm.prank(writer);
        module.upgradeSubmodule(upgradedSubmodule);

        // Confirm that new submodule is installed
        currentSubmodule = module.getSubmoduleForKeycode(upgradedSubmodule.SUBKEYCODE());
        (major_, minor_) = currentSubmodule.VERSION();
        assertEq(major_, 2);
        assertEq(minor_, 0);
    }

    function test_upgradeSubmodule_INIT() public {
        // Install submodule so we can upgrade it
        _installSubmodule();

        // Create upgraded submodule to upgrade to
        MockUpgradedSubmodule upgradedSubmodule = new MockUpgradedSubmodule(module);

        // Confirm that the INIT function on the mock submodule has not been called yet
        assertFalse(upgradedSubmodule.theTruth());

        // Upgrade submodule with permissioned address, expect success
        vm.prank(writer);
        module.upgradeSubmodule(upgradedSubmodule);

        // Confirm that the INIT function on the mock submodule has been called
        assertTrue(upgradedSubmodule.theTruth());
    }

    function testRevert_execOnSubmodule_mustbeInstalled() public {
        // Confirm that submodule is not installed
        SubKeycode subKeycode = submodule.SUBKEYCODE();
        address currentSubmodule = address(module.getSubmoduleForKeycode(subKeycode));
        assertEq(currentSubmodule, address(0));

        // Try to execute function on submodule, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Module_SubmoduleNotInstalled(bytes20)",
            subKeycode
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.execOnSubmodule(
            subKeycode,
            abi.encodeWithSelector(MockSubmodule.mockFunction.selector)
        );
    }

    function testRevert_execOnSubmodule_onlyPermissioned(address other_) public {
        vm.assume(other_ != writer);

        // Install submodule so we can execute function on it
        _installSubmodule();

        SubKeycode subKeycode = submodule.SUBKEYCODE();

        // Try to execute function on submodule with non-permissioned address, expect revert
        bytes memory err = abi.encodeWithSignature("Module_PolicyNotPermitted(address)", other_);
        vm.expectRevert(err);
        vm.prank(other_);
        module.execOnSubmodule(
            subKeycode,
            abi.encodeWithSelector(MockSubmodule.mockFunction.selector)
        );

        // Execute function on submodule with permissioned address, expect success
        vm.prank(writer);
        module.execOnSubmodule(
            subKeycode,
            abi.encodeWithSelector(MockSubmodule.mockFunction.selector)
        );
    }

    function testRevert_execOnSubmodule_catchesRevert() public {
        // Install submodule so we can execute function on it
        _installSubmodule();

        SubKeycode subKeycode = submodule.SUBKEYCODE();

        // Try to execute function on submodule that reverts, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Module_SubmoduleExecutionReverted(bytes)",
            abi.encodeWithSignature("MockSubmodule_mockRevert()")
        );
        vm.expectRevert(err);
        vm.prank(writer);
        module.execOnSubmodule(
            subKeycode,
            abi.encodeWithSelector(MockSubmodule.mockRevert.selector)
        );
    }

    function test_execOnSubmodule_returnData() public {
        // Install submodule so we can execute function on it
        _installSubmodule();

        SubKeycode subKeycode = submodule.SUBKEYCODE();

        // Execute function on submodule, expect success
        vm.prank(writer);
        bytes memory returnData = module.execOnSubmodule(
            subKeycode,
            abi.encodeWithSelector(MockSubmodule.mockFunction.selector)
        );
        assertEq(returnData.length, 32);
        assertEq(abi.decode(returnData, (uint256)), 42);
    }

    /* ========== SUBMODULE TESTS ========== */

    function testRevert_constructor_parentKeycodeMustMatch() public {
        MockWrongModule wrongModule = new MockWrongModule(kernel);
        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);
        new MockSubmodule(wrongModule);
    }

    function test_constructor_parentStored() public {
        assertEq(address(submodule.parent()), address(module));
    }

    function test_PARENT() public {
        assertEq(fromKeycode(submodule.PARENT()), bytes5("MOCKY"));
    }

    function test_SUBKEYCODE() public {
        assertEq(fromSubKeycode(submodule.SUBKEYCODE()), bytes20("MOCKY.SUBMODUL3_NICE"));
    }

    function test_VERSION() public {
        (uint8 major, uint8 minor) = submodule.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function testRevert_INIT_onlyParent(address other_) public {
        vm.assume(other_ != address(module));

        // Try to call INIT with non-parent address, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(other_)
        );
        vm.expectRevert(err);
        vm.prank(other_);
        submodule.INIT();

        // Call INIT with parent address, expect success
        vm.prank(address(module));
        submodule.INIT();
    }

    function test_INIT() public {
        // Check that variable is not set before INIT
        assertFalse(submodule.theTruth());

        // Call INIT, expect success
        vm.prank(address(module));
        submodule.INIT();

        // Check that variable is set after INIT
        assertTrue(submodule.theTruth());
    }
}
