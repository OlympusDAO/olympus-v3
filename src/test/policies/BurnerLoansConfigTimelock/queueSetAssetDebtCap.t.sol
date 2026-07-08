// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetAssetDebtCapTest is BurnerLoansConfigTimelockTest {
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);

    // queueSetAssetDebtCap
    // given caller has neither admin nor burner_loans_admin
    //  when queueing an asset debt cap update
    //   then it reverts before validating the cap
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        configTimelock.queueSetAssetDebtCap(address(usds), 0);
    }

    // queueSetAssetDebtCap
    // given asset is not configured
    //  when queueing an asset debt cap update
    //   then it reverts
    function test_givenUnconfiguredAsset_reverts() public {
        address unknownAsset = makeAddr("unknownAsset");

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unknownAsset
            )
        );
        configTimelock.queueSetAssetDebtCap(unknownAsset, 100_000e9);
    }

    // queueSetAssetDebtCap
    // given timelock policy is disabled
    //  when queueing an asset debt cap update
    //   then it reverts
    function test_givenTimelockDisabled_reverts() public {
        vm.prank(emergency);
        configTimelock.disable("");

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueSetAssetDebtCap(address(usds), 0);
    }

    // queueSetAssetDebtCap
    // given new asset debt cap is zero
    //  when queueing an asset debt cap update
    //   then the action is queued because active asset debt is zero
    function test_givenActiveDebtIsZero_allowsZeroCap() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), 0);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), 0);
        _expectSingleActionExecuted(actionId, IBurnerLoans.setAssetDebtCap.selector, address(this));
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, 0, "asset debt cap");
    }

    // queueSetAssetDebtCap
    // given new asset debt cap is below active asset debt
    //  when queueing an asset debt cap update
    //   then it reverts
    function test_givenCapBelowActiveDebt_reverts(uint256 activeDebtOhm_, uint256 cap_) public {
        activeDebtOhm_ = bound(activeDebtOhm_, 1, burnerLoans.globalDebtCapOhm());
        cap_ = bound(cap_, 0, activeDebtOhm_ - 1);
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        configTimelock.queueSetAssetDebtCap(address(usds), cap_);
    }

    // queueSetAssetDebtCap
    // given new asset debt cap is above the global debt cap
    //  when queueing an asset debt cap update
    //   then it reverts
    function test_givenCapAboveGlobalCap_reverts(uint256 cap_) public {
        uint256 globalDebtCap = burnerLoans.globalDebtCapOhm();
        cap_ = bound(cap_, globalDebtCap + 1, type(uint128).max);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        configTimelock.queueSetAssetDebtCap(address(usds), cap_);
    }

    // queueSetAssetDebtCap
    // given asset active debt rises above the queued debt cap after queueing
    //  when executing the asset debt cap update
    //   then it reverts because the live cap invariant is broken
    function test_givenAssetActiveDebtRisesAboveQueuedCap_reverts() public {
        uint256 debtCapOhm = 50_000e9;
        uint64 actionId;

        vm.prank(burnerLoansAdmin);
        actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm);

        burnerLoans.setActiveDebtForTest(address(usds), debtCapOhm + 1, debtCapOhm + 1);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoans.getAssetConfig(address(usds)).debtCap,
            100_000e9,
            "asset debt cap unchanged"
        );
    }

    // queueSetAssetDebtCap
    // given global debt cap falls below the queued asset debt cap after queueing
    //  when executing the asset debt cap update
    //   then it reverts because the live cap invariant is broken
    function test_givenGlobalDebtCapFallsBelowQueuedCap_reverts() public {
        uint256 debtCapOhm = 900_000e9;
        uint64 actionId;

        vm.prank(burnerLoansAdmin);
        actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm);

        // The old asset cap is 100,000 OHM, so governance can still lower the global cap
        // below the queued 900,000 OHM cap without violating the current stored asset cap.
        vm.prank(admin);
        burnerLoans.setGlobalDebtCap(500_000e9);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoans.getAssetConfig(address(usds)).debtCap,
            100_000e9,
            "asset debt cap unchanged"
        );
    }

    // queueSetAssetDebtCap
    // given global debt cap changes after queueing but remains above the queued asset debt cap
    //  when executing the asset debt cap update
    //   then the action executes because live validation still passes
    function test_givenGlobalDebtCapChangesWithinQueuedCap_executesAction() public {
        uint256 debtCapOhm = 900_000e9;
        uint64 actionId;

        vm.prank(burnerLoansAdmin);
        actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm);

        vm.prank(admin);
        burnerLoans.setGlobalDebtCap(950_000e9);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), debtCapOhm);
        _expectSingleActionExecuted(actionId, IBurnerLoans.setAssetDebtCap.selector, address(this));
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, debtCapOhm, "asset debt cap");
    }

    // queueSetAssetDebtCap
    // given active debt changes after queueing but remains below the queued debt cap
    //  when executing the asset debt cap update
    //   then the action executes because live validation still passes
    function test_givenAssetActiveDebtChangesWithinQueuedCap_executesAction() public {
        uint256 debtCapOhm = 50_000e9;
        uint64 actionId;

        vm.prank(burnerLoansAdmin);
        actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm);

        burnerLoans.setActiveDebtForTest(address(usds), debtCapOhm - 1, debtCapOhm - 1);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), debtCapOhm);
        _expectSingleActionExecuted(actionId, IBurnerLoans.setAssetDebtCap.selector, address(this));
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, debtCapOhm, "asset debt cap");
    }

    // queueSetAssetDebtCap
    // given caller has admin role
    //  when asset debt cap is valid
    //   then the action is queued and stores the expected sub-action
    function test_givenAdminCaller_whenCapIsValid_queuesAction(uint256 debtCapOhm_) public {
        debtCapOhm_ = bound(debtCapOhm_, 1, burnerLoans.globalDebtCapOhm());
        uint64 nextActionId = configTimelock.nextActionId();
        bytes memory payload = abi.encode(address(usds), debtCapOhm_);
        _expectSingleActionQueued(
            nextActionId,
            admin,
            IBurnerLoans.setAssetDebtCap.selector,
            payload
        );

        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(actionId, nextActionId, "action id");
        (address target, bytes4 selector, bytes memory storedPayload) = configTimelock
            .getQueuedSubAction(actionId, 0);
        assertEq(target, address(burnerLoans), "target");
        assertEq(selector, IBurnerLoans.setAssetDebtCap.selector, "selector");
        assertEq(storedPayload, payload, "payload");
    }

    // queueSetAssetDebtCap
    // given caller has burner_loans_admin role
    //  when asset debt cap is valid
    //   then the action is queued
    function test_givenBurnerLoansAdminCaller_whenCapIsValid_queuesAction(
        uint256 debtCapOhm_
    ) public {
        debtCapOhm_ = bound(debtCapOhm_, 1, burnerLoans.globalDebtCapOhm());

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetDebtCap
    // given a valid queued asset debt cap update
    //  when the action executes after the delay
    //   then BurnerLoans stores the new cap
    function test_givenDelayElapsed_executesAction(uint256 debtCapOhm_) public {
        debtCapOhm_ = bound(debtCapOhm_, 1, burnerLoans.globalDebtCapOhm());

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm_);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetDebtCapSet(address(usds), debtCapOhm_);
        _expectSingleActionExecuted(actionId, IBurnerLoans.setAssetDebtCap.selector, address(this));
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, debtCapOhm_, "asset debt cap");
    }
}
