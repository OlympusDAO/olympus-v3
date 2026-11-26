// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

// Scenario amounts are intentionally explicit; bounded casts are proven by their adjacent bounds.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

contract RevenueDistributorSetConfigOperatorTest is RevenueDistributorTest {
    // Scenarios: OP-A01, OP-A02.
    function test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
        address caller_,
        bool clearCurrent_,
        bool disable_,
        uint8 targetKind_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        uint64 id = _seedLifecycleQueue();
        targetKind_ = uint8(bound(targetKind_, 0, 3));
        if (clearCurrent_) {
            vm.prank(admin);
            distributor.setConfigOperator(address(0));
        }
        address current = distributor.configOperator();
        address target = targetKind_ == 0 ? address(0) : targetKind_ == 1
            ? current
            : targetKind_ == 2
            ? alice
            : address(token);
        if (disable_) {
            _disableDistributor();
        }

        bytes32 beforeState = _distributorStateDigest(id);
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        vm.prank(caller_);
        distributor.setConfigOperator(target);

        assertEq(distributor.configOperator(), current, "unauthorized rotation preserves operator");
        assertEq(
            distributor.getActiveAssetCount(),
            1,
            "unauthorized rotation preserves route state"
        );
        assertEq(
            _distributorStateDigest(id),
            beforeState,
            "Unauthorized rotation preserves funded state"
        );
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized rotation emits no event");
    }

    // Scenarios: OP-A03, OP-A04.
    function test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
        address caller_,
        bool clearCurrent_,
        bool disable_,
        uint8 targetKind_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        uint64 id = _seedLifecycleQueue();
        targetKind_ = uint8(bound(targetKind_, 0, 3));
        if (clearCurrent_) {
            vm.prank(admin);
            distributor.setConfigOperator(address(0));
        }
        address current = distributor.configOperator();
        address target = targetKind_ == 0 ? address(0) : targetKind_ == 1
            ? current
            : targetKind_ == 2
            ? alice
            : address(token);
        if (disable_) {
            _disableDistributor();
        }

        _setPolicyActive(address(distributor), false);

        bytes32 beforeState = _distributorStateDigest(id);
        vm.recordLogs();
        _expectPolicyInactive();
        vm.prank(caller_);
        distributor.setConfigOperator(target);

        assertEq(distributor.configOperator(), current, "unauthorized rotation preserves operator");
        assertEq(
            distributor.getActiveAssetCount(),
            1,
            "unauthorized rotation preserves route state"
        );
        assertEq(
            _distributorStateDigest(id),
            beforeState,
            "Unauthorized rotation preserves funded state"
        );
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized rotation emits no event");
    }

    function test_givenSelectedOperator_whenAdminClearsOperator_revokesConfiguration() public {
        vm.expectEmit(true, false, false, false, address(distributor));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        vm.prank(admin);
        distributor.setConfigOperator(address(0));

        assertEq(distributor.configOperator(), address(0), "operator is cleared");
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    function test_givenSelectedOperator_whenAdminClearsOperator_preservesConfiguration(
        bool disable_
    ) public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_333});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.seedPendingForTest(address(token), bob, 11, 22, 33);
        token.mint(address(distributor), 66);
        bytes32 routeHash = distributor.assetDistributionHash(address(token));
        if (disable_) {
            _disableDistributor();
        }

        vm.expectEmit(true, false, false, true, address(distributor));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        vm.prank(admin);
        distributor.setConfigOperator(address(0));

        assertEq(distributor.configOperator(), address(0), "operator is cleared");
        assertEq(
            distributor.assetDistributionHash(address(token)),
            routeHash,
            "route hash is preserved"
        );
        assertEq(distributor.getActiveAssetCount(), 1, "active membership is preserved");
        _assertPendingPayouts(address(token), bob, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "custody is preserved");
        assertEq(distributor.isEnabled(), !disable_, "local lifecycle state is preserved");
    }

    function test_givenClearedOperator_whenAdminRestoresTimelock_restoresConfiguration() public {
        vm.startPrank(admin);
        distributor.setConfigOperator(address(0));
        distributor.setConfigOperator(address(configTimelock));
        vm.stopPrank();

        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "timelock operator is restored"
        );
    }

    function test_whenNonAdminSetsOperator_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        vm.prank(caller_);
        distributor.setConfigOperator(address(0));
        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "unauthorized call leaves operator unchanged"
        );
    }

    function test_givenSelectedOperator_whenAdminSetsSameOperator_reverts() public {
        vm.recordLogs();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        vm.prank(admin);
        distributor.setConfigOperator(address(configTimelock));
        assertEq(vm.getRecordedLogs().length, 0, "same operator emits no event");
    }

    function test_givenClearedOperator_whenAdminSetsZeroAgain_reverts() public {
        vm.prank(admin);
        distributor.setConfigOperator(address(0));

        vm.recordLogs();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        vm.prank(admin);
        distributor.setConfigOperator(address(0));

        assertEq(distributor.configOperator(), address(0), "operator remains cleared");
        assertEq(vm.getRecordedLogs().length, 0, "same zero operator emits no event");
    }

    function test_givenPolicyInactive_whenAdminSetsChangedOperator_reverts() public {
        _setPolicyActive(address(distributor), false);

        vm.recordLogs();
        _expectPolicyInactive();
        vm.prank(admin);
        distributor.setConfigOperator(alice);

        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "inactive rotation preserves operator"
        );
        assertEq(vm.getRecordedLogs().length, 0, "inactive rotation emits no event");
    }

    // Scenarios: OP-L01, OP-L02.
    function test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(
        bool disable_,
        bool clearCurrent_,
        uint8 targetKind_
    ) public {
        targetKind_ = uint8(bound(targetKind_, 0, 2));
        if (clearCurrent_) {
            vm.prank(admin);
            distributor.setConfigOperator(address(0));
        }
        address current = distributor.configOperator();
        address target = targetKind_ == 0 ? address(0) : targetKind_ == 1 ? current : alice;
        distributor.seedPendingForTest(address(token), bob, 11, 22, 33);
        token.mint(address(distributor), 66);
        if (disable_) {
            _disableDistributor();
        }
        _setPolicyActive(address(distributor), false);

        bytes32 beforeState = _revenueAccountingDigest();
        vm.recordLogs();
        _expectPolicyInactive();
        vm.prank(admin);
        distributor.setConfigOperator(target);

        assertEq(distributor.configOperator(), current, "inactive rotation preserves operator");
        _assertPendingPayouts(address(token), bob, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "inactive rotation preserves custody");
        assertEq(distributor.isEnabled(), !disable_, "inactive rotation preserves local state");
        assertEq(
            _revenueAccountingDigest(),
            beforeState,
            "Inactive rotation preserves all accounting"
        );
        assertEq(vm.getRecordedLogs().length, 0, "inactive rotation emits no event");
    }

    // Scenarios: OP-L03.
    function test_givenPolicyInactive_whenNonAdminSetsOperator_revertsActivityFirst() public {
        _setPolicyActive(address(distributor), false);

        _expectPolicyInactive();
        vm.prank(alice);
        distributor.setConfigOperator(alice);
    }

    function test_givenLocallyDisabled_whenAdminSetsOperator_succeeds() public {
        _disableDistributor();

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IConfigOperator.ConfigOperatorSet(alice);
        vm.prank(admin);
        distributor.setConfigOperator(alice);

        assertEq(distributor.configOperator(), alice, "local disablement does not block rotation");
    }

    function test_whenAdminSetsEOAOperator_thenEOACanConfigureDistribution() public {
        vm.prank(admin);
        distributor.setConfigOperator(alice);
        assertEq(distributor.configOperator(), alice, "EOA becomes selected operator");

        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(alice);
        distributor.setAssetRoutes(address(token), 0, routes);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "selected EOA can configure an asset"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            )
        );
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
        assertEq(distributor.getActiveAssetCount(), 1, "old operator can no longer change route");
    }

    // Scenarios: OP-P01, OP-P02, OP-P04, OP-P05.
    function test_givenFundedActivePolicy_whenAdminChangesOperator(
        address caller_,
        address target_,
        bool cleared_,
        bool disabled_
    ) public {
        uint64 id = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        if (cleared_) {
            vm.prank(admin);
            distributor.setConfigOperator(address(0));
        }
        address previous = distributor.configOperator();
        vm.assume(target_ != previous);
        _setRevenuePolicyLifecycle(address(distributor), true, !disabled_);
        bytes32 funds = _revenueFundsDigest();
        bytes32 queue = _queuedLifecycleDigest(id);
        uint48 transition = distributor.lastTransitionAt();
        vm.expectEmit(true, false, false, true, address(distributor));
        emit IConfigOperator.ConfigOperatorSet(target_);
        vm.recordLogs();
        vm.prank(caller_);
        distributor.setConfigOperator(target_);
        assertEq(distributor.configOperator(), target_, "Requested operator stored");
        assertEq(vm.getRecordedLogs().length, 1, "Exactly one operator event");
        assertEq(_revenueFundsDigest(), funds, "Routes, debts, custody and indexes preserved");
        assertEq(_queuedLifecycleDigest(id), queue, "Queued action and ownership preserved");
        assertEq(distributor.lastTransitionAt(), transition, "Lifecycle timestamp preserved");
        assertEq(distributor.isEnabled(), !disabled_, "Enablement preserved");
        if (previous != address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    previous
                )
            );
            vm.prank(previous);
            distributor.rescuePendingPayout(address(token), alice, bob, 1);
        }
        if (target_ != address(0)) {
            vm.prank(target_);
            distributor.rescuePendingPayout(address(token), alice, bob, 1);
            assertEq(token.balanceOf(bob), 1, "New operator can rescue while disabled too");
        }
        vm.prank(caller_);
        distributor.rescuePendingPayout(address(token), address(treasury), bob, 1);
        assertEq(
            distributor.pendingPayout(address(token), address(treasury)),
            7,
            "Direct governance authority retained"
        );
    }

    // Scenarios: OP-I01, OP-I02.
    function test_givenFundedPolicy_whenAdminRepeatsOperator_reverts(
        address caller_,
        bool cleared_,
        bool disabled_
    ) public {
        uint64 id = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        if (cleared_) {
            vm.prank(admin);
            distributor.setConfigOperator(address(0));
        }
        _setRevenuePolicyLifecycle(address(distributor), true, !disabled_);
        address current = distributor.configOperator();
        bytes32 beforeState = _distributorStateDigest(id);
        vm.recordLogs();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        vm.prank(caller_);
        distributor.setConfigOperator(current);
        assertEq(
            _distributorStateDigest(id),
            beforeState,
            "Repeated operator preserves all funded state"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Repeated operator commits no logs");
    }

    // Scenarios: OP-A01, OP-A02, OP-A03, OP-A04, OP-I01, OP-I02, OP-L01, OP-L02, OP-P01, OP-P02, OP-P04, OP-P05.
    function test_givenOperatorLifecycleAndIdentitySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            false,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(false, false, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(false, false, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(false, false, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedPolicy_whenAdminRepeatsOperator_reverts(address(0x1234), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(address(0x1234), alice, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(
            address(0x1234),
            address(token),
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(
            address(0x1234),
            address(0),
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            false,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(false, true, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(false, true, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(false, true, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedPolicy_whenAdminRepeatsOperator_reverts(address(0x1234), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(address(0x1234), alice, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(
            address(0x1234),
            address(token),
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            false,
            true,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(true, false, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(true, false, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(true, false, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedPolicy_whenAdminRepeatsOperator_reverts(address(0x1234), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(address(0x1234), alice, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(
            address(0x1234),
            address(token),
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(
            address(0x1234),
            address(0),
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
            address(0),
            true,
            true,
            3
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(true, true, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(true, true, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts(true, true, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedPolicy_whenAdminRepeatsOperator_reverts(address(0x1234), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(address(0x1234), alice, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
        test_givenFundedActivePolicy_whenAdminChangesOperator(
            address(0x1234),
            address(token),
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore operator seed");
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast)
