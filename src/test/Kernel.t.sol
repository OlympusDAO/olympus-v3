// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import "./mocks/KernelTestMocks.sol";

import "src/Kernel.sol";

contract KernelTest is Test {
    Kernel internal kernel;
    MockPolicy internal policy;
    MockModule internal MOCKY;

    address public deployer;
    address public multisig;
    address public user;
    UserFactory public userFactory;

    bytes public err;
    MockPolicy internal policyTest;

    function setUp() public {
        userFactory = new UserFactory();
        address[] memory users = userFactory.create(3);
        deployer = users[0];
        multisig = users[1];
        user = users[2];

        vm.startPrank(deployer);
        kernel = new Kernel();
        MOCKY = new MockModule(kernel);
        policy = new MockPolicy(kernel);

        vm.stopPrank();
    }

    function testCorrectness_InitializeKernel() public {
        Keycode keycode = Keycode.wrap(0);

        assertEq(kernel.executor(), deployer);
        assertEq(kernel.modulePermissions(keycode, policy, bytes4(0)), false);
        assertEq(address(kernel.getModuleForKeycode(keycode)), address(0));
        assertEq(Keycode.unwrap(kernel.getKeycodeForModule(MOCKY)), bytes5(0));

        // Ensure actions cannot be performed by unauthorized addresses
        err = abi.encodeWithSignature("Kernel_OnlyExecutor(address)", address(this));
        vm.expectRevert(err);
        kernel.executeAction(Actions.InstallModule, address(MOCKY));
    }

    function testCorrectness_EnsureContract() public {
        ensureContract(address(kernel));

        err = abi.encodeWithSignature("TargetNotAContract(address)", address(deployer));
        vm.expectRevert(err);
        ensureContract(deployer);

        err = abi.encodeWithSignature("TargetNotAContract(address)", address(0));
        vm.expectRevert(err);
        ensureContract(address(0));
    }

    function testCorrectness_EnsureValidKeycode() public {
        ensureValidKeycode(Keycode.wrap("VALID"));

        err = abi.encodeWithSignature("InvalidKeycode(bytes5)", Keycode.wrap("inval"));
        vm.expectRevert(err);
        ensureValidKeycode(Keycode.wrap("inval"));

        err = abi.encodeWithSignature("InvalidKeycode(bytes5)", Keycode.wrap(""));
        vm.expectRevert(err);
        ensureValidKeycode(Keycode.wrap(bytes5("")));
    }

    function testCorrectness_InitializeModule() public {
        assertEq(Keycode.unwrap(MOCKY.KEYCODE()), "MOCKY");
        assertEq(MOCKY.publicState(), 0);
        assertEq(MOCKY.permissionedState(), 0);
    }

    function testCorrectness_InstallModule() public {
        vm.startPrank(deployer);

        // Ensure module is installed properly
        kernel.executeAction(Actions.InstallModule, address(MOCKY));
        assertEq(address(kernel.getModuleForKeycode(Keycode.wrap("MOCKY"))), address(MOCKY));
        assertEq(Keycode.unwrap(kernel.getKeycodeForModule(MOCKY)), "MOCKY");

        // Try installing an EOA as a module
        err = abi.encodeWithSignature("TargetNotAContract(address)", deployer);
        vm.expectRevert(err);
        kernel.executeAction(Actions.InstallModule, deployer);

        // Try installing module with a bad keycode
        Module invalidModule = new InvalidMockModule(kernel);
        err = abi.encodeWithSignature("InvalidKeycode(bytes5)", Keycode.wrap("badkc"));
        vm.expectRevert(err);
        kernel.executeAction(Actions.InstallModule, address(invalidModule));

        // Try installing MOCKY again
        err = abi.encodeWithSignature(
            "Kernel_ModuleAlreadyInstalled(bytes5)",
            Keycode.wrap("MOCKY")
        );
        vm.expectRevert(err);
        kernel.executeAction(Actions.InstallModule, address(MOCKY));

        vm.stopPrank();
    }

    function testCorrectness_ActivatePolicy() public {
        Keycode testKeycode = Keycode.wrap("MOCKY");

        // Try to activate policy without module installed
        vm.prank(deployer);
        err = abi.encodeWithSignature("Policy_ModuleDoesNotExist(bytes5)", testKeycode);
        vm.expectRevert(err);
        kernel.executeAction(Actions.ActivatePolicy, address(policy));

        _initModuleAndPolicy();

        // Ensure policy was activated correctly
        assertEq(
            kernel.modulePermissions(testKeycode, policy, MOCKY.permissionedCall.selector),
            true
        );
        assertEq(address(kernel.activePolicies(0)), address(policy));
        assertTrue(policy.isActive());

        // Ensure policy is a dependent
        uint256 depIndex = kernel.getDependentIndex(testKeycode, policy);
        Policy[] memory dependencies = new Policy[](1);
        dependencies[0] = policy;
        assertEq(address(kernel.moduleDependents(testKeycode, depIndex)), address(dependencies[0]));
    }

    function testRevert_ActivatePolicyTwice() public {
        _initModuleAndPolicy();

        vm.prank(deployer);
        err = abi.encodeWithSelector(
            Kernel.Kernel_PolicyAlreadyActivated.selector,
            address(policy)
        );
        vm.expectRevert(err);
        kernel.executeAction(Actions.ActivatePolicy, address(policy));
    }

    function testCorrectness_PolicyPermissions() public {
        _initModuleAndPolicy();
        Permissions[] memory permissions = policy.requestPermissions();

        assertEq(Keycode.unwrap(permissions[0].keycode), "MOCKY");
        assertEq(permissions[0].funcSelector, MOCKY.permissionedCall.selector);
    }

    function testCorrectness_CallPublicPolicyFunction() public {
        _initModuleAndPolicy();

        vm.prank(deployer);
        policy.callPublicFunction();

        assertEq(MOCKY.publicState(), 1);
    }

    function testCorrectness_DeactivatePolicy() public {
        vm.startPrank(deployer);

        kernel.executeAction(Actions.InstallModule, address(MOCKY));
        kernel.executeAction(Actions.ActivatePolicy, address(policy));

        err = abi.encodeWithSignature("Kernel_PolicyAlreadyActivated(address)", address(policy));
        vm.expectRevert(err);
        kernel.executeAction(Actions.ActivatePolicy, address(policy));

        kernel.executeAction(Actions.DeactivatePolicy, address(policy));
        vm.stopPrank();

        assertEq(
            kernel.modulePermissions(
                Keycode.wrap("MOCKY"),
                policy,
                MOCKY.permissionedCall.selector
            ),
            false
        );
        vm.expectRevert();
        assertEq(address(kernel.activePolicies(0)), address(0));
    }

    function testCorrectness_UpgradeModule() public {
        UpgradedMockModule upgradedModule = new UpgradedMockModule(kernel, MOCKY);

        vm.startPrank(deployer);

        err = abi.encodeWithSignature("Kernel_InvalidModuleUpgrade(bytes5)", Keycode.wrap("MOCKY"));
        vm.expectRevert(err);
        kernel.executeAction(Actions.UpgradeModule, address(upgradedModule));

        kernel.executeAction(Actions.InstallModule, address(MOCKY));

        err = abi.encodeWithSignature("Kernel_InvalidModuleUpgrade(bytes5)", Keycode.wrap("MOCKY"));
        vm.expectRevert(err);
        kernel.executeAction(Actions.UpgradeModule, address(MOCKY));

        kernel.executeAction(Actions.ActivatePolicy, address(policy));

        vm.stopPrank();

        vm.prank(multisig);
        policy.callPermissionedFunction();

        assertEq(MOCKY.permissionedState(), 1);

        // Upgrade MOCKY
        vm.prank(deployer);
        kernel.executeAction(Actions.UpgradeModule, address(upgradedModule));

        // check state is reset
        assertEq(upgradedModule.permissionedState(), 1);

        vm.prank(multisig);
        policy.callPermissionedFunction();

        assertEq(upgradedModule.permissionedState(), 2);
    }

    function testCorrectness_ChangeExecutor() public {
        vm.startPrank(deployer);
        kernel.executeAction(Actions.ChangeExecutor, address(multisig));

        err = abi.encodeWithSignature("Kernel_OnlyExecutor(address)", deployer);
        vm.expectRevert(err);
        kernel.executeAction(Actions.ChangeExecutor, address(deployer));

        vm.stopPrank();

        vm.prank(multisig);
        kernel.executeAction(Actions.ChangeExecutor, address(deployer));

        vm.startPrank(deployer);
        kernel.executeAction(Actions.ChangeExecutor, address(multisig));
    }

    function testCorrectness_MigrateKernel() public {
        _initModuleAndPolicy();

        assertEq(address(kernel.getModuleForKeycode(kernel.allKeycodes(0))), address(MOCKY));
        assertEq(address(kernel.activePolicies(0)), address(policy));

        vm.startPrank(deployer);

        // Create new kernel and migrate to it
        Kernel newKernel = new Kernel();

        kernel.executeAction(Actions.MigrateKernel, address(newKernel));

        assertEq(address(MOCKY.kernel()), address(newKernel));
        assertEq(address(policy.kernel()), address(newKernel));

        // Install module and approve policy
        newKernel.executeAction(Actions.InstallModule, address(MOCKY));
        newKernel.executeAction(Actions.ActivatePolicy, address(policy));

        assertEq(address(newKernel.getModuleForKeycode(newKernel.allKeycodes(0))), address(MOCKY));
        assertEq(address(newKernel.activePolicies(0)), address(policy));
    }

    function _initModuleAndPolicy() internal {
        vm.startPrank(deployer);
        kernel.executeAction(Actions.InstallModule, address(MOCKY));
        kernel.executeAction(Actions.ActivatePolicy, address(policy));
        vm.stopPrank();
    }
}
