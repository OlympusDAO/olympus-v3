// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {Actions} from "src/Kernel.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

// Scenario amounts are intentionally explicit; bounded casts are proven by their adjacent bounds.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

contract RevenueDistributorSetConfigOperatorTest is RevenueDistributorTest {
    // Scenarios: OP-A01
    function test_givenAnyLifecycleAndOperatorState_whenNonAdminSetsAnyOperator_reverts(
        address caller_,
        bool clearCurrent_,
        bool disable_,
        bool deactivate_,
        uint8 targetKind_
    ) public {
        vm.assume(caller_ != admin);
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
            vm.prank(admin);
            distributor.disable("");
        }
        if (deactivate_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        }

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, caller_)
        );
        vm.prank(caller_);
        distributor.setConfigOperator(target);

        assertEq(distributor.configOperator(), current, "unauthorized rotation preserves operator");
        assertEq(
            distributor.getActiveAssetCount(),
            0,
            "unauthorized rotation preserves route state"
        );
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized rotation emits no event");
    }

    // Scenarios: OP-P04
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

    // Scenarios: OP-P04
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
            vm.prank(admin);
            distributor.disable("");
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

    // Scenarios: OP-P01
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

    // Scenarios: OP-A01
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

    // Scenarios: OP-I01
    function test_givenSelectedOperator_whenAdminSetsSameOperator_reverts() public {
        vm.recordLogs();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        vm.prank(admin);
        distributor.setConfigOperator(address(configTimelock));
        assertEq(vm.getRecordedLogs().length, 0, "same operator emits no event");
    }

    // Scenarios: OP-I01
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

    // Scenarios: OP-L01
    function test_givenPolicyInactive_whenAdminSetsChangedOperator_reverts() public {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        vm.prank(admin);
        distributor.setConfigOperator(alice);

        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "inactive rotation preserves operator"
        );
        assertEq(vm.getRecordedLogs().length, 0, "inactive rotation emits no event");
    }

    // Scenarios: OP-L01
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
            vm.prank(admin);
            distributor.disable("");
        }
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        vm.prank(admin);
        distributor.setConfigOperator(target);

        assertEq(distributor.configOperator(), current, "inactive rotation preserves operator");
        _assertPendingPayouts(address(token), bob, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "inactive rotation preserves custody");
        assertEq(distributor.isEnabled(), !disable_, "inactive rotation preserves local state");
        assertEq(vm.getRecordedLogs().length, 0, "inactive rotation emits no event");
    }

    // Scenarios: OP-A01
    function test_givenPolicyInactive_whenNonAdminSetsOperator_revertsUnauthorizedFirst() public {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.expectRevert(
            abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unauthorized.selector, alice)
        );
        vm.prank(alice);
        distributor.setConfigOperator(alice);
    }

    // Scenarios: OP-P01
    function test_givenLocallyDisabled_whenAdminSetsOperator_succeeds() public {
        vm.prank(admin);
        distributor.disable("");

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IConfigOperator.ConfigOperatorSet(alice);
        vm.prank(admin);
        distributor.setConfigOperator(alice);

        assertEq(distributor.configOperator(), alice, "local disablement does not block rotation");
    }

    // Scenarios: OP-P01
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
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast)
