// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// The test-local compatible ROLES mock is clearer beside its sole consumer. Calls whose return
// values are omitted assert cache updates or exact reverts instead.
// forge-lint: disable-start(multi-contract-file,unused-return)

// Contracts
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";
import {Kernel, Keycode, Module, Policy, toKeycode} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {MockConfigUnsupportedRoles} from "src/test/policies/BurnerLoansConfig/fixtures/MockConfigUnsupportedRoles.sol";

contract RevenueDistributorConfigTimelockConfigureDependenciesTest is
    RevenueDistributorConfigTimelockTest
{
    // Scenarios: RDCT-DEPS-P01, RDCT-DEPS-P03, RDCT-DEPS-P04, RDCT-DEPS-P05.
    function test_whenCalledInAnyLifecycleState_refreshesRoles(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(configTimelock), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = configTimelock.lastTransitionAt();
        uint32 beforeGrace = configTimelock.gracePeriod();
        vm.recordLogs();
        vm.prank(caller_);
        Keycode[] memory dependencies = configTimelock.configureDependencies();

        assertEq(dependencies.length, 1, "dependency count");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES keycode"
        );
        assertEq(address(configTimelock.ROLES()), address(roles), "cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Module refresh preserves raw accounting and custody"
        );
        assertEq(configTimelock.isEnabled(), enabled_, "Module refresh preserves local enablement");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Module refresh preserves transition timestamp"
        );
        assertEq(configTimelock.gracePeriod(), beforeGrace, "Module refresh preserves grace");
        assertEq(vm.getRecordedLogs().length, 0, "Module refresh emits no events");
    }

    // Scenarios: RDCT-DEPS-P02, RDCT-DEPS-P06, RDCT-DEPS-P07, RDCT-DEPS-P08.
    function test_whenRolesUpgraded_refreshesCompatibleReplacement(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(configTimelock), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = configTimelock.lastTransitionAt();
        MockCompatibleRoles replacement = new MockCompatibleRoles(kernel);
        _upgradeModule(replacement);
        vm.recordLogs();
        vm.prank(caller_);
        Keycode[] memory dependencies = configTimelock.configureDependencies();
        assertEq(dependencies.length, 1, "One dependency is returned");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES keycode"
        );
        assertEq(
            address(configTimelock.ROLES()),
            address(replacement),
            "Compatible minor version is cached"
        );
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Role module replacement preserves accounting and custody"
        );
        assertEq(
            configTimelock.isEnabled(),
            enabled_,
            "Role module replacement preserves enablement"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Role module replacement preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Permissionless refresh emits no events");
    }

    function test_whenRolesMissing_reverts(address caller_) public {
        (, RevenueDistributorConfigTimelock localTimelock) = _newTimelockWithoutModules();

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        localTimelock.configureDependencies();
    }

    function test_whenRolesMajorUnsupported_reverts(address caller_) public {
        (
            Kernel localKernel,
            RevenueDistributorConfigTimelock localTimelock
        ) = _newTimelockWithoutModules();
        _installModule(localKernel, new MockConfigUnsupportedRoles(localKernel));

        vm.expectRevert(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([uint8(1)])
            )
        );
        vm.prank(caller_);
        localTimelock.configureDependencies();
    }

    // Scenarios: RDCT-DEPS-P01, RDCT-DEPS-P03, RDCT-DEPS-P04, RDCT-DEPS-P05.
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

    // Scenarios: RDCT-DEPS-P02, RDCT-DEPS-P06, RDCT-DEPS-P07, RDCT-DEPS-P08.
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

    // Scenarios: RDCT-DEPS-I01.
    function test_givenActivePolicy_whenRolesMissing_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(configTimelock.ROLES());
        uint48 beforeAt = configTimelock.lastTransitionAt();
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
        configTimelock.configureDependencies();
        assertEq(address(configTimelock.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(configTimelock.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(configTimelock.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
    }

    // Scenarios: RDCT-DEPS-I02.
    function test_givenActivePolicy_whenRolesUnsupportedMajor_reverts(address caller_) public {
        _seedLifecycleRevenue();
        bytes32 beforeState = _revenueAccountingDigest();
        address beforeRoles = address(configTimelock.ROLES());
        uint48 beforeAt = configTimelock.lastTransitionAt();
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
        configTimelock.configureDependencies();
        assertEq(address(configTimelock.ROLES()), beforeRoles, "Failure restores cached ROLES");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Failure restores accounting and custody"
        );
        assertEq(configTimelock.lastTransitionAt(), beforeAt, "Failure preserves timestamp");
        assertTrue(configTimelock.isEnabled(), "Failure preserves enabled state");
        assertEq(vm.getRecordedLogs().length, 0, "Failure commits no logs");
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
