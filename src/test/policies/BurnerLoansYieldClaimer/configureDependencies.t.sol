// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {MockConfigUnsupportedRoles} from "src/test/policies/BurnerLoansConfig/fixtures/MockConfigUnsupportedRoles.sol";
import {MockTaskCompatibleRoles} from "src/test/policies/RevenueDistributorTask/fixtures/MockTaskCompatibleRoles.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";
import {MockBurnerLoansYieldClaimerTarget} from "./MockBurnerLoansYieldClaimerTarget.sol";

contract BurnerLoansYieldClaimerConfigureDependenciesTest is BurnerLoansYieldClaimerTest {
    // Scenarios: BLYC-DEPS-P01.
    function test_whenCalledInAnyLifecycleState_refreshesRoles(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setClaimerLifecycle(active_, enabled_);
        uint32 executionLimitBefore = claimer.executionGasLimit();
        uint32 thresholdBefore = claimer.minimumGasToAttempt();
        uint32 reserveBefore = claimer.gasReserve();
        uint256 cursorBefore = claimer.nextAssetIndex();

        vm.prank(caller_);
        Keycode[] memory dependencies = claimer.configureDependencies();

        assertEq(dependencies.length, 1, "dependency count");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES keycode"
        );
        assertEq(address(claimer.ROLES()), address(roles), "cached ROLES address");
        assertEq(claimer.executionGasLimit(), executionLimitBefore, "execution limit unchanged");
        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(claimer.nextAssetIndex(), cursorBefore, "cursor unchanged");
    }

    // Scenarios: BLYC-DEPS-P02.
    function test_whenRolesUpgraded_refreshesCompatibleReplacement(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setClaimerLifecycle(active_, enabled_);
        MockTaskCompatibleRoles replacement = new MockTaskCompatibleRoles(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));

        vm.prank(caller_);
        Keycode[] memory dependencies = claimer.configureDependencies();

        assertEq(dependencies.length, 1, "dependency count");
        assertEq(address(claimer.ROLES()), address(replacement), "replacement ROLES cached");
    }

    // Scenarios: BLYC-DEPS-I01.
    function test_whenRolesMissing_reverts(address caller_) public {
        (BurnerLoansYieldClaimer localClaimer, ) = _deployWithKernelWithoutRoles();
        uint32 executionLimitBefore = localClaimer.executionGasLimit();

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        // The return value is unavailable because the call is expected to revert.
        // forge-lint: disable-next-line(unused-return)
        localClaimer.configureDependencies();

        assertEq(address(localClaimer.ROLES()), address(0), "cached dependency rolls back");
        assertEq(localClaimer.executionGasLimit(), executionLimitBefore, "configuration unchanged");
    }

    // Scenarios: BLYC-DEPS-I02.
    function test_whenRolesMajorUnsupported_reverts(address caller_) public {
        (
            BurnerLoansYieldClaimer localClaimer,
            Kernel localKernel
        ) = _deployWithKernelWithoutRoles();
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
        localClaimer.configureDependencies();

        assertEq(address(localClaimer.ROLES()), address(0), "cached dependency rolls back");
    }

    function _deployWithKernelWithoutRoles()
        internal
        returns (BurnerLoansYieldClaimer localClaimer_, Kernel localKernel_)
    {
        localKernel_ = new Kernel();
        MockBurnerLoansYieldClaimerTarget localTarget = new MockBurnerLoansYieldClaimerTarget(
            localKernel_
        );
        localClaimer_ = new BurnerLoansYieldClaimer(localKernel_, address(localTarget), 1);
    }
}
