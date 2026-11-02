// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {MockConfigUnsupportedRoles} from "src/test/policies/BurnerLoansConfig/fixtures/MockConfigUnsupportedRoles.sol";
import {MockTaskCompatibleRoles} from "./fixtures/MockTaskCompatibleRoles.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskConfigureDependenciesTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-DEPS-P01, RDTASK-DEPS-P03, RDTASK-DEPS-P04, RDTASK-DEPS-P05.
    function test_whenCalledInAnyLifecycleState_refreshesRoles(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(task), active_, enabled_);
        uint32 executionLimit = task.executionGasLimit();
        uint32 attemptThreshold = task.minimumGasToAttempt();
        uint32 reserve = task.gasReserve();
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = task.lastTransitionAt();
        uint32 beforeGrace = task.gracePeriod();
        vm.recordLogs();
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
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Module refresh preserves raw accounting and custody"
        );
        assertEq(task.isEnabled(), enabled_, "Module refresh preserves local enablement");
        assertEq(
            task.lastTransitionAt(),
            beforeAt,
            "Module refresh preserves transition timestamp"
        );
        assertEq(task.gracePeriod(), beforeGrace, "Module refresh preserves grace");
        assertEq(vm.getRecordedLogs().length, 0, "Module refresh emits no events");
    }

    // Scenarios: RDTASK-DEPS-P02, RDTASK-DEPS-P06, RDTASK-DEPS-P07, RDTASK-DEPS-P08.
    function test_whenRolesUpgraded_refreshesCompatibleReplacement(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(task), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = task.lastTransitionAt();
        MockTaskCompatibleRoles replacement = new MockTaskCompatibleRoles(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.recordLogs();
        vm.prank(caller_);
        Keycode[] memory dependencies = task.configureDependencies();
        assertEq(dependencies.length, 1, "One dependency is returned");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES keycode"
        );
        assertEq(address(task.ROLES()), address(replacement), "Compatible minor version is cached");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Role module replacement preserves accounting and custody"
        );
        assertEq(task.isEnabled(), enabled_, "Role module replacement preserves enablement");
        assertEq(task.lastTransitionAt(), beforeAt, "Role module replacement preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Permissionless refresh emits no events");
    }

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

    // Scenarios: RDTASK-DEPS-P01, RDTASK-DEPS-P03, RDTASK-DEPS-P04, RDTASK-DEPS-P05.
    function test_whenCalledInAnyLifecycleState_refreshesRolesLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenCalledInAnyLifecycleState_refreshesRoles(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenCalledInAnyLifecycleState_refreshesRoles(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenCalledInAnyLifecycleState_refreshesRoles(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenCalledInAnyLifecycleState_refreshesRoles(address(0), false, false);
    }

    // Scenarios: RDTASK-DEPS-P02, RDTASK-DEPS-P06, RDTASK-DEPS-P07, RDTASK-DEPS-P08.
    function test_whenRolesUpgraded_refreshesCompatibleReplacementLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenRolesUpgraded_refreshesCompatibleReplacement(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenRolesUpgraded_refreshesCompatibleReplacement(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenRolesUpgraded_refreshesCompatibleReplacement(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenRolesUpgraded_refreshesCompatibleReplacement(address(0), false, false);
    }

    // Scenarios: RDTASK-DEPS-I01.
    function test_givenActivePolicy_whenRolesMissing_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(task.ROLES());
        uint48 beforeAt = task.lastTransitionAt();
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", toKeycode("ROLES")),
            abi.encode(address(0))
        );
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        // The expected revert has no return value.
        // forge-lint: disable-next-line(unused-return)
        task.configureDependencies();
        assertEq(address(task.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(task.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
    }

    // Scenarios: RDTASK-DEPS-I02.
    function test_givenActivePolicy_whenRolesUnsupportedMajor_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(task.ROLES());
        uint48 beforeAt = task.lastTransitionAt();
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
        task.configureDependencies();
        assertEq(address(task.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(task.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
    }
}
