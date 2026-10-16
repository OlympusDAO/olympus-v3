// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Scenario amounts stay inline for accounting clarity.
// Scenario matrices intentionally call the system in bounded loops; bounded casts are proven locally.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorDisableAssetRoutesTest is RevenueDistributorTest {
    // given an active asset
    //   when governance admin disables its routes
    //     [X] the asset is retired
    // Scenarios: DAR-A01
    function test_givenActiveAsset_whenAdminDisables_succeeds()
        public
        givenAliceConfiguredAsRecipient
    {
        bytes32 beforeHash = distributor.assetDistributionHash(address(token));
        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionDisabled(address(token));
        vm.prank(admin);
        distributor.disableAssetRoutes(address(token));
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "admin retires active asset"
        );
        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory routes) = distributor
            .getAssetDistribution(address(token));
        assertEq(repurchaseBps, 0, "admin retirement clears repurchase share");
        assertEq(routes.length, 0, "admin retirement clears configured routes");
        assertEq(
            distributor.getActiveAssetCount(),
            0,
            "admin retirement removes active membership"
        );
        assertTrue(
            distributor.assetDistributionHash(address(token)) != beforeHash,
            "admin retirement changes hash"
        );
    }

    // given an active asset with a configured route
    //   when the selected config operator disables it
    //     [X] the route is cleared for future receipts
    // Scenarios: DAR-A02
    function test_givenActiveAsset_whenDisabled_clearsRoute()
        public
        givenAliceConfiguredAsRecipient
    {
        bytes32 beforeHash = distributor.assetDistributionHash(address(token));
        IRevenueDistributor.AssetRoute[] memory emptyRoutes = new IRevenueDistributor.AssetRoute[](
            0
        );
        bytes32 expectedHash = keccak256(
            abi.encode(
                IRevenueDistributor.AssetState.Retired,
                uint16(0),
                emptyRoutes,
                distributor.yieldRecipient()
            )
        );
        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionDisabled(address(token));
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory routes) = distributor
            .getAssetDistribution(address(token));
        assertEq(repurchaseBps, 0, "retirement clears repurchase share");
        assertEq(routes.length, 0, "retirement clears routes");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "asset remains managed as retired"
        );
        assertEq(distributor.getActiveAssetCount(), 0, "retired asset leaves active set");
        assertEq(distributor.getActiveAssets().length, 0, "active enumeration is empty");
        assertTrue(
            distributor.assetDistributionHash(address(token)) != beforeHash,
            "route hash reflects retirement"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            expectedHash,
            "retired hash matches independent model"
        );
    }

    // Scenarios: DAR-A03
    function test_givenAnyLifecycleAndAssetState_whenUnauthorizedCallerDisables_reverts(
        address caller_,
        uint8 assetKind_,
        bool disable_,
        bool deactivate_
    ) public {
        vm.assume(caller_ != admin && caller_ != address(configTimelock));
        address asset = _prepareAssetKind(assetKind_);
        IRevenueDistributor.AssetState stateBefore = distributor.assetState(asset);
        bytes32 hashBefore = distributor.assetDistributionHash(asset);
        uint256 activeCountBefore = distributor.getActiveAssetCount();
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
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        distributor.disableAssetRoutes(asset);

        assertEq(
            uint8(distributor.assetState(asset)),
            uint8(stateBefore),
            "unauthorized call preserves asset state"
        );
        assertEq(
            distributor.assetDistributionHash(asset),
            hashBefore,
            "unauthorized call preserves route hash"
        );
        assertEq(
            distributor.getActiveAssetCount(),
            activeCountBefore,
            "unauthorized call preserves membership"
        );
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized call emits no event");
    }

    // Scenarios: DAR-A03
    function test_givenSeededUnauthorizedIdentities_whenAssetDisabled_reverts()
        public
        givenAliceConfiguredAsRecipient
    {
        address[3] memory callers = [emergency, alice, bob];
        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    callers[i]
                )
            );
            vm.prank(callers[i]);
            distributor.disableAssetRoutes(address(token));
        }
        assertEq(
            distributor.getActiveAssetCount(),
            1,
            "seeded unauthorized callers preserve active membership"
        );
    }

    // given an active asset
    //   when an unauthorized caller disables its routes
    //     [X] the call reverts and the asset remains active
    // Scenarios: DAR-A03
    function test_givenActiveAsset_whenUnauthorizedCallerDisables_reverts(
        address caller_
    ) public givenAliceConfiguredAsRecipient {
        vm.assume(caller_ != address(configTimelock));
        vm.assume(caller_ != admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        distributor.disableAssetRoutes(address(token));
        assertEq(distributor.getActiveAssetCount(), 1, "unauthorized call leaves asset active");
    }

    // given the distributor is locally disabled
    //   when the selected config operator disables an active asset's routes
    //     [X] the call reverts
    // Scenarios: DAR-L01
    function test_givenDisabled_whenOperatorDisablesAsset_reverts()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.prank(admin);
        distributor.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
    }

    // Scenarios: DAR-L01
    function test_givenDisabled_whenPermittedCallerDisablesAnyAsset_reverts(
        uint8 assetKind_,
        bool adminCalls_
    ) public {
        address asset = _prepareAssetKind(assetKind_);
        IRevenueDistributor.AssetState stateBefore = distributor.assetState(asset);
        bytes32 hashBefore = distributor.assetDistributionHash(asset);
        uint256 activeCountBefore = distributor.getActiveAssetCount();
        vm.prank(admin);
        distributor.disable("");

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.disableAssetRoutes(asset);

        assertEq(
            uint8(distributor.assetState(asset)),
            uint8(stateBefore),
            "disabled call preserves asset state"
        );
        assertEq(
            distributor.assetDistributionHash(asset),
            hashBefore,
            "disabled call preserves route hash"
        );
        assertEq(
            distributor.getActiveAssetCount(),
            activeCountBefore,
            "disabled call preserves membership"
        );
        assertEq(vm.getRecordedLogs().length, 0, "disabled call emits no event");
    }

    // given the distributor was disabled and re-enabled with an active asset
    //   when the selected config operator disables its routes
    //     [X] the asset is retired
    function test_givenActiveAsset_givenReEnabled_whenOperatorDisables_succeeds()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.startPrank(admin);
        distributor.disable("");
        distributor.reEnable();
        vm.stopPrank();

        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "re-enabled distributor retires active asset"
        );
    }

    // given the distributor policy is Kernel-inactive
    //   when the selected config operator disables an active asset's routes
    //     [X] the call reverts
    // Scenarios: DAR-L02
    function test_givenPolicyInactive_whenOperatorDisablesAsset_reverts()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
    }

    // Scenarios: DAR-L02
    function test_givenPolicyInactive_whenPermittedCallerDisablesAnyAsset_reverts(
        uint8 assetKind_,
        bool adminCalls_
    ) public {
        address asset = _prepareAssetKind(assetKind_);
        IRevenueDistributor.AssetState stateBefore = distributor.assetState(asset);
        bytes32 hashBefore = distributor.assetDistributionHash(asset);
        uint256 activeCountBefore = distributor.getActiveAssetCount();
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.disableAssetRoutes(asset);

        assertEq(
            uint8(distributor.assetState(asset)),
            uint8(stateBefore),
            "inactive call preserves asset state"
        );
        assertEq(
            distributor.assetDistributionHash(asset),
            hashBefore,
            "inactive call preserves route hash"
        );
        assertEq(
            distributor.getActiveAssetCount(),
            activeCountBefore,
            "inactive call preserves membership"
        );
        assertEq(vm.getRecordedLogs().length, 0, "inactive call emits no event");
    }

    // Scenarios: DAR-L03
    function test_givenPolicyInactiveAndDisabled_whenAssetDisabled_revertsNotEnabledFirst()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.startPrank(admin);
        distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.stopPrank();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
    }

    // given the distributor policy was deactivated and reactivated with an active asset
    //   when the selected config operator disables its routes
    //     [X] the asset is retired
    function test_givenActiveAsset_givenPolicyReactivated_whenOperatorDisables_succeeds()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        vm.stopPrank();

        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "reactivated policy retires active asset"
        );
    }

    // given an asset that has never been listed
    //   when the selected config operator tries to disable it
    //     [X] the call reverts and the asset remains unlisted
    // Scenarios: DAR-I01
    function test_givenNeverListedAsset_whenDisabled_reverts() public {
        vm.prank(address(configTimelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                address(token)
            )
        );
        distributor.disableAssetRoutes(address(token));
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "absent asset stays unlisted"
        );
    }

    // Scenarios: DAR-I01
    function test_givenNeverListedAddress_whenPermittedCallerDisables_reverts(
        address asset_,
        bool adminCalls_
    ) public {
        vm.assume(asset_.code.length == 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                asset_
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.disableAssetRoutes(asset_);

        assertEq(
            uint8(distributor.assetState(asset_)),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "never-listed address remains unlisted"
        );
        assertEq(vm.getRecordedLogs().length, 0, "failed disable emits no event");
    }

    // given an asset that has already been retired
    //   when the selected config operator disables it again
    //     [X] the call reverts and retirement remains in force
    // Scenarios: DAR-I02
    function test_givenRetiredAsset_whenDisabledAgain_reverts()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        vm.prank(address(configTimelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                address(token)
            )
        );
        distributor.disableAssetRoutes(address(token));
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "asset remains retired"
        );
    }

    // Scenarios: DAR-I02
    function test_givenRetiredAssetWithPendingBuckets_whenPermittedCallerDisablesAgain_reverts(
        bool adminCalls_
    ) public givenAliceConfiguredAsRecipient {
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
        distributor.seedPendingForTest(address(token), alice, 10, 20, 30);
        token.mint(address(distributor), 60);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                address(token)
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        _assertPendingPayouts(address(token), alice, 10, 20, 30);
        assertEq(token.balanceOf(address(distributor)), 60, "retired custody is unchanged");
        assertTrue(
            distributor.pendingAssetMemberForTest(address(token)),
            "retired pending asset remains indexed"
        );
        assertTrue(
            distributor.pendingRouteMemberForTest(address(token), alice),
            "retired route recipient remains indexed"
        );
        assertEq(vm.getRecordedLogs().length, 0, "failed repeated disable emits no event");
    }

    // Scenarios: DAR-P04
    function test_givenMultipleActiveAssets_whenOneDisabled_preservesOtherMembership() public {
        MockERC20 otherToken = new MockERC20("Other Revenue", "OREV", 18);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.startPrank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.setAssetRoutes(address(otherToken), 0, routes);
        distributor.disableAssetRoutes(address(token));
        vm.stopPrank();

        assertEq(distributor.getActiveAssetCount(), 1, "one active asset remains");
        assertEq(distributor.getActiveAssetAt(0), address(otherToken), "other asset stays active");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Retired),
            "target asset is retired"
        );
        assertEq(
            uint8(distributor.assetState(address(otherToken))),
            uint8(IRevenueDistributor.AssetState.Active),
            "other asset remains active"
        );
    }

    // Scenarios: DAR-P04
    function test_givenThreeActiveAssets_whenAnyPositionDisabled_preservesOtherAssets(
        uint8 targetIndex_,
        uint8 pendingMask_,
        bool adminCalls_
    ) public {
        targetIndex_ = uint8(bound(targetIndex_, 0, 2));
        pendingMask_ = uint8(bound(pendingMask_, 0, 7));
        MockERC20 secondToken = new MockERC20("Second Revenue", "REV2", 18);
        MockERC20 thirdToken = new MockERC20("Third Revenue", "REV3", 18);
        address[3] memory assets = [address(token), address(secondToken), address(thirdToken)];
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.startPrank(address(configTimelock));
        for (uint256 i; i < assets.length; ++i) {
            distributor.setAssetRoutes(assets[i], 0, routes);
        }
        vm.stopPrank();
        address target = assets[targetIndex_];
        uint256 routeAmount = pendingMask_ & 1 == 0 ? 0 : 11;
        uint256 yieldAmount = pendingMask_ & 2 == 0 ? 0 : 22;
        uint256 treasuryAmount = pendingMask_ & 4 == 0 ? 0 : 33;
        distributor.seedPendingForTest(target, alice, routeAmount, yieldAmount, treasuryAmount);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionDisabled(target);
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.disableAssetRoutes(target);

        address[] memory remaining = distributor.getActiveAssets();
        assertEq(remaining.length, 2, "exactly two active assets remain");
        for (uint256 i; i < assets.length; ++i) {
            if (i == targetIndex_) continue;
            assertTrue(_contains(remaining, assets[i]), "non-target asset remains active");
        }
        assertEq(
            uint8(distributor.assetState(target)),
            uint8(IRevenueDistributor.AssetState.Retired),
            "selected position is retired"
        );
        _assertPendingPayouts(target, alice, routeAmount, yieldAmount, treasuryAmount);
    }

    // given an active asset with a failed configured-recipient payout
    //   when the selected config operator disables the asset
    //     [X] the old route is cleared but the recipient remains owed and discoverable
    // Scenarios: DAR-P01
    function test_givenPendingConfiguredPayout_whenDisabled_preservesLiability()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 100);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, alice),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();

        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        assertEq(distributor.pendingPayout(address(token), alice), 33, "recipient remains owed");
        address[] memory pending = distributor.getPendingPayoutRecipients(address(token));
        assertEq(pending.length, 1, "one recipient remains discoverable");
        assertEq(pending[0], alice, "retired recipient remains listed");
        assertEq(token.balanceOf(address(distributor)), 33, "reserved payout stays in custody");
        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory routes) = distributor
            .getAssetDistribution(address(token));
        assertEq(repurchaseBps, 0, "retirement clears repurchase share");
        assertEq(routes.length, 0, "retirement clears configured route");
    }

    // Scenarios: DAR-P01
    function test_givenAnyPendingBuckets_whenPermittedCallerDisables_preservesEveryLiability(
        uint8 pendingMask_,
        uint96 route_,
        uint96 yield_,
        uint96 treasury_,
        bool adminCalls_
    ) public {
        pendingMask_ = uint8(bound(pendingMask_, 1, 7));
        route_ = uint96(bound(route_, 1, type(uint96).max));
        yield_ = uint96(bound(yield_, 1, type(uint96).max));
        treasury_ = uint96(bound(treasury_, 1, type(uint96).max));
        uint256 routeAmount = pendingMask_ & 1 == 0 ? 0 : route_;
        uint256 yieldAmount = pendingMask_ & 2 == 0 ? 0 : yield_;
        uint256 treasuryAmount = pendingMask_ & 4 == 0 ? 0 : treasury_;
        uint256 total = routeAmount + yieldAmount + treasuryAmount;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 2_500});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.seedPendingForTest(
            address(token),
            alice,
            routeAmount,
            yieldAmount,
            treasuryAmount
        );
        token.mint(address(distributor), total);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionDisabled(address(token));
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        _assertPendingPayouts(address(token), alice, routeAmount, yieldAmount, treasuryAmount);
        assertEq(
            token.balanceOf(address(distributor)),
            total,
            "retirement preserves pending custody"
        );
        assertTrue(
            distributor.pendingAssetMemberForTest(address(token)),
            "pending asset remains indexed"
        );
        assertEq(
            distributor.pendingRouteMemberForTest(address(token), alice),
            routeAmount != 0,
            "route recipient membership matches retained debt"
        );
        assertEq(distributor.getActiveAssetCount(), 0, "retired asset leaves active set");
        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory storedRoutes) = distributor
            .getAssetDistribution(address(token));
        assertEq(repurchaseBps, 0, "retirement clears repurchase share");
        assertEq(storedRoutes.length, 0, "retirement clears future configured routes");
    }

    function _prepareAssetKind(uint8 assetKind_) internal returns (address asset) {
        assetKind_ = uint8(bound(assetKind_, 0, 4));
        if (assetKind_ == 0) return address(0);
        if (assetKind_ == 1) return alice;
        if (assetKind_ == 2) return address(new MockERC20("Never Listed", "NONE", 18));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 2_500});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        if (assetKind_ == 4) {
            vm.prank(address(configTimelock));
            distributor.disableAssetRoutes(address(token));
        }
        return address(token);
    }

    function _contains(address[] memory values_, address value_) internal pure returns (bool) {
        for (uint256 i; i < values_.length; ++i) {
            if (values_[i] == value_) return true;
        }
        return false;
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
