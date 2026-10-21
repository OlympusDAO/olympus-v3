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
    // Scenarios: RD-DEPS-P01
    function test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys(
        address caller_,
        bool disable_,
        bool deactivate_
    ) public {
        _setDistributorLifecycle(disable_, deactivate_);

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
    }

    // Scenarios: RD-DEPS-P02
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

    // Scenarios: RD-DEPS-I01
    function test_givenMissingRoles_whenDependenciesConfigured_reverts() public {
        Kernel emptyKernel = new Kernel();
        RevenueDistributorHarness localDistributor = new RevenueDistributorHarness(emptyKernel);

        _assertConfigureDependenciesReverts(
            localDistributor,
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
    }

    // Scenarios: RD-DEPS-I02
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

    // Scenarios: RD-DEPS-I03, RD-DEPS-I04
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
}
