// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";
import {Actions} from "src/Kernel.sol";
import {MockBurnerLoansYieldClaimerTaskTarget} from "src/test/policies/BurnerLoansYieldClaimerTask/MockBurnerLoansYieldClaimerTaskTarget.sol";

// The bounded role-identity loop intentionally calls Foundry cheatcodes and the task entry point.
// forge-lint: disable-start(calls-loop)

contract BurnerLoansYieldClaimerTaskSelfExecuteTaskTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-SELF-EXECUTE-A01.
    function test_whenExternalCallerExecutesTaskDirectly_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != address(claimer));
        _setClaimerLifecycle(active_, enabled_);

        vm.expectRevert(IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_OnlySelf.selector);
        vm.prank(caller_);
        claimer.selfExecuteTask();

        assertEq(claimer.nextAssetIndex(), 0, "unauthorized call preserves cursor");
        assertEq(target.claimCalls(), 0, "unauthorized call makes no claim");
    }

    // Scenarios: BLYC-SELF-EXECUTE-A01.
    function test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts() public {
        address[5] memory callers = [admin, burnerLoansAdmin, _emergency, heart, address(target)];
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(claimer));

        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(IBurnerLoansYieldClaimerTask.BurnerLoansYieldClaimer_OnlySelf.selector);
            vm.prank(callers[i]);
            claimer.selfExecuteTask();
        }

        assertEq(claimer.nextAssetIndex(), 0, "role-bearing calls preserve cursor");
        assertEq(target.claimCalls(), 0, "role-bearing calls make no claim");
    }

    // Scenarios: BLYC-EXECUTE-P01.
    function test_givenCallerIsSelf_executesTask() public {
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

    // Scenarios: BLYC-SELF-EXECUTE-L01, BLYC-SELF-EXECUTE-L02, BLYC-SELF-EXECUTE-L03.
    function test_givenUnavailableCore_whenSelfCalled(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        address[] memory assets = new address[](2);
        assets[0] = address(1);
        assets[1] = address(2);
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);
        _setTargetLifecycle(active_, enabled_);
        target.setAssetViewReverts(true);
        vm.recordLogs();
        vm.prank(address(claimer));
        claimer.selfExecuteTask();
        assertEq(claimer.nextAssetIndex(), 1, "Core gate preserves saved cursor");
        assertEq(target.claimCalls(), 0, "No claim");
        assertEq(vm.getRecordedLogs().length, 0, "No failure event");
    }

    // Scenarios: BLYC-SELF-EXECUTE-A02, BLYC-SELF-EXECUTE-I01.
    function test_givenEmptyRegistry_whenHeartSelfCalls() public {
        target.setAssets(new address[](0));
        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();
        assertEq(vm.getRecordedLogs().length, 0, "Empty scan succeeds without failures");
        assertEq(claimer.nextAssetIndex(), 0, "Empty scan retains cursor");
    }

    // Scenarios: BLYC-SELF-EXECUTE-P02.
    function test_givenAttemptGasBreakpoint_whenBudgetIsAdjacent() public {
        _assertGasBreakpoint();
    }

    // Scenarios: BLYC-SELF-EXECUTE-P02.
    function test_givenPostLookupReserveBreakpoint_whenBudgetIsAdjacent() public {
        vm.prank(admin);
        claimer.setGasReserve(240_000);
        _assertGasBreakpoint();
    }

    function _assertGasBreakpoint() internal {
        address[] memory assets = new address[](2);
        assets[0] = address(1);
        assets[1] = address(2);
        target.setAssets(assets);
        vm.mockCall(
            address(claimer),
            abi.encodeWithSignature("claimYield(address)"),
            abi.encode(address(1), uint256(1))
        );
        // Calibrate the exact forwarded-gas breakpoint for this compiler. Below it the task
        // stops without writing its cursor; at/above it exactly one attempted asset is saved.
        // Warm all lookup and storage slots before measuring so access warmth is identical.
        _selfCall(400_000);
        vm.prank(admin);
        claimer.setNextAssetIndex(0);
        uint256 low = 200_000;
        uint256 high = 400_000;
        while (low + 1 < high) {
            uint256 mid = (low + high) / 2;
            uint256 saved = vm.snapshotState();
            vm.record();
            _selfCall(mid);
            (, bytes32[] memory writes) = vm.accesses(address(claimer));
            // A complete two-asset pass wraps the cursor to zero; a cursor write still proves
            // an attempt. This keeps the binary-search predicate monotonic in the gas budget.
            bool attempted = writes.length != 0;
            vm.revertToState(saved);
            if (attempted) high = mid;
            else low = mid;
        }
        uint256 snapshot = vm.snapshotState();
        _selfCall(high - 1);
        assertEq(claimer.nextAssetIndex(), 0, "Breakpoint minus one preserves current asset");
        vm.revertToState(snapshot);
        _selfCall(high);
        assertEq(claimer.nextAssetIndex(), 1, "First sufficient budget persists one attempt");
        vm.revertToState(snapshot);
        _selfCall(high + 1);
        assertEq(claimer.nextAssetIndex(), 1, "Breakpoint plus one persists the same attempt");
    }

    function _selfCall(uint256 gas_) internal {
        vm.prank(address(claimer));
        (bool success, ) = address(claimer).call{gas: gas_}(
            abi.encodeCall(claimer.selfExecuteTask, ())
        );
        assertTrue(success, "Self scan returns cleanly at gas boundary");
    }

    // Scenarios: BLYC-SELF-EXECUTE-P01.
    function test_givenLaterRegistryFailure_whenSelfCalled_reverts() public {
        address[] memory assets = new address[](2);
        assets[0] = address(1);
        assets[1] = address(2);
        target.setAssets(assets);
        target.setAssetViewRevertIndex(1);
        vm.expectRevert(MockBurnerLoansYieldClaimerTaskTarget.AssetViewReverted.selector);
        vm.prank(address(claimer));
        claimer.selfExecuteTask();
        assertEq(
            target.claimCalls(),
            0,
            "Registry failure rolls back earlier successful settlement"
        );
        assertEq(claimer.nextAssetIndex(), 0, "All self-call cursor writes roll back");
    }
}

// forge-lint: disable-end(calls-loop)
