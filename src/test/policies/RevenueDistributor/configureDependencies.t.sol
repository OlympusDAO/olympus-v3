// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RevenueDistributorHarness} from "./fixtures/RevenueDistributorHarness.sol";
import {MockRevenueDistributorRolesV2} from "./fixtures/MockRevenueDistributorModules.sol";
import {MockRevenueDistributorTreasuryV2} from "./fixtures/MockRevenueDistributorTreasuryV2.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorConfigureDependenciesTest is RevenueDistributorTest {
    // Scenarios: RD-DEPS-P01, RD-DEPS-P03, RD-DEPS-P04, RD-DEPS-P05.
    function test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(distributor), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = distributor.lastTransitionAt();
        uint32 beforeGrace = distributor.gracePeriod();
        vm.recordLogs();
        vm.prank(caller_);
        Keycode[] memory dependencies = distributor.configureDependencies();

        assertEq(dependencies.length, 2, "two dependencies are returned");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES first"
        );
        assertEq(
            Keycode.unwrap(dependencies[1]),
            Keycode.unwrap(toKeycode("TRSRY")),
            "TRSRY second"
        );
        assertEq(address(distributor.ROLES()), address(roles), "ROLES cache matches Kernel");
        assertEq(distributor.treasury(), address(treasury), "Treasury cache matches Kernel");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Module refresh preserves raw accounting and custody"
        );
        assertEq(distributor.isEnabled(), enabled_, "Module refresh preserves local enablement");
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Module refresh preserves transition timestamp"
        );
        assertEq(distributor.gracePeriod(), beforeGrace, "Module refresh preserves grace");
        assertEq(vm.getRecordedLogs().length, 0, "Module refresh emits no events");
    }

    function test_whenCompatibleModuleReplaced_refreshesSelectedDependency(
        bool replaceRoles_
    ) public {
        address rolesBefore = address(distributor.ROLES());
        address treasuryBefore = distributor.treasury();

        vm.startPrank(admin);
        if (replaceRoles_) {
            OlympusRoles replacement = new OlympusRoles(kernel);
            kernel.executeAction(Actions.UpgradeModule, address(replacement));
            assertEq(address(distributor.ROLES()), address(replacement), "ROLES cache refreshes");
            assertEq(distributor.treasury(), treasuryBefore, "Treasury cache remains unchanged");
        } else {
            OlympusTreasury replacement = new OlympusTreasury(kernel);
            kernel.executeAction(Actions.UpgradeModule, address(replacement));
            assertEq(distributor.treasury(), address(replacement), "Treasury cache refreshes");
            assertEq(address(distributor.ROLES()), rolesBefore, "ROLES cache remains unchanged");
        }
        vm.stopPrank();
    }

    function test_givenMissingRoles_whenDependenciesConfigured_reverts() public {
        Kernel emptyKernel = new Kernel();
        RevenueDistributorHarness localDistributor = new RevenueDistributorHarness(emptyKernel);

        _assertConfigureDependenciesReverts(
            localDistributor,
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
    }

    function test_givenMissingTreasury_whenDependenciesConfigured_reverts() public {
        Kernel localKernel = new Kernel();
        OlympusRoles localRoles = new OlympusRoles(localKernel);
        localKernel.executeAction(Actions.InstallModule, address(localRoles));
        RevenueDistributorHarness localDistributor = new RevenueDistributorHarness(localKernel);

        _assertConfigureDependenciesReverts(
            localDistributor,
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("TRSRY"))
        );
    }

    function test_givenWrongModuleMajor_whenDependenciesConfigured_reverts(
        bool wrongRoles_
    ) public {
        Kernel localKernel = new Kernel();
        OlympusRoles localRoles = new OlympusRoles(localKernel);
        OlympusTreasury localTreasury = new OlympusTreasury(localKernel);
        address rolesModule = wrongRoles_
            ? address(new MockRevenueDistributorRolesV2(localKernel))
            : address(localRoles);
        address treasuryModule = wrongRoles_
            ? address(localTreasury)
            : address(new MockRevenueDistributorTreasuryV2(localKernel));
        localKernel.executeAction(Actions.InstallModule, rolesModule);
        localKernel.executeAction(Actions.InstallModule, treasuryModule);
        RevenueDistributorHarness localDistributor = new RevenueDistributorHarness(localKernel);

        _assertConfigureDependenciesReverts(
            localDistributor,
            abi.encodeWithSelector(Policy.Policy_WrongModuleVersion.selector, abi.encode([1]))
        );
    }

    function _assertConfigureDependenciesReverts(
        RevenueDistributorHarness distributor_,
        bytes memory expectedRevert_
    ) internal {
        try distributor_.configureDependencies() returns (Keycode[] memory) {
            fail("configureDependencies should revert");
        } catch (bytes memory revertData) {
            assertEq(revertData, expectedRevert_, "configureDependencies revert data");
        }
    }

    function _setDistributorLifecycle(bool disable_, bool deactivate_) internal {
        if (disable_) {
            vm.prank(admin);
            distributor.disable("");
        }
        if (deactivate_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        }
    }

    // Scenarios: RD-DEPS-P01, RD-DEPS-P03, RD-DEPS-P04, RD-DEPS-P05.
    function test_whenAnyCallerConfiguresDependencies_returnsOrderedKeysLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys(address(0), false, false);
    }

    // Scenarios: RD-DEPS-P02, RD-DEPS-P06, RD-DEPS-P07, RD-DEPS-P08.
    function test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(distributor), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        address otherBefore = distributor.treasury();
        OlympusRoles replacement = new OlympusRoles(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.recordLogs();
        vm.prank(caller_);
        Keycode[] memory dependencies = distributor.configureDependencies();
        assertEq(dependencies.length, 2, "Refresh returns both dependencies");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES first"
        );
        assertEq(
            Keycode.unwrap(dependencies[1]),
            Keycode.unwrap(toKeycode("TRSRY")),
            "TRSRY second"
        );
        assertEq(
            address(distributor.ROLES()),
            address(replacement),
            "Replaced dependency cache changes"
        );
        assertEq(distributor.treasury(), otherBefore, "Other module cache remains unchanged");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Module replacement preserves authoritative obligations and custody"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Permissionless refresh emits no events");
    }

    // Scenarios: RD-DEPS-P02, RD-DEPS-P06, RD-DEPS-P07, RD-DEPS-P08.
    function test_givenCompatibleRolesReplacement_whenAnyCallerRefreshesLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes(address(0), false, false);
    }

    // Scenarios: RD-DEPS-P02, RD-DEPS-P06, RD-DEPS-P07, RD-DEPS-P08.
    function test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(distributor), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        address otherBefore = address(distributor.ROLES());
        address treasuryBefore = distributor.treasury();
        OlympusTreasury replacement = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.recordLogs();
        vm.prank(caller_);
        Keycode[] memory dependencies = distributor.configureDependencies();
        assertEq(dependencies.length, 2, "Refresh returns both dependencies");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES first"
        );
        assertEq(
            Keycode.unwrap(dependencies[1]),
            Keycode.unwrap(toKeycode("TRSRY")),
            "TRSRY second"
        );
        assertEq(distributor.treasury(), address(replacement), "Replaced dependency cache changes");
        assertEq(address(distributor.ROLES()), otherBefore, "Other module cache remains unchanged");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Module replacement preserves authoritative obligations and custody"
        );
        assertEq(
            distributor.pendingPayout(address(token), address(replacement)),
            8,
            "Treasury and fallback yield obligations follow new Treasury"
        );
        assertEq(
            distributor.pendingPayout(address(token), treasuryBefore),
            0,
            "Old Treasury loses only its role entitlement"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Permissionless refresh emits no events");
    }

    // Scenarios: RD-DEPS-P02, RD-DEPS-P06, RD-DEPS-P07, RD-DEPS-P08.
    function test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshesLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes(address(0), false, false);
    }

    // Scenarios: RD-DEPS-I01.
    function test_givenActivePolicy_whenRolesMissing_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(distributor.ROLES());
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("ROLES")),
            abi.encode(address(0))
        );
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        // The expected revert has no return value.
        // forge-lint: disable-next-line(unused-return)
        distributor.configureDependencies();
        assertEq(address(distributor.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(distributor.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(distributor.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
    }

    // Scenarios: RD-DEPS-I03.
    function test_givenActivePolicy_whenRolesUnsupportedMajor_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(distributor.ROLES());
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.mockCall(
            address(roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(2), uint8(0))
        );
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([uint8(1)])
            )
        );
        vm.prank(caller_);
        // The expected revert has no return value.
        // forge-lint: disable-next-line(unused-return)
        distributor.configureDependencies();
        assertEq(address(distributor.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(distributor.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(distributor.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
    }

    // Scenarios: RD-DEPS-I02.
    function test_givenActivePolicy_whenTreasuryMissing_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(distributor.ROLES());
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("TRSRY")),
            abi.encode(address(0))
        );
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("TRSRY"))
        );
        vm.prank(caller_);
        // The expected revert has no return value.
        // forge-lint: disable-next-line(unused-return)
        distributor.configureDependencies();
        assertEq(address(distributor.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(distributor.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(distributor.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
    }

    // Scenarios: RD-DEPS-I04.
    function test_givenActivePolicy_whenTreasuryUnsupportedMajor_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(distributor.ROLES());
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.mockCall(
            address(treasury),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(2), uint8(0))
        );
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([uint8(1)])
            )
        );
        vm.prank(caller_);
        // The expected revert has no return value.
        // forge-lint: disable-next-line(unused-return)
        distributor.configureDependencies();
        assertEq(address(distributor.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(distributor.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(distributor.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
    }
}
