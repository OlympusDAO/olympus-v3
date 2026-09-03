// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {Actions, Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BurnerLoansInventory} from "src/policies/BurnerLoansInventory.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

import {BurnerLoansInventoryPrincipal, BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryConfigureDependenciesTest is BurnerLoansInventoryTest {
    // configureDependencies
    // [X] given installed dependencies, it grants the current MINTR maximum burn allowance
    function test_givenInstalledDependencies_setsBurnAllowance() public view {
        assertEq(ohm.allowance(address(inventory), address(mintr)), type(uint256).max, "allowance");
    }

    // configureDependencies
    // [X] given an enabled Burner Loans Inventory with active principal, a MINTR upgrade moves the
    //     burn allowance and initializes the replacement module's approval to remaining capacity
    function test_givenMintrUpgrade_reconcilesReplacementApproval() public {
        _enableAndSetCap(DEFAULT_CAP);
        _draw(100e9);
        OlympusMinter replacement = new OlympusMinter(kernel, address(ohm));

        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));

        assertEq(ohm.allowance(address(inventory), address(mintr)), 0, "old burn allowance");
        assertEq(
            ohm.allowance(address(inventory), address(replacement)),
            type(uint256).max,
            "replacement burn allowance"
        );
        assertEq(
            replacement.mintApproval(address(inventory)),
            DEFAULT_CAP - 100e9,
            "replacement mint approval"
        );
    }

    // configureDependencies
    // [X] given a MINTR replacement after a default, it reconciles the replacement approval
    function test_givenMintrUpgradeAfterDefault_reconcilesReplacementApproval() public {
        _enableAndSetCap(1_000e9);
        _supply(100e9);
        _draw(100e9);
        vm.prank(address(facility));
        inventory.recordDefault(40e9);
        OlympusMinter replacement = new OlympusMinter(kernel, address(ohm));

        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));

        assertEq(ohm.allowance(address(inventory), address(mintr)), 0, "old burn allowance");
        assertEq(
            ohm.allowance(address(inventory), address(replacement)),
            type(uint256).max,
            "replacement burn allowance"
        );
        assertEq(
            replacement.mintApproval(address(inventory)),
            inventory.desiredMintApproval(),
            "replacement mint approval"
        );
    }

    // configureDependencies
    // [X] given an initial MINTR for a different token, activating Burner Loans Inventory reverts
    function test_givenInitialMintrWithDifferentOhm_reverts() public {
        Kernel initialKernel = new Kernel();
        MockOhm expectedOhm = new MockOhm("Expected OHM", "EOHM", 9);
        MockOhm differentOhm = new MockOhm("Different OHM", "DOHM", 9);
        OlympusMinter differentMintr = new OlympusMinter(initialKernel, address(differentOhm));
        OlympusRoles initialRoles = new OlympusRoles(initialKernel);
        OlympusTreasury initialTrsry = new OlympusTreasury(initialKernel);
        BurnerLoansInventory initialInventory = new BurnerLoansInventory(
            initialKernel,
            IERC20(address(expectedOhm)),
            address(new BurnerLoansInventoryPrincipal(initialKernel, address(0)))
        );

        initialKernel.executeAction(Actions.InstallModule, address(differentMintr));
        initialKernel.executeAction(Actions.InstallModule, address(initialRoles));
        initialKernel.executeAction(Actions.InstallModule, address(initialTrsry));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidOhm.selector,
                address(expectedOhm),
                address(differentOhm)
            )
        );
        initialKernel.executeAction(Actions.ActivatePolicy, address(initialInventory));
    }

    // configureDependencies
    // [X] given a replacement MINTR for a different token, upgrading reverts atomically
    function test_givenReplacementMintrWithDifferentOhm_revertsWithoutStateChange() public {
        _enableAndSetCap(DEFAULT_CAP);
        _draw(100e9);
        MockOhm differentOhm = new MockOhm("Different OHM", "DOHM", 9);
        OlympusMinter replacement = new OlympusMinter(kernel, address(differentOhm));

        uint256 originalAllowance = ohm.allowance(address(inventory), address(mintr));
        uint256 originalApproval = mintr.mintApproval(address(inventory));
        uint128 originalPrincipal = inventory.activePrincipalOhm();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidOhm.selector,
                address(ohm),
                address(differentOhm)
            )
        );
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));

        assertEq(
            ohm.allowance(address(inventory), address(mintr)),
            originalAllowance,
            "old burn allowance"
        );
        assertEq(
            ohm.allowance(address(inventory), address(replacement)),
            0,
            "replacement burn allowance"
        );
        assertEq(mintr.mintApproval(address(inventory)), originalApproval, "old mint approval");
        assertEq(inventory.activePrincipalOhm(), originalPrincipal, "active principal");
    }

    // configureDependencies
    // [X] given an unsupported MINTR major version, dependency reconfiguration reverts
    function test_givenUnsupportedMintrVersion_reverts() public {
        _expectUnsupportedModuleReverts(new MockUnsupportedInventoryMintr(kernel));
    }

    // configureDependencies
    // [X] given an unsupported ROLES major version, dependency reconfiguration reverts
    function test_givenUnsupportedRolesVersion_reverts() public {
        _expectUnsupportedModuleReverts(new MockUnsupportedInventoryRoles(kernel));
    }

    // configureDependencies
    // [X] given an unsupported TRSRY major version, dependency reconfiguration reverts
    function test_givenUnsupportedTrsryVersion_reverts() public {
        _expectUnsupportedModuleReverts(new MockUnsupportedInventoryTrsry(kernel));
    }

    function _expectUnsupportedModuleReverts(Module module_) internal {
        if (Keycode.unwrap(module_.KEYCODE()) == Keycode.unwrap(toKeycode("ROLES"))) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(rolesAdmin));
        }
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_InvalidModuleVersion.selector);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(module_));
    }
}

contract MockUnsupportedInventoryMintr is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MINTR");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }
}

contract MockUnsupportedInventoryRoles is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("ROLES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }
}

contract MockUnsupportedInventoryTrsry is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (2, 0);
    }
}
