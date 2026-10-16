// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

// The bounded role-identity loop intentionally calls Foundry cheatcodes and the task entry point.
// forge-lint: disable-start(calls-loop)

contract BurnerLoansYieldClaimerSelfExecuteTaskTest is BurnerLoansYieldClaimerTest {
    // Scenarios: SELF-A01.
    function test_whenExternalCallerExecutesTaskDirectly_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != address(claimer));
        _setClaimerLifecycle(active_, enabled_);

        vm.expectRevert(IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_OnlySelf.selector);
        vm.prank(caller_);
        claimer.selfExecuteTask();

        assertEq(claimer.nextAssetIndex(), 0, "unauthorized call preserves cursor");
        assertEq(target.claimCalls(), 0, "unauthorized call makes no claim");
    }

    // Scenarios: SELF-A01.
    function test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts() public {
        address[5] memory callers = [admin, burnerLoansAdmin, _emergency, heart, address(target)];
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(claimer));

        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_OnlySelf.selector);
            vm.prank(callers[i]);
            claimer.selfExecuteTask();
        }

        assertEq(claimer.nextAssetIndex(), 0, "role-bearing calls preserve cursor");
        assertEq(target.claimCalls(), 0, "role-bearing calls make no claim");
    }

    // Scenarios: SELF-P01.
    function test_givenCallerIsSelf_executesTask(bool active_, bool enabled_) public {
        _setClaimerLifecycle(active_, enabled_);

        vm.prank(address(claimer));
        claimer.selfExecuteTask();

        assertEq(target.claimCalls(), 1, "self call makes claim");
        assertEq(
            target.lastClaimedAsset(),
            target.getAssetAt(0),
            "self call claims registered asset"
        );
        assertEq(claimer.nextAssetIndex(), 0, "single-asset cursor wraps");
    }
}

// forge-lint: disable-end(calls-loop)
