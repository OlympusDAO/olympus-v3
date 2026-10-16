// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// The test-local compatible ROLES mock is clearer beside its sole consumer. Calls whose return
// values are omitted assert cache updates or exact reverts instead.
// forge-lint: disable-start(multi-contract-file,unused-return)

import {Actions, Kernel, Keycode, Module, Policy, toKeycode} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {MockConfigUnsupportedRoles} from "src/test/policies/BurnerLoansConfig/fixtures/MockConfigUnsupportedRoles.sol";
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockConfigureDependenciesTest is
    RevenueDistributorConfigTimelockTest
{
    // Scenarios: RDCT-DEPS-P01
    function testFuzz_whenCalledInAnyLifecycleState_refreshesRoles(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        if (!enabled_) _disableTimelock();
        if (!active_) _deactivateTimelock();

        vm.prank(caller_);
        Keycode[] memory dependencies = configTimelock.configureDependencies();

        assertEq(dependencies.length, 1, "dependency count");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES keycode"
        );
        assertEq(address(configTimelock.ROLES()), address(roles), "cached ROLES");
    }

    // Scenarios: RDCT-DEPS-P02
    function testFuzz_whenRolesUpgraded_refreshesCompatibleReplacement(address caller_) public {
        MockCompatibleRoles replacement = new MockCompatibleRoles(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));

        vm.prank(caller_);
        configTimelock.configureDependencies();

        assertEq(address(configTimelock.ROLES()), address(replacement), "replacement ROLES cached");
    }

    // Scenarios: RDCT-DEPS-I01
    function testFuzz_whenRolesMissing_reverts(address caller_) public {
        Kernel localKernel = new Kernel();
        RevenueDistributor localDistributor = new RevenueDistributor(localKernel);
        RevenueDistributorConfigTimelock localTimelock = new RevenueDistributorConfigTimelock(
            localKernel,
            localDistributor
        );

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        localTimelock.configureDependencies();
    }

    // Scenarios: RDCT-DEPS-I02
    function testFuzz_whenRolesMajorUnsupported_reverts(address caller_) public {
        Kernel localKernel = new Kernel();
        RevenueDistributor localDistributor = new RevenueDistributor(localKernel);
        RevenueDistributorConfigTimelock localTimelock = new RevenueDistributorConfigTimelock(
            localKernel,
            localDistributor
        );
        localKernel.executeAction(
            Actions.InstallModule,
            address(new MockConfigUnsupportedRoles(localKernel))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([uint8(1)])
            )
        );
        vm.prank(caller_);
        localTimelock.configureDependencies();
    }
}

contract MockCompatibleRoles is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("ROLES");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1);
    }
}

// forge-lint: disable-end(multi-contract-file,unused-return)
