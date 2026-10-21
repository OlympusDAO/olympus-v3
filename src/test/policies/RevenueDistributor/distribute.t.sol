// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Scenario amounts stay inline; bounded loops/casts intentionally exercise allocation matrices.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {PendingPayoutCallbackObserver} from "./fixtures/PendingPayoutCallbackObserver.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";

contract RevenueDistributorDistributeTest is RevenueDistributorTest {
    // given the route names a future Treasury as a configured recipient
    //   given that Treasury becomes the current module
    //     when new receipts are distributed before the route is updated
    //       [X] no funds are reserved or transferred
    //       [X] updating the route permits distribution of those receipts
    // Scenarios: DIST-P05
    function test_givenConfiguredRecipientBecomesTreasury_givenNewReceipts_reverts() public {
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(newTreasury), bps: 5_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        token.mint(address(distributor), 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(newTreasury)
            )
        );
        distributor.distribute(address(token));

        assertEq(token.balanceOf(address(distributor)), 100, "new receipts remain unallocated");
        assertEq(token.balanceOf(address(newTreasury)), 0, "Treasury receives no transfer");
        assertEq(
            distributor.pendingPayout(address(token), address(newTreasury)),
            0,
            "no payout is reserved"
        );

        routes[0].recipient = alice;
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.distribute(address(token));

        assertEq(token.balanceOf(alice), 50, "updated recipient receives its share");
        assertEq(token.balanceOf(address(newTreasury)), 50, "current Treasury receives remainder");
        assertEq(token.balanceOf(address(distributor)), 0, "updated route settles the receipts");
    }

    // given the route names a future Treasury as its second configured recipient
    //   given that Treasury becomes the current module
    //     when new receipts are distributed
    //       [X] all reservations and transfers roll back
    // Scenarios: DIST-P05
    function test_givenSecondConfiguredRecipientBecomesTreasury_reverts() public {
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_000});
        routes[1] = IRevenueDistributor.AssetRoute({recipient: address(newTreasury), bps: 3_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        token.mint(address(distributor), 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(newTreasury)
            )
        );
        distributor.distribute(address(token));

        assertEq(token.balanceOf(address(distributor)), 100, "all receipts remain in custody");
        assertEq(token.balanceOf(alice), 0, "first recipient receives no transfer");
        assertEq(token.balanceOf(address(newTreasury)), 0, "Treasury receives no transfer");
        assertEq(
            distributor.pendingPayout(address(token), alice),
            0,
            "first reservation rolls back"
        );
        assertEq(
            distributor.pendingPayout(address(token), address(newTreasury)),
            0,
            "Treasury reservation rolls back"
        );
        assertEq(distributor.getPendingPayoutAssets().length, 0, "no pending asset is recorded");
    }

    // given a configured recipient and the old Treasury both have reserved shares
    //   given the configured recipient becomes the current Treasury
    //     when distribution is called without new receipts while transfers fail
    //       [X] both historical liabilities remain pending
    //       [X] a later successful distribution pays them in one transfer
    // Scenarios: DIST-P06
    function test_givenConfiguredRecipientBecomesTreasury_givenNoNewReceipts_paysPendingOnce(
        address caller_
    ) public {
        MockRevertingTransferToken revertingToken = new MockRevertingTransferToken(18);
        token = revertingToken;
        vm.label(address(token), "Revenue token with configurable transfer revert");
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(newTreasury), bps: 5_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        token.mint(address(distributor), 100);
        revertingToken.setTransferReverts(address(newTreasury), true);
        revertingToken.setTransferReverts(address(treasury), true);
        vm.prank(caller_);
        distributor.distribute(address(token));
        revertingToken.setTransferReverts(address(newTreasury), false);
        revertingToken.setTransferReverts(address(treasury), false);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));

        revertingToken.setTransferReverts(address(newTreasury), true);
        vm.prank(caller_);
        distributor.distribute(address(token));
        assertEq(token.balanceOf(address(newTreasury)), 0, "failed retry transfers nothing");
        assertEq(
            distributor.getPendingPayoutRecipients(address(token)).length,
            1,
            "overlapping liabilities enumerate one recipient"
        );
        assertEq(
            distributor.pendingPayout(address(token), address(newTreasury)),
            100,
            "both historical liabilities are owed before retry"
        );

        revertingToken.setTransferReverts(address(newTreasury), false);
        revertingToken.setRevertOnTransferCall(0);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(newTreasury), 100);
        vm.prank(caller_);
        distributor.distribute(address(token));
        assertEq(token.balanceOf(address(newTreasury)), 100, "distribution pays both shares once");
        assertEq(
            revertingToken.transferCallCount(),
            1,
            "overlapping liabilities use one transfer attempt"
        );
        assertEq(token.balanceOf(address(distributor)), 0, "distribution pays reserved custody");
        assertEq(
            distributor.pendingPayout(address(token), address(newTreasury)),
            0,
            "both liabilities are cleared"
        );
        assertEq(distributor.getPendingPayoutAssets().length, 0, "pending asset is removed");
    }

    // given a route change queued by admin or revenue distributor admin and a token with a callback
    //   when the callback executes the queued change during distribution
    //     [X] the in-flight distribution keeps its original recipient allocation
    // Scenarios: DIST-C01
    function testFuzz_givenMaturedRouteChange_whenTokenCallsTimelockDuringDistribution_thenRouteStaysFixed(
        bool useRevenueDistributorAdmin_
    ) public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        address nextRecipient = makeAddr("nextRecipient");
        IRevenueDistributor.AssetRoute[] memory oldRoutes = new IRevenueDistributor.AssetRoute[](2);
        oldRoutes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_000});
        oldRoutes[1] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 3_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(callbackToken), 0, oldRoutes);

        IRevenueDistributor.AssetRoute[] memory newRoutes = new IRevenueDistributor.AssetRoute[](2);
        newRoutes[0] = IRevenueDistributor.AssetRoute({recipient: nextRecipient, bps: 1_000});
        newRoutes[1] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 7_000});
        if (useRevenueDistributorAdmin_) {
            vm.prank(admin);
            rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, bob);
        }
        vm.prank(useRevenueDistributorAdmin_ ? bob : admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(callbackToken), 0, newRoutes);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        callbackToken.mint(address(distributor), 10);
        callbackToken.setCallbackFrom(
            address(distributor),
            address(configTimelock),
            abi.encodeCall(configTimelock.executeQueuedAction, (actionId))
        );

        distributor.distribute(address(callbackToken));

        assertFalse(callbackToken.callbackSucceeded(), "route change cannot execute mid-payout");
        assertEq(
            callbackToken.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "configuration sees the payout guard"
        );
        assertEq(callbackToken.balanceOf(alice), 3, "first old recipient paid once");
        assertEq(callbackToken.balanceOf(bob), 3, "second old recipient paid once");
        assertEq(callbackToken.balanceOf(nextRecipient), 0, "new route does not mix into payout");
        assertEq(callbackToken.balanceOf(address(treasury)), 4, "old route remainder paid");

        configTimelock.executeQueuedAction(actionId);
        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory activeRoute) = distributor
            .getAssetDistribution(address(callbackToken));
        assertEq(repurchaseBps, 0, "queued route retains zero repurchase share");
        assertEq(activeRoute[0].recipient, nextRecipient, "queued route remains executable");
    }

    // given a token whose transfer callback calls distribute again
    //   when distribution runs
    //     [X] the nested call fails and each share is paid once
    // Scenarios: DIST-C01
    function test_givenCallbackToken_nestedDistributionFailsAndPaysOnce() public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_333});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(callbackToken), 0, routes);
        callbackToken.mint(address(distributor), 10);
        callbackToken.setCallbackFrom(
            address(distributor),
            address(distributor),
            abi.encodeCall(distributor.distribute, (address(callbackToken)))
        );

        distributor.distribute(address(callbackToken));

        assertFalse(callbackToken.callbackSucceeded(), "nested distribution fails");
        assertEq(
            callbackToken.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "nested distribution hits guard"
        );
        // 10 token units * 3333 / 10000 rounds down to 3; TRSRY receives the other 7.
        assertEq(callbackToken.balanceOf(alice), 3, "ordinary recipient paid once");
        assertEq(callbackToken.balanceOf(address(treasury)), 7, "Treasury paid once");
        assertEq(callbackToken.balanceOf(address(distributor)), 0, "receipt settled once");
    }

    // given the token propagates a reentrant callback failure
    //   when receipts are distributed
    //     [X] each failed transfer remains pending
    // Scenarios: DIST-C02, DIST-T09
    function test_givenCallbackFailureBubbles_defersEachShare() public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_333});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(callbackToken), 0, routes);
        callbackToken.mint(address(distributor), 10);
        callbackToken.setCallbackFrom(
            address(distributor),
            address(distributor),
            abi.encodeCall(distributor.distribute, (address(callbackToken)))
        );
        callbackToken.setBubbleCallbackFailure(true);

        distributor.distribute(address(callbackToken));
        assertEq(
            callbackToken.balanceOf(address(distributor)),
            10,
            "failed transfers remain in custody"
        );
        assertEq(
            distributor.pendingPayout(address(callbackToken), alice),
            3,
            "configured share remains owed"
        );
        assertEq(
            distributor.pendingPayout(address(callbackToken), address(treasury)),
            7,
            "Treasury share remains owed"
        );
    }

    // given a managed receipt arrived before Treasury was upgraded
    //   when distribution executes after the upgrade
    //     [X] the residual share reaches the current Treasury
    // Scenarios: DIST-P07
    function test_givenBalanceReceivedBeforeTreasuryUpgrade_paysNewTreasury()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));

        distributor.distribute(address(token));

        // 10 token units * 3333 / 10000 rounds down to 3; new TRSRY gets the remaining 7.
        assertEq(token.balanceOf(alice), 3, "ordinary recipient keeps its configured share");
        assertEq(token.balanceOf(address(treasury)), 0, "former Treasury gets no remainder");
        assertEq(token.balanceOf(address(newTreasury)), 7, "new Treasury gets remainder");
        assertEq(token.balanceOf(address(distributor)), 0, "receipt is fully settled");
    }

    // given Alice is configured for 3,333 basis points
    //   given the distributor holds ten token units
    //     when receipts are distributed
    //       [X] Alice and Treasury each have a payout event with the transferred amount
    // Scenarios: DIST-P02
    function test_givenAliceConfiguredAsRecipient_emitsEachRecipientPayout()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), alice, 3);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(treasury), 7);

        distributor.distribute(address(token));
    }

    // given the yield recipient accepts this vault token
    //   given the route assigns 20% to repurchase and names no configured recipients
    //     when receipts are distributed
    //       [X] yield recipient and Treasury have separate payout events
    // Scenarios: DIST-P08
    function test_givenYieldRecipientVaultEnabled_emitsRepurchaseAndTreasury() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        distributor.setAssetRoutes(address(token), 2_000, routes);
        vm.stopPrank();
        token.mint(address(distributor), 10);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(recipient), 2);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(treasury), 8);

        distributor.distribute(address(token));
        assertEq(token.balanceOf(address(recipient)), 2, "yield recipient receives enabled share");
        assertEq(token.balanceOf(address(treasury)), 8, "Treasury receives remainder");
    }

    // given a managed route with a 33.33% recipient
    //   when a ten-unit balance is distributed
    //     [X] it transfers three units to the recipient
    //     [X] it transfers all seven remaining units to Treasury
    // Scenarios: DIST-P02
    function test_givenAliceConfiguredAsRecipient_whenBalanceHasRoundingDust()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);

        vm.prank(bob);
        distributor.distribute(address(token));

        // 10 token units * 3333 / 10000 rounds down to 3; Treasury receives 7.
        assertEq(token.balanceOf(alice), 3, "configured recipient receives floor-rounded share");
        assertEq(token.balanceOf(address(treasury)), 7, "Treasury receives exact remainder");
        assertEq(token.balanceOf(address(distributor)), 0, "settlement leaves no managed balance");
    }

    // given Alice is configured for 3,333 basis points
    //   when 100 tokens are distributed
    //     [X] gas is recorded
    //     [X] Alice receives 33.33 tokens
    //     [X] Treasury receives the 66.67-token remainder
    function test_givenAliceConfiguredAsRecipient_given100TokenBalance_recordsGasSnapshot()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 100e18);

        vm.startSnapshotGas("RevenueDistributor.distribute.standard");
        distributor.distribute(address(token));
        uint256 gasUsed = vm.stopSnapshotGas();

        assertGt(gasUsed, 0, "distribution gas is recorded");
        assertEq(
            token.balanceOf(alice),
            33_330_000_000_000_000_000,
            "configured recipient receives share"
        );
        assertEq(
            token.balanceOf(address(treasury)),
            66_670_000_000_000_000_000,
            "Treasury receives remainder"
        );
    }

    // given the distributor is disabled with a managed route
    //   when a balance arrives and settlement is attempted
    //     [X] it rejects settlement and leaves the full balance in custody
    // Scenarios: DIST-L01
    function test_givenDisabled_whenManagedBalanceArrives_reverts()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.prank(admin);
        distributor.disable("");
        token.mint(address(distributor), 11);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        distributor.distribute(address(token));

        assertEq(token.balanceOf(address(distributor)), 11, "disabled distributor retains balance");
        assertEq(token.balanceOf(address(treasury)), 0, "disabled distributor sends nothing");
    }

    // given the distributor is Kernel-inactive with a managed route
    //   when a balance arrives and settlement is attempted
    //     [X] it rejects settlement and leaves the full balance in custody
    // Scenarios: DIST-L02
    function test_givenKernelInactive_whenManagedBalanceArrives_reverts()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        token.mint(address(distributor), 11);

        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        distributor.distribute(address(token));

        assertEq(token.balanceOf(address(distributor)), 11, "inactive distributor retains balance");
        assertEq(token.balanceOf(address(treasury)), 0, "inactive distributor sends nothing");
    }

    // given a configured recipient transfer fails
    //  when anyone distributes a managed token
    //   then Treasury receives its share and the configured recipient remains owed
    // Scenarios: DIST-T01
    function test_givenRecipientTransferFails_keepsOnlyRecipientPending()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 100);
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, alice, 33),
            abi.encode(false)
        );

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(address(token), alice, 33);
        distributor.distribute(address(token));
        assertEq(token.balanceOf(address(distributor)), 33, "failed share remains in custody");
        assertEq(token.balanceOf(alice), 0, "recipient received nothing");
        assertEq(token.balanceOf(address(treasury)), 67, "Treasury receives its share");
        assertEq(
            distributor.pendingPayout(address(token), alice),
            33,
            "configured share remains owed"
        );
        address[] memory assets = distributor.getPendingPayoutAssets();
        assertEq(assets.length, 1, "pending asset is discoverable");
        assertEq(assets[0], address(token), "pending token address");
        address[] memory recipients = distributor.getPendingPayoutRecipients(address(token));
        assertEq(recipients.length, 1, "only blocked recipient remains");
        assertEq(recipients[0], alice, "blocked recipient is discoverable");
    }

    // given the configured recipient accepts its allocation
    //   given the token transfer to Treasury reverts
    //     when receipts are distributed
    //       [X] the configured recipient is paid and only Treasury's residual remains pending
    // Scenarios: DIST-T02
    function test_givenTreasuryBlacklisted_retainsTreasuryShare()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 100);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, address(treasury)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );

        distributor.distribute(address(token));
        assertEq(token.balanceOf(address(distributor)), 67, "Treasury share remains managed");
        assertEq(token.balanceOf(alice), 33, "configured recipient receives its share");
        assertEq(token.balanceOf(address(treasury)), 0, "Treasury receives nothing");
        assertEq(
            distributor.pendingPayout(address(token), address(treasury)),
            67,
            "Treasury is owed"
        );

        vm.clearMockedCalls();
        distributor.transferPendingPayout(address(token), address(treasury));
        assertEq(token.balanceOf(address(distributor)), 0, "later retry empties custody");
        assertEq(token.balanceOf(alice), 33, "configured recipient is not paid twice");
        assertEq(token.balanceOf(address(treasury)), 67, "later retry pays Treasury");
    }

    // given a managed token has no balance
    //  when anyone distributes it
    //   then no recipient transfer occurs
    // Scenarios: DIST-P01
    function test_givenZeroBalance_succeedsWithoutTransfer()
        public
        givenAliceConfiguredAsRecipient
    {
        vm.prank(bob);
        distributor.distribute(address(token));
        assertEq(token.balanceOf(alice), 0, "recipient balance remains zero");
        assertEq(token.balanceOf(address(treasury)), 0, "Treasury balance remains zero");
    }

    // given a managed route with one recipient
    //  when a fuzzed nonzero balance is distributed
    //   then the recipient receives the floor and Treasury receives all remaining units
    // Scenarios: DIST-P02, DIST-P08
    function test_givenAliceConfiguredAsRecipient_whenBalanceIsFuzzed(
        uint256 balance_
    ) public givenAliceConfiguredAsRecipient {
        vm.assume(balance_ != 0);
        token.mint(address(distributor), balance_);
        vm.prank(bob);
        distributor.distribute(address(token));

        // Full precision: balance (token units) * 3333 BPS / 10000 BPS = token units, rounded down.
        uint256 expectedRecipient = FullMath.mulDiv(balance_, 3_333, 10_000);
        assertEq(token.balanceOf(alice), expectedRecipient, "recipient amount rounds down");
        assertEq(
            token.balanceOf(address(treasury)),
            uint256(balance_) - expectedRecipient,
            "Treasury gets exact residual"
        );
        assertEq(token.balanceOf(address(distributor)), 0, "custody is fully settled");
    }

    // given Alice is configured for 3,333 basis points
    //   when the maximum token balance is distributed
    //     [X] both allocations sum to the original balance without overflow
    // Scenarios: DIST-P02
    function test_givenAliceConfiguredAsRecipient_whenBalanceIsMaximum_preservesExactTotal()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), type(uint256).max);
        distributor.distribute(address(token));
        uint256 expectedRecipient = FullMath.mulDiv(type(uint256).max, 3_333, 10_000);
        assertEq(
            token.balanceOf(alice),
            expectedRecipient,
            "recipient gets floor-rounded maximum share"
        );
        assertEq(
            token.balanceOf(address(treasury)),
            type(uint256).max - expectedRecipient,
            "Treasury gets exact maximum residual"
        );
        assertEq(token.balanceOf(address(distributor)), 0, "maximum receipt leaves no custody");
    }

    // Scenarios: DIST-I01
    function test_givenAssetNotActive_whenDistributed_reverts(
        address caller_,
        uint8 assetKind_
    ) public {
        assetKind_ = uint8(bound(assetKind_, 0, 3));
        address asset;
        if (assetKind_ == 0) asset = address(0);
        if (assetKind_ == 1) asset = makeAddr("EOA asset");
        if (assetKind_ == 2) asset = address(token);
        if (assetKind_ == 3) {
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                0
            );
            vm.startPrank(admin);
            distributor.setAssetRoutes(address(token), 0, routes);
            distributor.disableAssetRoutes(address(token));
            vm.stopPrank();
            asset = address(token);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_AssetNotActive.selector,
                asset
            )
        );
        vm.prank(caller_);
        distributor.distribute(asset);
    }

    // Scenarios: DIST-I02
    function test_givenReservedDebtExceedsCustody_whenDistributed_reverts() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.seedPendingForTest(address(token), alice, 10, 20, 30);
        token.mint(address(distributor), 59);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InsufficientPayoutBalance.selector,
                address(token)
            )
        );
        distributor.distribute(address(token));

        _assertPendingPayouts(address(token), alice, 10, 20, 30);
        assertEq(token.balanceOf(address(distributor)), 59, "failed distribution keeps custody");
    }

    // Scenarios: DIST-P08
    function test_givenTreasuryOnlyRoute_whenBalanceDistributed_paysExactAmount(
        uint128 amount_,
        address caller_
    ) public {
        vm.assume(amount_ != 0);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        token.mint(address(distributor), amount_);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(treasury), amount_);
        vm.prank(caller_);
        distributor.distribute(address(token));

        assertEq(token.balanceOf(address(treasury)), amount_, "Treasury receives full receipt");
        assertEq(token.balanceOf(address(distributor)), 0, "distribution clears custody");
        assertEq(distributor.getPendingPayoutAssets().length, 0, "no debt remains indexed");
    }

    // Scenarios: DIST-I03
    function test_givenActiveAsset_whenBalanceQueryReverts_bubblesExactError() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        bytes memory errorData = abi.encodeWithSignature("BalanceQueryFailed()");
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.balanceOf.selector, address(distributor)),
            errorData
        );

        vm.expectRevert(errorData);
        distributor.distribute(address(token));

        assertEq(
            distributor.totalPendingForTest(address(token)),
            0,
            "failed query reserves no debt"
        );
    }

    // Scenarios: DIST-T03
    function test_givenTokenReportsTransferSuccessWithoutMovement_recordsApparentDelivery() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        token.mint(address(distributor), 10);
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, address(treasury), 10),
            abi.encode(true)
        );

        distributor.distribute(address(token));

        assertEq(token.balanceOf(address(treasury)), 0, "nonconforming token moves no balance");
        assertEq(token.balanceOf(address(distributor)), 10, "apparent delivery leaves custody");
        assertEq(
            distributor.totalPendingForTest(address(token)),
            0,
            "reported success clears debt"
        );
    }

    // Scenarios: DIST-T06
    function test_givenMultipleTransfersReturnFalse_defersEveryShare()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, alice, 3),
            abi.encode(false)
        );
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, address(treasury), 7),
            abi.encode(false)
        );

        distributor.distribute(address(token));

        _assertPendingPayouts(address(token), alice, 3, 0, 7);
        assertEq(token.balanceOf(address(distributor)), 10, "failed shares remain in custody");
        assertEq(
            distributor.getPendingPayoutRecipients(address(token)).length,
            2,
            "both debts remain enumerable"
        );
    }

    // Scenarios: DIST-I07
    function test_givenActiveAsset_whenBalanceQueryReturnsMalformedData_reverts() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.balanceOf.selector, address(distributor)),
            hex"01"
        );

        // Solidity's external-call decoder does not expose a stable selector for short returndata.
        vm.expectRevert();
        distributor.distribute(address(token));

        assertEq(
            distributor.totalPendingForTest(address(token)),
            0,
            "malformed query reserves no debt"
        );
    }

    // Scenarios: DIST-L01, DIST-L02
    function test_givenUnavailableDistributor_whenAnyCallerDistributes_revertsAndRollsBack(
        address caller_,
        bool disabled_
    ) public givenAliceConfiguredAsRecipient {
        distributor.seedPendingForTest(address(token), bob, 2, 3, 5);
        token.mint(address(distributor), 21);
        if (disabled_) {
            vm.prank(admin);
            distributor.disable("");
        } else {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        }

        vm.recordLogs();
        vm.expectRevert(
            disabled_
                ? IEnabler.NotEnabled.selector
                : IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
        );
        vm.prank(caller_);
        distributor.distribute(address(token));

        _assertPendingPayouts(address(token), bob, 2, 3, 5);
        assertEq(
            token.balanceOf(address(distributor)),
            21,
            "lifecycle rejection preserves custody"
        );
        assertEq(token.balanceOf(alice), 0, "lifecycle rejection pays no route recipient");
        assertEq(token.balanceOf(address(treasury)), 0, "lifecycle rejection pays no Treasury");
        assertEq(
            distributor.getPendingPayoutAssets().length,
            1,
            "lifecycle rejection preserves pending index"
        );
        assertEq(vm.getRecordedLogs().length, 0, "lifecycle rejection emits no event");
    }

    // Scenarios: DIST-P01
    function test_givenZeroBalance_whenAnyCallerDistributes_makesNoTokenCallOrEvent(
        address caller_
    ) public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(
            address(callbackToken),
            0,
            new IRevenueDistributor.AssetRoute[](0)
        );
        callbackToken.setCallbackFrom(
            address(distributor),
            address(distributor),
            abi.encodeCall(distributor.distribute, (address(callbackToken)))
        );

        vm.recordLogs();
        vm.prank(caller_);
        distributor.distribute(address(callbackToken));

        assertTrue(callbackToken.callbackEnabled(), "zero balance makes no transfer callback");
        assertEq(callbackToken.transferCallCount(), 0, "zero balance makes no token transfer call");
        assertEq(
            distributor.totalPendingForTest(address(callbackToken)),
            0,
            "zero balance creates no debt"
        );
        assertEq(vm.getRecordedLogs().length, 0, "zero balance emits no event");
    }

    // Scenarios: DIST-P02, DIST-P08
    function test_givenAnyValidRouteTopology_whenReceiptsDistributed_conservesExactAmount(
        uint8 topology_,
        uint16 firstBps_,
        uint16 secondBps_,
        uint16 thirdBps_,
        uint256 amount_,
        address caller_
    ) public {
        topology_ = uint8(bound(topology_, 0, 4));
        vm.assume(amount_ != 0);
        uint16 repurchaseBps;
        uint16 aliceBps;
        uint16 bobBps;
        if (topology_ == 1) {
            repurchaseBps = uint16(bound(firstBps_, 1, 10_000));
        } else if (topology_ == 2) {
            aliceBps = uint16(bound(firstBps_, 1, 10_000));
        } else if (topology_ == 3) {
            aliceBps = uint16(bound(firstBps_, 1, 9_999));
            bobBps = uint16(bound(secondBps_, 1, 10_000 - aliceBps));
        } else if (topology_ == 4) {
            repurchaseBps = uint16(bound(firstBps_, 1, 9_998));
            aliceBps = uint16(bound(secondBps_, 1, 9_999 - repurchaseBps));
            // Mixed routes may intentionally allocate less than 100%; Treasury receives the rest.
            bobBps = uint16(bound(thirdBps_, 1, 10_000 - repurchaseBps - aliceBps));
        }
        uint256 routeLength = topology_ < 2 ? 0 : (topology_ == 2 ? 1 : 2);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
            routeLength
        );
        if (routeLength != 0)
            routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: aliceBps});
        if (routeLength == 2)
            routes[1] = IRevenueDistributor.AssetRoute({recipient: bob, bps: bobBps});
        MockYieldRepurchaseRecipient yieldRecipient;
        if (repurchaseBps != 0) {
            yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
            yieldRecipient.setVaultConfig(address(token), address(token), true);
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
            vm.prank(address(configTimelock));
            distributor.setYieldRecipient(address(yieldRecipient));
        }
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), repurchaseBps, routes);
        MockERC20 other = new MockERC20("Other Revenue", "OREV", 18);
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(other), 0, new IRevenueDistributor.AssetRoute[](0));
        other.mint(address(distributor), 77);
        token.mint(address(distributor), amount_);

        vm.recordLogs();
        vm.prank(caller_);
        distributor.distribute(address(token));

        uint256 expectedYield = FullMath.mulDiv(amount_, repurchaseBps, 10_000);
        uint256 expectedAlice = FullMath.mulDiv(amount_, aliceBps, 10_000);
        uint256 expectedBob = FullMath.mulDiv(amount_, bobBps, 10_000);
        uint256 expectedTreasury = amount_ - expectedYield - expectedAlice - expectedBob;
        assertEq(
            token.balanceOf(address(yieldRecipient)),
            expectedYield,
            "yield share rounds down exactly"
        );
        assertEq(
            token.balanceOf(alice),
            expectedAlice,
            "first configured share rounds down exactly"
        );
        assertEq(token.balanceOf(bob), expectedBob, "second configured share rounds down exactly");
        assertEq(
            token.balanceOf(address(treasury)),
            expectedTreasury,
            "Treasury receives exact residual"
        );
        assertEq(token.balanceOf(address(distributor)), 0, "selected asset custody clears");
        assertEq(
            distributor.totalPendingForTest(address(token)),
            0,
            "selected asset reserve clears"
        );
        assertEq(
            distributor.getPendingPayoutAssets().length,
            0,
            "selected asset leaves no pending index"
        );
        assertEq(other.balanceOf(address(distributor)), 77, "other managed asset remains isolated");
        assertEq(
            _countPayoutLogs(vm.getRecordedLogs()),
            _nonzeroShareCount(expectedYield, expectedAlice, expectedBob, expectedTreasury),
            "each nonzero share emits once"
        );
    }

    // Scenarios: DIST-T01
    function test_givenOneTransferReturnsFalse_whenAnyCallerDistributes_defersOnlySelectedClass(
        uint8 failedClass_,
        address caller_
    ) public {
        _assertSingleTransferFailure(failedClass_, caller_, false);
    }

    // Scenarios: DIST-P02
    function test_givenOneConfiguredRecipient_whenBoundaryBalancesDistributed_conservesExactAmount(
        address caller_
    ) public {
        uint256[8] memory amounts = [uint256(0), 1, 3, 4, 9_999, 10_000, 10_001, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            MockERC20 boundaryToken = new MockERC20("Boundary Revenue", "BREV", 18);
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                1
            );
            routes[0] = IRevenueDistributor.AssetRoute({
                recipient: address(uint160(100 + i)),
                bps: 3_333
            });
            vm.prank(address(configTimelock));
            distributor.setAssetRoutes(address(boundaryToken), 0, routes);
            boundaryToken.mint(address(distributor), amounts[i]);

            vm.prank(caller_);
            distributor.distribute(address(boundaryToken));

            uint256 expectedRecipient = FullMath.mulDiv(amounts[i], 3_333, 10_000);
            assertEq(
                boundaryToken.balanceOf(routes[0].recipient),
                expectedRecipient,
                "boundary recipient amount is exact"
            );
            assertEq(
                boundaryToken.balanceOf(address(treasury)),
                amounts[i] - expectedRecipient,
                "boundary Treasury residual is exact"
            );
            assertEq(boundaryToken.balanceOf(address(distributor)), 0, "boundary custody clears");
            assertEq(
                distributor.totalPendingForTest(address(boundaryToken)),
                0,
                "boundary reserve clears"
            );
        }
    }

    // Scenarios: DIST-T02
    function test_givenOneTransferReverts_whenAnyCallerDistributes_defersOnlySelectedClass(
        uint8 failedClass_,
        address caller_
    ) public {
        _assertSingleTransferFailure(failedClass_, caller_, true);
    }

    // Scenarios: DIST-P04
    function test_givenAnyExistingDebtSubset_whenZeroOrOneNewReceiptDistributed_allocatesOnlySurplus(
        uint8 debtMask_,
        bool addReceipt_,
        address caller_
    ) public {
        debtMask_ = uint8(bound(debtMask_, 1, 7));
        MockERC20 other = new MockERC20("Other Revenue", "OREV", 18);
        MockYieldRepurchaseRecipient yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        yieldRecipient.setVaultConfig(address(token), address(token), true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(yieldRecipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 3_333});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 2_000, routes);
        uint256 configured = debtMask_ & 1 == 0 ? 0 : 2;
        uint256 repurchase = debtMask_ & 2 == 0 ? 0 : 3;
        uint256 treasuryDebt = debtMask_ & 4 == 0 ? 0 : 5;
        uint256 reserved = configured + repurchase + treasuryDebt;
        distributor.seedPendingForTest(address(token), alice, configured, repurchase, treasuryDebt);
        distributor.seedPendingForTest(address(other), alice, 7, 11, 13);
        token.mint(address(distributor), reserved + (addReceipt_ ? 1 : 0));
        other.mint(address(distributor), 31);

        vm.prank(caller_);
        distributor.distribute(address(token));

        assertEq(
            distributor.pendingPayout(address(token), alice),
            configured,
            "removed fixed recipient remains owed"
        );
        assertEq(
            token.balanceOf(address(yieldRecipient)),
            repurchase,
            "current yield debt is retried"
        );
        assertEq(
            token.balanceOf(address(treasury)),
            treasuryDebt + (addReceipt_ ? 1 : 0),
            "Treasury gets debt and new dust"
        );
        assertEq(token.balanceOf(bob), 0, "one-unit receipt produces no configured share");
        assertEq(
            token.balanceOf(address(distributor)),
            configured,
            "only former fixed debt remains in custody"
        );
        assertEq(
            distributor.totalPendingForTest(address(token)),
            configured,
            "reserve equals former fixed debt"
        );
        _assertPendingPayouts(address(other), alice, 7, 11, 13);
        assertEq(other.balanceOf(address(distributor)), 31, "other asset custody is isolated");
    }

    // Scenarios: DIST-P05
    function test_givenConfiguredRecipientBecomesTreasury_whenAnyCallerDistributes_revertsAtomically(
        address caller_,
        bool invalidRecipientSecond_
    ) public {
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        uint256 routeLength = invalidRecipientSecond_ ? 2 : 1;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
            routeLength
        );
        if (invalidRecipientSecond_)
            routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_000});
        routes[routeLength - 1] = IRevenueDistributor.AssetRoute({
            recipient: address(newTreasury),
            bps: 3_000
        });
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        bytes32 routeHash = distributor.assetDistributionHash(address(token));
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        token.mint(address(distributor), 100);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(newTreasury)
            )
        );
        vm.prank(caller_);
        distributor.distribute(address(token));

        assertEq(
            token.balanceOf(address(distributor)),
            100,
            "invalid current Treasury leaves custody intact"
        );
        assertEq(token.balanceOf(alice), 0, "earlier configured transfer rolls back");
        assertEq(token.balanceOf(address(newTreasury)), 0, "invalid destination receives nothing");
        assertEq(distributor.totalPendingForTest(address(token)), 0, "all reservations roll back");
        assertEq(distributor.getPendingPayoutAssets().length, 0, "pending index rolls back");
        assertEq(
            distributor.assetDistributionHash(address(token)),
            routeHash,
            "route hash remains unchanged"
        );
        assertEq(vm.getRecordedLogs().length, 0, "reverted distribution commits no event");
    }

    // Scenarios: DIST-P07
    function test_givenReceiptsBeforeTreasuryUpgrade_whenAnyCallerDistributes_usesCurrentTreasury(
        address caller_
    ) public givenAliceConfiguredAsRecipient {
        bytes32 routeHash = distributor.assetDistributionHash(address(token));
        token.mint(address(distributor), 10);
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), alice, 3);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(newTreasury), 7);
        vm.prank(caller_);
        distributor.distribute(address(token));

        assertEq(
            distributor.treasury(),
            address(newTreasury),
            "treasury getter resolves replacement module"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            routeHash,
            "Treasury upgrade preserves route hash"
        );
        assertEq(
            distributor.getActiveAssetCount(),
            1,
            "Treasury upgrade preserves active membership"
        );
        assertEq(token.balanceOf(alice), 3, "configured recipient receives exact share");
        assertEq(token.balanceOf(address(treasury)), 0, "old Treasury receives nothing");
        assertEq(token.balanceOf(address(newTreasury)), 7, "current Treasury receives residual");
        assertEq(distributor.totalPendingForTest(address(token)), 0, "all pending buckets clear");
        assertEq(distributor.getPendingPayoutAssets().length, 0, "pending asset index clears");
        assertEq(
            distributor.getPendingPayoutRecipients(address(token)).length,
            0,
            "recipient index clears"
        );
    }

    // Scenarios: DIST-C01
    function test_givenCallbackFromAnyPayoutClass_whenAnyGuardedWriteAttempted_outerDistributionPaysOnce(
        uint8 payoutClass_,
        uint8 operation_,
        address caller_
    ) public {
        payoutClass_ = uint8(bound(payoutClass_, 0, 2));
        operation_ = uint8(bound(operation_, 0, 4));
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        MockYieldRepurchaseRecipient yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        yieldRecipient.setVaultConfig(address(callbackToken), address(callbackToken), true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(yieldRecipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(callbackToken), 2_000, routes);
        bytes memory callback;
        if (operation_ == 0) {
            callback = abi.encodeCall(distributor.distribute, (address(callbackToken)));
        } else if (operation_ == 1) {
            callback = abi.encodeCall(
                distributor.transferPendingPayout,
                (address(callbackToken), alice)
            );
        } else if (operation_ == 2) {
            callback = abi.encodeCall(
                distributor.setAssetRoutes,
                (address(callbackToken), uint16(0), new IRevenueDistributor.AssetRoute[](0))
            );
        } else if (operation_ == 3) {
            callback = abi.encodeCall(distributor.setYieldRecipient, (address(0)));
        } else {
            callback = abi.encodeCall(distributor.rescue, (address(callbackToken), bob));
        }
        address callbackRecipient = payoutClass_ == 0
            ? address(yieldRecipient)
            : (payoutClass_ == 1 ? alice : address(treasury));
        callbackToken.setCallbackFrom(address(distributor), address(distributor), callback);
        callbackToken.setCallbackTransferRecipient(callbackRecipient);
        callbackToken.mint(address(distributor), 100);

        vm.prank(caller_);
        distributor.distribute(address(callbackToken));

        assertFalse(callbackToken.callbackSucceeded(), "nested guarded write fails");
        assertEq(
            callbackToken.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "nested write hits reentrancy guard"
        );
        assertEq(
            callbackToken.balanceOf(address(yieldRecipient)),
            20,
            "yield recipient is paid once"
        );
        assertEq(callbackToken.balanceOf(alice), 30, "configured recipient is paid once");
        assertEq(callbackToken.balanceOf(address(treasury)), 50, "Treasury is paid once");
        assertEq(
            callbackToken.balanceOf(address(distributor)),
            0,
            "outer distribution settles custody once"
        );
        assertEq(
            distributor.totalPendingForTest(address(callbackToken)),
            0,
            "outer distribution clears reserve"
        );
    }

    // Scenarios: DIST-C01
    function test_givenPayoutCallbackReadsPendingGetter_observesDebtBeforeDeliveryClearsIt(
        address caller_
    ) public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        PendingPayoutCallbackObserver observer = new PendingPayoutCallbackObserver();
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(
            address(callbackToken),
            0,
            new IRevenueDistributor.AssetRoute[](0)
        );
        callbackToken.setCallbackFrom(
            address(distributor),
            address(observer),
            abi.encodeCall(
                observer.observe,
                (distributor, address(callbackToken), address(treasury))
            )
        );
        callbackToken.setCallbackTransferRecipient(address(treasury));
        callbackToken.mint(address(distributor), 10);

        vm.prank(caller_);
        distributor.distribute(address(callbackToken));

        assertTrue(
            callbackToken.callbackSucceeded(),
            "pending getter remains readable during callback"
        );
        assertEq(
            observer.observedPendingPayout(),
            10,
            "callback observes debt before delivery cleanup"
        );
        assertEq(
            distributor.pendingPayout(address(callbackToken), address(treasury)),
            0,
            "delivery clears debt after callback"
        );
        assertEq(callbackToken.balanceOf(address(treasury)), 10, "Treasury receives payout once");
    }

    // Scenarios: DIST-C02
    function test_givenPropagatedGuardFailure_whenAnyCallerDistributes_defersThenRetriesExactly(
        address caller_
    ) public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_333});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(callbackToken), 0, routes);
        callbackToken.mint(address(distributor), 10);
        callbackToken.setCallbackFrom(
            address(distributor),
            address(distributor),
            abi.encodeCall(distributor.distribute, (address(callbackToken)))
        );
        callbackToken.setBubbleCallbackFailure(true);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(address(callbackToken), alice, 3);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(address(callbackToken), address(treasury), 7);
        vm.recordLogs();
        vm.prank(caller_);
        distributor.distribute(address(callbackToken));

        assertEq(
            _countPayoutLogs(vm.getRecordedLogs()),
            2,
            "failed distribution emits exactly two payout events"
        );
        _assertPendingPayouts(address(callbackToken), alice, 3, 0, 7);
        assertEq(
            callbackToken.balanceOf(address(distributor)),
            10,
            "failed transfers retain all custody"
        );

        callbackToken.setBubbleCallbackFailure(false);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(callbackToken), alice, 3);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(callbackToken), address(treasury), 7);
        vm.prank(caller_);
        distributor.distribute(address(callbackToken));

        assertEq(callbackToken.balanceOf(alice), 3, "retry pays configured share once");
        assertEq(callbackToken.balanceOf(address(treasury)), 7, "retry pays Treasury share once");
        assertEq(callbackToken.balanceOf(address(distributor)), 0, "retry clears custody");
        assertEq(
            distributor.totalPendingForTest(address(callbackToken)),
            0,
            "retry clears reserve"
        );
        assertEq(distributor.getPendingPayoutAssets().length, 0, "retry clears pending index");
    }

    function _assertSingleTransferFailure(
        uint8 failedClass_,
        address caller_,
        bool reverts_
    ) internal {
        failedClass_ = uint8(bound(failedClass_, 0, 2));
        MockYieldRepurchaseRecipient yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        yieldRecipient.setVaultConfig(address(token), address(token), true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(yieldRecipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 2_000, routes);
        token.mint(address(distributor), 100);
        address failedRecipient = failedClass_ == 0
            ? alice
            : (failedClass_ == 1 ? address(yieldRecipient) : address(treasury));
        uint256 failedAmount = failedClass_ == 0 ? 30 : (failedClass_ == 1 ? 20 : 50);
        bytes memory transferCall = abi.encodeWithSelector(
            ERC20.transfer.selector,
            failedRecipient,
            failedAmount
        );
        if (reverts_) {
            vm.mockCallRevert(
                address(token),
                transferCall,
                abi.encodeWithSignature("Error(string)", "blocked")
            );
        } else {
            vm.mockCall(address(token), transferCall, abi.encode(false));
        }

        vm.recordLogs();
        vm.prank(caller_);
        distributor.distribute(address(token));

        assertEq(
            distributor.pendingPayout(address(token), failedRecipient),
            failedAmount,
            "selected debt is retained"
        );
        assertEq(
            token.balanceOf(address(distributor)),
            failedAmount,
            "failed share remains in custody"
        );
        assertEq(
            token.balanceOf(alice),
            failedClass_ == 0 ? 0 : 30,
            "configured recipient outcome is exact"
        );
        assertEq(
            token.balanceOf(address(yieldRecipient)),
            failedClass_ == 1 ? 0 : 20,
            "yield recipient outcome is exact"
        );
        assertEq(
            token.balanceOf(address(treasury)),
            failedClass_ == 2 ? 0 : 50,
            "Treasury outcome is exact"
        );
        assertEq(
            distributor.totalPendingForTest(address(token)),
            failedAmount,
            "aggregate reserve equals failed share"
        );
        address[] memory assets = distributor.getPendingPayoutAssets();
        assertEq(assets.length, 1, "failed asset remains indexed once");
        assertEq(assets[0], address(token), "failed asset index is exact");
        address[] memory recipients = distributor.getPendingPayoutRecipients(address(token));
        assertEq(recipients.length, 1, "failed recipient remains indexed once");
        assertEq(recipients[0], failedRecipient, "failed recipient index is exact");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countEvent(logs, IRevenueDistributor.DistributionDeferred.selector),
            1,
            "one deferred event emitted"
        );
        assertEq(
            _countEvent(logs, IRevenueDistributor.Distributed.selector),
            2,
            "two healthy payout events emitted"
        );
        vm.clearMockedCalls();
    }

    function _countPayoutLogs(Vm.Log[] memory logs_) internal pure returns (uint256 count) {
        count =
            _countEvent(logs_, IRevenueDistributor.DistributionDeferred.selector) +
            _countEvent(logs_, IRevenueDistributor.Distributed.selector);
    }

    function _countEvent(
        Vm.Log[] memory logs_,
        bytes32 selector_
    ) internal pure returns (uint256 count) {
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].topics.length != 0 && logs_[i].topics[0] == selector_) ++count;
        }
    }

    function _nonzeroShareCount(
        uint256 yieldAmount_,
        uint256 aliceAmount_,
        uint256 bobAmount_,
        uint256 treasuryAmount_
    ) internal pure returns (uint256 count) {
        if (yieldAmount_ != 0) ++count;
        if (aliceAmount_ != 0) ++count;
        if (bobAmount_ != 0) ++count;
        if (treasuryAmount_ != 0) ++count;
    }

    /// @dev Use a fresh asset for each explicit boundary so MAX supply never accumulates.
    ///      Shares use base units: floor(receipt * BPS / 10,000); Treasury gets all remainder.
    function _assertAllocationBoundary(
        uint16 repurchaseBps_,
        uint16 aliceBps_,
        uint16 bobBps_,
        uint256 receipt_,
        address caller_
    ) internal {
        MockERC20 boundaryToken = new MockERC20("Boundary Revenue", "BREV", 18);
        MockYieldRepurchaseRecipient recipient = MockYieldRepurchaseRecipient(
            distributor.yieldRecipient()
        );
        if (address(recipient) == address(0)) {
            recipient = new MockYieldRepurchaseRecipient(kernel);
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(recipient));
            vm.prank(address(configTimelock));
            distributor.setYieldRecipient(address(recipient));
        }
        recipient.setVaultConfig(address(boundaryToken), address(boundaryToken), true);

        uint256 routeCount = (aliceBps_ == 0 ? 0 : 1) + (bobBps_ == 0 ? 0 : 1);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
            routeCount
        );
        if (aliceBps_ != 0)
            routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: aliceBps_});
        if (bobBps_ != 0)
            routes[1] = IRevenueDistributor.AssetRoute({recipient: bob, bps: bobBps_});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(boundaryToken), repurchaseBps_, routes);
        boundaryToken.mint(address(distributor), receipt_);
        vm.recordLogs();
        vm.prank(caller_);
        distributor.distribute(address(boundaryToken));

        uint256 yieldShare = FullMath.mulDiv(receipt_, repurchaseBps_, 10_000);
        uint256 aliceShare = FullMath.mulDiv(receipt_, aliceBps_, 10_000);
        uint256 bobShare = FullMath.mulDiv(receipt_, bobBps_, 10_000);
        uint256 treasuryShare = receipt_ - yieldShare - aliceShare - bobShare;
        assertEq(
            boundaryToken.balanceOf(address(recipient)),
            yieldShare,
            "exact rounded repurchase share"
        );
        assertEq(
            boundaryToken.balanceOf(alice),
            aliceShare,
            "exact rounded first configured share"
        );
        assertEq(boundaryToken.balanceOf(bob), bobShare, "exact rounded second configured share");
        assertEq(
            boundaryToken.balanceOf(address(treasury)),
            treasuryShare,
            "Treasury receives all residual"
        );
        assertEq(boundaryToken.balanceOf(address(distributor)), 0, "boundary custody cleared");
        assertEq(
            distributor.totalPendingForTest(address(boundaryToken)),
            0,
            "boundary reserve cleared"
        );
        assertEq(
            distributor.getPendingPayoutAssets().length,
            0,
            "boundary creates no pending index"
        );
        assertEq(
            _countPayoutLogs(vm.getRecordedLogs()),
            _nonzeroShareCount(yieldShare, aliceShare, bobShare, treasuryShare),
            "one event per nonzero share"
        );
    }

    // Scenarios: DIST-P08.
    function test_givenTreasuryOnly_whenReceiptBoundariesDistributed(address caller_) public {
        _assertAllocationBoundary(0, 0, 0, 1, caller_);
        _assertAllocationBoundary(0, 0, 0, type(uint256).max, caller_);
    }

    // Scenarios: DIST-P08.
    function test_givenRepurchaseOnly_whenBpsAndReceiptBoundariesDistributed(
        address caller_
    ) public {
        _assertAllocationBoundary(1, 0, 0, 1, caller_);
        _assertAllocationBoundary(1, 0, 0, type(uint256).max, caller_);
        _assertAllocationBoundary(9_999, 0, 0, 1, caller_);
        _assertAllocationBoundary(9_999, 0, 0, type(uint256).max, caller_);
        _assertAllocationBoundary(10_000, 0, 0, 1, caller_);
        _assertAllocationBoundary(10_000, 0, 0, type(uint256).max, caller_);
    }

    // Scenarios: DIST-P08.
    function test_givenOneConfiguredRecipient_whenBpsAndReceiptBoundariesDistributed(
        address caller_
    ) public {
        _assertAllocationBoundary(0, 1, 0, 1, caller_);
        _assertAllocationBoundary(0, 1, 0, type(uint256).max, caller_);
        _assertAllocationBoundary(0, 9_999, 0, 1, caller_);
        _assertAllocationBoundary(0, 9_999, 0, type(uint256).max, caller_);
        _assertAllocationBoundary(0, 10_000, 0, 1, caller_);
        _assertAllocationBoundary(0, 10_000, 0, type(uint256).max, caller_);
    }

    // Scenarios: DIST-P08.
    function test_givenTwoConfiguredRecipients_whenBpsAndReceiptBoundariesDistributed(
        address caller_
    ) public {
        _assertAllocationBoundary(0, 1, 1, 1, caller_);
        _assertAllocationBoundary(0, 1, 1, type(uint256).max, caller_);
        _assertAllocationBoundary(0, 1, 9_999, 1, caller_);
        _assertAllocationBoundary(0, 1, 9_999, type(uint256).max, caller_);
        _assertAllocationBoundary(0, 9_999, 1, 1, caller_);
        _assertAllocationBoundary(0, 9_999, 1, type(uint256).max, caller_);
    }

    // Scenarios: DIST-P08.
    function test_givenMixedRecipients_whenBpsAndReceiptBoundariesDistributed(
        address caller_
    ) public {
        // Three positive shares cap each BPS at 9,998. The 1/1/1 route deliberately
        // leaves 9,997 BPS to Treasury; this is not just a rounding residual.
        _assertAllocationBoundary(1, 1, 1, 1, caller_);
        _assertAllocationBoundary(1, 1, 1, type(uint256).max, caller_);
        _assertAllocationBoundary(9_998, 1, 1, 1, caller_);
        _assertAllocationBoundary(9_998, 1, 1, type(uint256).max, caller_);
        _assertAllocationBoundary(1, 9_998, 1, 1, caller_);
        _assertAllocationBoundary(1, 9_998, 1, type(uint256).max, caller_);
        _assertAllocationBoundary(1, 1, 9_998, 1, caller_);
        _assertAllocationBoundary(1, 1, 9_998, type(uint256).max, caller_);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
