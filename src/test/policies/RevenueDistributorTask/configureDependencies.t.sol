// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {MockConfigUnsupportedRoles} from "src/test/policies/BurnerLoansConfig/fixtures/MockConfigUnsupportedRoles.sol";
import {MockTaskCompatibleRoles} from "./fixtures/MockTaskCompatibleRoles.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskConfigureDependenciesTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-DEPS-P01.
    function test_whenCalledInAnyLifecycleState_refreshesRoles(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        if (!enabled_) _disableTask("");
        if (!active_) _deactivateTask();
        uint32 executionLimit = task.executionGasLimit();
        uint32 attemptThreshold = task.minimumGasToAttempt();
        uint32 reserve = task.gasReserve();

        vm.prank(caller_);
        Keycode[] memory dependencies = task.configureDependencies();

        assertEq(dependencies.length, 1, "dependency count");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES keycode"
        );
        assertEq(address(task.ROLES()), address(roles), "cached ROLES address");
        assertEq(task.executionGasLimit(), executionLimit, "execution limit unchanged");
        assertEq(task.minimumGasToAttempt(), attemptThreshold, "attempt threshold unchanged");
        assertEq(task.gasReserve(), reserve, "reserve unchanged");
    }

    // Scenarios: RDTASK-DEPS-P02.
    function test_whenRolesUpgraded_refreshesCompatibleReplacement(address caller_) public {
        MockTaskCompatibleRoles replacement = new MockTaskCompatibleRoles(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));

        vm.prank(caller_);
        Keycode[] memory dependencies = task.configureDependencies();

        assertEq(dependencies.length, 1, "dependency count");
        assertEq(address(task.ROLES()), address(replacement), "replacement ROLES cached");
    }

    // Scenarios: RDTASK-DEPS-I01.
    function test_whenRolesMissing_reverts(address caller_) public {
        (RevenueDistributorTask localTask, ) = _deployWithKernelWithoutRoles();
        uint32 executionLimit = localTask.executionGasLimit();

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        // The return value is unavailable because the call is expected to revert.
        // forge-lint: disable-next-line(unused-return)
        localTask.configureDependencies();

        assertEq(address(localTask.ROLES()), address(0), "cached dependency rolls back");
        assertEq(localTask.executionGasLimit(), executionLimit, "configuration unchanged");
    }

    // Scenarios: RDTASK-DEPS-I02.
    function test_whenRolesMajorUnsupported_reverts(address caller_) public {
        (RevenueDistributorTask localTask, Kernel localKernel) = _deployWithKernelWithoutRoles();
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
        // The return value is unavailable because the call is expected to revert.
        // forge-lint: disable-next-line(unused-return)
        localTask.configureDependencies();

        assertEq(address(localTask.ROLES()), address(0), "cached dependency rolls back");
    }

    function _deployWithKernelWithoutRoles()
        internal
        returns (RevenueDistributorTask localTask_, Kernel localKernel_)
    {
        localKernel_ = new Kernel();
        RevenueDistributor localDistributor = new RevenueDistributor(localKernel_);
        localTask_ = new RevenueDistributorTask(localKernel_, address(localDistributor), 1);
    }
}
