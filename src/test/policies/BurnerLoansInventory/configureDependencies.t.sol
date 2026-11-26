// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

import {MockUnsupportedInventoryTrsry} from "./fixtures/MockUnsupportedInventoryTrsry.sol";

import {MockUnsupportedInventoryRoles} from "./fixtures/MockUnsupportedInventoryRoles.sol";

import {MockUnsupportedInventoryMintr} from "./fixtures/MockUnsupportedInventoryMintr.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {Actions, Kernel, Keycode, Module, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {BurnerLoansInventoryPrincipal} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryPrincipal.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Scenario-specific contracts and fixtures have no cross-file consumers.

contract BurnerLoansInventoryConfigureDependenciesTest is BurnerLoansInventoryTest {
    function test_givenInstalledDependencies_setsBurnAllowance() public view {
        assertEq(ohm.allowance(address(inventory), address(mintr)), type(uint256).max, "allowance");
    }

    //     burn allowance and initializes the replacement module's approval to remaining capacity
    // Scenarios: BLINV-DEPENDENCIES-P01.
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

    // Scenarios: BLINV-DEPENDENCIES-P03.
    function test_givenMintrUpgradeAfterDefault_reconcilesReplacementApproval() public {
        _enableAndSetCap(1_000e9);
        _supply(100e9);
        _draw(100e9);
        vm.prank(address(facility));
        inventory.settleDefault(40e9);
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

    // Scenarios: BLINV-DEPENDENCIES-P02.
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

    // Scenarios: BLINV-DEPENDENCIES-P02.
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

    function test_givenUnsupportedMintrVersion_reverts() public {
        _expectUnsupportedModuleReverts(new MockUnsupportedInventoryMintr(kernel));
    }

    function test_givenUnsupportedRolesVersion_reverts() public {
        _expectUnsupportedModuleReverts(new MockUnsupportedInventoryRoles(kernel));
    }

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

    // Scenarios: BLINV-DEPENDENCIES-P01.
    function test_givenLifecycle_whenAnyCallerConfigures(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _givenInitialLifecycle(active_, enabled_);
        bytes32 beforeState = _accountingState();
        vm.prank(caller_);
        Keycode[] memory dependencies = inventory.configureDependencies();
        assertEq(dependencies.length, 3, "Exact dependency count");
        assertEq(Keycode.unwrap(dependencies[0]), bytes5("MINTR"), "First module");
        assertEq(Keycode.unwrap(dependencies[1]), bytes5("ROLES"), "Second module");
        assertEq(Keycode.unwrap(dependencies[2]), bytes5("TRSRY"), "Third module");
        assertEq(address(inventory.ROLES()), address(roles), "Current roles pointer");
        assertEq(inventory.isEnabled(), enabled_, "No lifecycle change");
        assertEq(_accountingState(), beforeState, "Repeated configuration preserves accounting");
    }

    // Scenarios: BLINV-DEPENDENCIES-I01.
    function test_givenMissingModule_whenAnyCallerConfigures_reverts(
        address caller_,
        uint8 module_
    ) public {
        bytes5[3] memory keycodes = [bytes5("MINTR"), bytes5("ROLES"), bytes5("TRSRY")];
        Keycode missing = toKeycode(keycodes[uint256(module_) % 3]);
        bytes32 beforeState = _accountingState();
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", Keycode.unwrap(missing)),
            abi.encode(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, missing));
        vm.prank(caller_);
        inventory.configureDependencies();
        assertEq(_accountingState(), beforeState, "Missing dependency rolls back");
        assertEq(address(inventory.ROLES()), address(roles), "Old roles retained");
    }

    // Scenarios: BLINV-DEPENDENCIES-I01.
    function test_givenUnsupportedMajor_whenAnyCallerConfigures_reverts(
        address caller_,
        uint8 module_
    ) public {
        address[3] memory modules = [address(mintr), address(roles), address(trsry)];
        bytes32 beforeState = _accountingState();
        vm.mockCall(
            modules[uint256(module_) % 3],
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(2), uint8(0))
        );
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_InvalidModuleVersion.selector);
        vm.prank(caller_);
        inventory.configureDependencies();
        assertEq(address(inventory.ROLES()), address(roles), "Old roles pointer retained");
        assertEq(_accountingState(), beforeState, "Version failure leaves no partial approvals");
    }

    // Scenarios: BLINV-DEPENDENCIES-P02.
    function test_givenWrongOhm_whenAnyCallerConfigures_reverts(address caller_) public {
        bytes32 beforeState = _accountingState();
        vm.mockCall(address(mintr), abi.encodeWithSignature("ohm()"), abi.encode(outsider));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidOhm.selector,
                address(ohm),
                outsider
            )
        );
        vm.prank(caller_);
        inventory.configureDependencies();
        assertEq(_accountingState(), beforeState, "Wrong OHM leaves approvals unchanged");
    }

    // Scenarios: BLINV-DEPENDENCIES-P03.
    function test_givenReplacementApprovalRestorationFails_whenUpgraded_succeeds() public {
        _enableAndSetCap(1000);
        _supply(100);
        _draw(200);
        vm.prank(address(facility));
        inventory.settleDefault(50);
        OlympusMinter replacement = new OlympusMinter(kernel, address(ohm));
        bytes memory failure = abi.encodeWithSelector(ApprovalChangeFailed.selector);
        // Cap 1000 - remaining principal 150 - idle 0 = desired approval 850.
        vm.mockCallRevert(
            address(replacement),
            abi.encodeWithSelector(replacement.increaseMintApproval.selector),
            failure
        );
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.ApprovalRestorationFailed(850, failure);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        assertEq(
            ohm.allowance(address(inventory), address(mintr)),
            0,
            "Old burn allowance revoked"
        );
        assertEq(
            ohm.allowance(address(inventory), address(replacement)),
            type(uint256).max,
            "New burn allowance installed"
        );
        assertEq(
            replacement.mintApproval(address(inventory)),
            0,
            "Restoration deficit recorded conservatively"
        );
        assertEq(inventory.activePrincipalOhm(), 150, "Principal preserved");
        assertEq(inventory.providerClaimOhm(provider), 100, "Provider claim preserved");
    }

    error ApprovalChangeFailed();

    // Scenarios: BLINV-DEPENDENCIES-P03.
    function test_givenBurnAllowanceUpdateFails_whenUpgraded_reverts() public {
        _enableAndSetCap(DEFAULT_CAP);
        OlympusMinter replacement = new OlympusMinter(kernel, address(ohm));
        bytes32 beforeState = _accountingState();
        bytes memory failure = abi.encodeWithSelector(ApprovalChangeFailed.selector);
        vm.mockCallRevert(
            address(ohm),
            abi.encodeCall(ohm.approve, (address(replacement), type(uint256).max)),
            failure
        );
        vm.expectRevert(failure);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        assertEq(
            address(kernel.getModuleForKeycode(toKeycode("MINTR"))),
            address(mintr),
            "Module upgrade rolled back"
        );
        assertEq(
            ohm.allowance(address(inventory), address(replacement)),
            0,
            "No partial new allowance"
        );
        assertEq(
            _accountingState(),
            beforeState,
            "Old allowance revocation and pointers roll back"
        );
    }

    // Scenarios: BLINV-DEPENDENCIES-I01.
    function test_whenDependencyBoundarySeeds() public {
        for (uint8 i; i < 3; ++i) {
            test_givenMissingModule_whenAnyCallerConfigures_reverts(outsider, i);
            vm.clearMockedCalls();
            test_givenUnsupportedMajor_whenAnyCallerConfigures_reverts(outsider, i);
            vm.clearMockedCalls();
        }
    }

    // Scenarios: BLINV-DEPENDENCIES-P01.
    function test_givenNeverConfigured_whenAnyCallerConfigures(address caller_) public {
        inventory = _newInventory();
        assertEq(address(inventory.ROLES()), address(0), "No initial cached roles");
        vm.prank(caller_);
        Keycode[] memory dependencies = inventory.configureDependencies();
        assertEq(dependencies.length, 3, "Initial dependency count");
        assertEq(address(inventory.ROLES()), address(roles), "Initial roles bound");
        assertEq(
            ohm.allowance(address(inventory), address(mintr)),
            type(uint256).max,
            "Initial burn allowance"
        );
        assertFalse(inventory.isEnabled(), "Configuration does not enable");
    }

    // Scenarios: BLINV-DEPENDENCIES-P01, BLINV-DEPENDENCIES-P03.
    function test_givenReplacementModule_whenAnyCallerConfigures(address caller_) public {
        _enableAndSetCap(1000);
        _supply(100);
        _draw(200);
        vm.prank(address(facility));
        inventory.settleDefault(50);
        OlympusMinter replacement = new OlympusMinter(kernel, address(ohm));
        // Model registry resolution at the reconfiguration boundary; the real Kernel upgrade
        // tests above separately prove the atomic callback and permission wiring.
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("MINTR")),
            abi.encode(address(replacement))
        );
        vm.prank(caller_);
        inventory.configureDependencies();
        assertEq(
            ohm.allowance(address(inventory), address(mintr)),
            0,
            "Old burn allowance revoked"
        );
        assertEq(
            ohm.allowance(address(inventory), address(replacement)),
            type(uint256).max,
            "New burn allowance"
        );
        assertEq(replacement.mintApproval(address(inventory)), 850, "Cap less principal and idle");
        assertEq(inventory.activePrincipalOhm(), 150, "Principal preserved");
        assertEq(inventory.providerClaimOhm(provider), 100, "Provider claim preserved");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
