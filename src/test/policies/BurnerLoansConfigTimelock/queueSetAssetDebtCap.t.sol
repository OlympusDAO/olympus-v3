// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetAssetDebtCapTest is BurnerLoansConfigTimelockTest {
    event AssetDebtCapSet(address indexed asset, uint256 debtCapOhm);

    // queueSetAssetDebtCap
    // given caller has neither admin nor burner_loans_admin
    //  when queueing an asset debt cap update
    //   then it reverts before validating the cap
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        configTimelock.queueSetAssetDebtCap(address(usds), 0);
    }

    // queueSetAssetDebtCap
    // given asset is not configured for this facility
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
    // given market principal due is zero
    //  when zero is queued and executed
    //   then the market cap is set to zero
    function test_givenMarketPrincipalDueIsZero_allowsZeroCap() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), 0);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDebtCapSet(address(usds), 0);
        _expectSingleActionExecuted(
            actionId,
            IBurnerLoansConfig.setAssetDebtCap.selector,
            address(this)
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoansConfig.getAssetConfig(address(usds)).debtCap, 0, "asset debt cap");
    }

    // queueSetAssetDebtCap
    // given market originations are disabled
    //  when a cap update is queued and executed
    //   then the existing market can still be configured
    function test_givenOriginationsDisabled_executes() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), 50_000e9);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertFalse(stored.originationsEnabled, "originations disabled");
        assertEq(stored.debtCap, 50_000e9, "asset debt cap");
    }

    // queueSetAssetDebtCap
    // given market principal due exceeds the proposed cap
    //  when queueing the cap
    //   then it reverts
    function test_givenCapBelowMarketPrincipalDue_reverts(
        uint128 activeDebtOhm_,
        uint128 cap_
    ) public {
        activeDebtOhm_ = uint128(bound(activeDebtOhm_, 1, _defaultAssetDebtCap()));
        cap_ = uint128(bound(cap_, 0, activeDebtOhm_ - 1));
        burnerLoans.setActiveDebtForTest(address(usds), activeDebtOhm_, activeDebtOhm_);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        configTimelock.queueSetAssetDebtCap(address(usds), cap_);
    }

    // queueSetAssetDebtCap
    // given market principal due rises above a queued cap
    //  when executing the update
    //   then live validation reverts and preserves the old cap
    function test_givenMarketPrincipalDueRisesAboveQueuedCap_reverts() public {
        uint128 debtCapOhm = 50_000e9;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm);
        burnerLoans.setActiveDebtForTest(address(usds), debtCapOhm + 1, debtCapOhm + 1);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            _defaultAssetDebtCap(),
            "asset debt cap unchanged"
        );
    }

    // queueSetAssetDebtCap
    // given market principal due changes but remains within a queued cap
    //  when executing the update
    //   then it succeeds
    function test_givenMarketPrincipalDueRemainsWithinQueuedCap_executesAction() public {
        uint128 debtCapOhm = 50_000e9;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm);
        burnerLoans.setActiveDebtForTest(address(usds), debtCapOhm - 1, debtCapOhm - 1);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDebtCapSet(address(usds), debtCapOhm);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            debtCapOhm,
            "asset debt cap"
        );
    }

    // queueSetAssetDebtCap
    // given caller has admin role and cap is valid
    //  when queueing the update
    //   then the facility-scoped Config action is stored
    function test_givenAdminCaller_whenCapIsValid_queuesAction(uint128 debtCapOhm_) public {
        debtCapOhm_ = uint128(bound(debtCapOhm_, 1, type(uint128).max));
        uint64 nextActionId = configTimelock.nextActionId();
        bytes memory payload = abi.encode(address(usds), debtCapOhm_);
        _expectSingleActionQueued(
            nextActionId,
            admin,
            IBurnerLoansConfig.setAssetDebtCap.selector,
            payload
        );

        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(actionId, nextActionId, "action id");
        (address target, bytes4 selector, bytes memory storedPayload) = configTimelock
            .getQueuedSubAction(actionId, 0);
        assertEq(target, address(burnerLoansConfig), "target");
        assertEq(selector, IBurnerLoansConfig.setAssetDebtCap.selector, "selector");
        assertEq(storedPayload, payload, "payload");
    }

    // queueSetAssetDebtCap
    // given caller has burner_loans_admin role and cap is valid
    //  when queueing the update
    //   then the action is queued
    function test_givenBurnerLoansAdminCaller_whenCapIsValid_queuesAction(
        uint128 debtCapOhm_
    ) public {
        debtCapOhm_ = uint128(bound(debtCapOhm_, 1, type(uint128).max));

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm_);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetDebtCap
    // given a valid queued cap update and elapsed delay
    //  when executing the action
    //   then Config stores it on the Burner Loans market
    function test_givenDelayElapsed_executesAction(uint128 debtCapOhm_) public {
        debtCapOhm_ = uint128(bound(debtCapOhm_, 1, type(uint128).max));

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm_);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetDebtCapSet(address(usds), debtCapOhm_);
        _expectSingleActionExecuted(
            actionId,
            IBurnerLoansConfig.setAssetDebtCap.selector,
            address(this)
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            debtCapOhm_,
            "asset debt cap"
        );
    }
}
