// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "src/Kernel.sol";

contract MockPolicy is Policy {
    MockModule public MOCKY;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("MOCKY");

        MOCKY = MockModule(getModuleAddress(dependencies[0]));

        (uint8 MOCKY_MAJOR, ) = MOCKY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1]);
        if (MOCKY_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](1);
        requests[0] = Permissions(MOCKY.KEYCODE(), MOCKY.permissionedCall.selector);
    }

    function callPublicFunction() external {
        MOCKY.publicCall();
    }

    function callPermissionedFunction() external {
        MOCKY.permissionedCall();
    }
}

contract MockModule is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    uint256 public publicState;
    uint256 public permissionedState;

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    function KEYCODE() public pure override returns (Keycode) {
        return Keycode.wrap("MOCKY");
    }

    function publicCall() public {
        publicState++;
    }

    function permissionedCall() public permissioned {
        permissionedState++;
    }
}

contract UpgradedMockModule is Module {
    MockModule internal _oldModule;
    uint256 public publicState;
    uint256 public permissionedState;

    constructor(Kernel kernel_, MockModule oldModule_) Module(kernel_) {
        _oldModule = oldModule_;
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1);
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function INIT() public override onlyKernel {
        permissionedState = _oldModule.permissionedState();
    }

    function publicCall() public {
        publicState++;
    }

    function permissionedCall() public permissioned {
        permissionedState++;
    }
}

contract UpgradedMockModuleNewMajor is Module {
    MockModule internal _oldModule;
    uint256 public publicState;
    uint256 public permissionedState;

    constructor(Kernel kernel_, MockModule oldModule_) Module(kernel_) {
        _oldModule = oldModule_;
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MOCKY");
    }

    function INIT() public override onlyKernel {
        permissionedState = _oldModule.permissionedState();
    }

    function publicCall() public {
        publicState++;
    }

    function permissionedCall() public permissioned {
        permissionedState++;
    }
}

contract MockPolicyUpgradedModule is Policy {
    MockModule public MOCKY;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("MOCKY");

        MOCKY = MockModule(getModuleAddress(dependencies[0]));

        (uint8 MOCKY_MAJOR, ) = MOCKY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([2]);
        if (MOCKY_MAJOR != 2) revert Policy_WrongModuleVersion(expected);
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](1);
        requests[0] = Permissions(MOCKY.KEYCODE(), MOCKY.permissionedCall.selector);
    }

    function callPublicFunction() external {
        MOCKY.publicCall();
    }

    function callPermissionedFunction() external {
        MOCKY.permissionedCall();
    }
}

contract InvalidMockModule is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    uint256 public publicState;
    uint256 public permissionedState;

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("badkc");
    }

    function INIT() public override onlyKernel {}

    function publicCall() public {
        publicState++;
    }

    function permissionedCall() public permissioned {
        permissionedState++;
    }
}
