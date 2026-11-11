// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Expected-revert calls and repeated configuration probes discard their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {Actions, Kernel, Policy, Keycode, toKeycode} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";

contract BurnerLoansInventoryConfigTimelockConfigureDependenciesTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-DEPS-P01.
    function test_whenDependenciesConfigured_thenExactRolesCache(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingRecovery {
        _setState(_timelock, active_, enabled_);
        bytes32 state = _queueDigest(_pendingId);
        vm.prank(caller_);
        Keycode[] memory dependencies = _timelock.configureDependencies();
        assertEq(dependencies.length, 1, "Single module dependency");
        assertEq(Keycode.unwrap(dependencies[0]), "ROLES", "ROLES keycode");
        assertEq(
            address(_timelock.ROLES()),
            address(_roles),
            "ROLES cache resolves installed module"
        );
        vm.prank(caller_);
        _timelock.configureDependencies();
        assertEq(
            _queueDigest(_pendingId),
            state,
            "Repeat configuration preserves all queue and Inventory state"
        );
    }

    // Scenarios: BLINCT-DEPS-I01.
    function test_givenRolesAbsent_whenConfigured_reverts(
        address caller_
    ) public givenPendingRecovery {
        Kernel empty = new Kernel();
        vm.prank(address(_kernel));
        _timelock.changeKernel(empty);
        bytes32 state = _queueDigest(_pendingId);
        address roles = address(_timelock.ROLES());
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        _timelock.configureDependencies();
        assertEq(address(_timelock.ROLES()), roles, "No partial cache update");
        assertEq(_queueDigest(_pendingId), state, "Missing module preserves queue and funds");
    }

    // Scenarios: BLINCT-DEPS-I02.
    function test_givenUnsupportedRolesVersion_whenConfigured_reverts(
        address caller_,
        uint8 major_
    ) public givenPendingRecovery {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(_roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, uint8(0))
        );
        bytes32 state = _queueDigest(_pendingId);
        address roles = address(_timelock.ROLES());
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion.selector);
        vm.prank(caller_);
        _timelock.configureDependencies();
        assertEq(address(_timelock.ROLES()), roles, "Unsupported module preserves cache");
        assertEq(
            _queueDigest(_pendingId),
            state,
            "Rejected configuration preserves queue and funds"
        );
    }

    // Scenarios: BLINCT-DEPS-P01.
    function test_givenKernelMigration_whenConfigured_thenFreshRolesResolved(
        address caller_
    ) public givenPendingRecovery {
        Kernel next = new Kernel();
        OlympusRoles replacement = new OlympusRoles(next);
        next.executeAction(Actions.InstallModule, address(replacement));
        vm.prank(address(_kernel));
        _timelock.changeKernel(next);
        bytes32 state = _queueDigest(_pendingId);
        vm.prank(caller_);
        Keycode[] memory dependencies = _timelock.configureDependencies();
        assertEq(dependencies.length, 1, "Exactly one migrated dependency");
        assertEq(Keycode.unwrap(dependencies[0]), "ROLES", "Migrated ROLES keycode");
        assertEq(
            address(_timelock.ROLES()),
            address(replacement),
            "Permissionless hook replaces the old cache before activation"
        );
        assertEq(
            _queueDigest(_pendingId),
            state,
            "Refreshing dependencies preserves pending work and Inventory accounting"
        );
    }
}

// forge-lint: disable-end(unused-return)
