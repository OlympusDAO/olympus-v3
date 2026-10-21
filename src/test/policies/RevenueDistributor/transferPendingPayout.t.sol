// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Scenario amounts stay inline for accounting clarity.
// Scenario amounts are intentionally explicit; bounded casts are proven by their adjacent bounds.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {PendingPayoutCallbackObserver} from "./fixtures/PendingPayoutCallbackObserver.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorTransferPendingPayoutTest is RevenueDistributorTest {
    // Scenarios: RTRY-P01, RTRY-P08
    function test_givenNoPendingPayout_whenInputsAreArbitrary_noOps(
        address asset_,
        address recipient_,
        address caller_
    ) public {
        vm.assume(asset_.code.length == 0);

        vm.recordLogs();
        vm.prank(caller_);
        distributor.transferPendingPayout(asset_, recipient_);

        assertEq(
            distributor.pendingPayout(asset_, recipient_),
            0,
            "empty retry creates no liability"
        );
        assertEq(vm.getRecordedLogs().length, 0, "empty retry emits no event");
    }

    // Scenarios: RTRY-P01
    function test_givenNeverListedContractWithNoPendingPayout_whenRetried_noOps(
        address recipient_,
        address caller_
    ) public {
        MockRevertingTransferToken neverListedAsset = new MockRevertingTransferToken(18);

        vm.recordLogs();
        vm.prank(caller_);
        distributor.transferPendingPayout(address(neverListedAsset), recipient_);

        assertEq(
            distributor.pendingPayout(address(neverListedAsset), recipient_),
            0,
            "empty retry creates no liability"
        );
        assertEq(
            neverListedAsset.balanceOf(address(distributor)),
            0,
            "empty retry changes no custody"
        );
        assertEq(neverListedAsset.balanceOf(recipient_), 0, "empty retry transfers no tokens");
        assertEq(vm.getRecordedLogs().length, 0, "empty retry emits no event");
    }

    // Scenarios: RTRY-P08
    function test_givenNoPendingPayout_noOps() public givenAliceConfiguredAsRecipient {
        vm.prank(bob);
        distributor.transferPendingPayout(address(token), alice);
        assertEq(
            distributor.pendingPayout(address(token), alice),
            0,
            "no liability is created by empty retry"
        );
        assertEq(token.balanceOf(alice), 0, "empty retry transfers no tokens");
    }

    // Scenarios: RTRY-L01
    function test_givenPolicyInactive_whenAnyRetryAttempted_revertsBeforeLocalState(
        address caller_,
        bool retired_,
        bool disable_,
        bool hasEntitlement_
    ) public {
        _setAssetState(retired_);
        uint256 amount = hasEntitlement_ ? 60 : 0;
        distributor.seedPendingForTest(address(token), alice, amount, 0, 0);
        token.mint(address(distributor), amount);
        if (disable_) {
            vm.prank(admin);
            distributor.disable("");
        }
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), alice);

        _assertPendingPayouts(address(token), alice, amount, 0, 0);
        assertEq(token.balanceOf(address(distributor)), amount, "inactive retry preserves custody");
        assertEq(
            distributor.pendingAssetMemberForTest(address(token)),
            hasEntitlement_,
            "pending index is preserved"
        );
        assertEq(vm.getRecordedLogs().length, 0, "inactive retry emits no event");
    }

    // Scenarios: RTRY-L02
    function test_givenDistributorDisabled_whenAnyManagedAssetRetried_reverts(
        address caller_,
        bool retired_,
        uint96 amount_
    ) public {
        amount_ = uint96(bound(amount_, 1, type(uint96).max));
        _setAssetState(retired_);
        distributor.seedPendingForTest(address(token), alice, amount_, 0, 0);
        token.mint(address(distributor), amount_);
        vm.prank(admin);
        distributor.disable("");

        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), alice);

        _assertPendingPayouts(address(token), alice, amount_, 0, 0);
        assertEq(
            token.balanceOf(address(distributor)),
            amount_,
            "disabled retry preserves custody"
        );
        assertTrue(
            distributor.pendingAssetMemberForTest(address(token)),
            "pending asset remains indexed"
        );
        assertTrue(
            distributor.pendingRouteMemberForTest(address(token), alice),
            "pending recipient remains indexed"
        );
        assertEq(vm.getRecordedLogs().length, 0, "disabled retry emits no event");
    }

    // given a configured recipient and the old Treasury both have reserved shares
    //   given the configured recipient becomes the current Treasury
    //     when new receipts arrive and the recipient is retried directly
    //       [X] the recipient appears once and receives both reserved shares
    //       [X] the new receipts remain unallocated
    //       [X] updating the route then allows those new receipts to be distributed
    // Scenarios: RTRY-P05
    function test_givenPendingConfiguredRecipientBecomesTreasury_whenNewReceiptsArrive_paysBoth()
        public
    {
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
        distributor.distribute(address(token));
        revertingToken.setTransferReverts(address(newTreasury), false);
        revertingToken.setTransferReverts(address(treasury), false);

        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        token.mint(address(distributor), 10);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(newTreasury)
            )
        );
        distributor.distribute(address(token));

        address[] memory pending = distributor.getPendingPayoutRecipients(address(token));
        assertEq(pending.length, 1, "overlapping configured and Treasury debt lists one recipient");
        assertEq(pending[0], address(newTreasury), "current Treasury is listed once");
        assertEq(
            distributor.pendingPayout(address(token), address(newTreasury)),
            100,
            "the recipient is owed both allocations"
        );
        distributor.transferPendingPayout(address(token), address(newTreasury));
        assertEq(token.balanceOf(address(newTreasury)), 100, "one retry delivers both allocations");
        assertEq(token.balanceOf(address(distributor)), 10, "new receipts remain unallocated");
        assertEq(
            distributor.pendingPayout(address(token), address(newTreasury)),
            0,
            "retry clears both reserved shares"
        );

        routes[0].recipient = alice;
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.distribute(address(token));
        assertEq(token.balanceOf(alice), 5, "updated route pays the configured share");
        assertEq(token.balanceOf(address(newTreasury)), 105, "new Treasury receives the remainder");
        assertEq(
            token.balanceOf(address(distributor)),
            0,
            "new receipts settle after route update"
        );
    }

    // given a retired asset with a pending payout and a disabled distributor
    //   when the payout is retried before and after re-enablement
    //     [X] only the enabled retry pays the recipient
    // Scenarios: RTRY-L02, RTRY-P02
    function test_givenRetiredAssetAndDisabledDistributor_retryWaitsForReEnable() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 10_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        token.mint(address(distributor), 10);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, bob),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
        vm.prank(emergency);
        distributor.disable("");

        assertEq(distributor.pendingPayout(address(token), bob), 10, "pending debt remains");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        distributor.transferPendingPayout(address(token), bob);
        assertEq(distributor.pendingPayout(address(token), bob), 10, "disabled retry retains debt");
        vm.prank(admin);
        distributor.reEnable();
        distributor.transferPendingPayout(address(token), bob);
        assertEq(token.balanceOf(bob), 10, "direct retry pays retired asset recipient");
    }

    // given two pending recipients and one still blocked by the token
    //   when the other recipient is retried directly
    //     [X] only that recipient receives its payout
    // Scenarios: RTRY-P02
    function test_givenTwoPendingRecipients_whenFirstStillBlocked_thenSecondCanRetryDirectly()
        public
    {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 5_000});
        routes[1] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 5_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        token.mint(address(distributor), 10);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, alice),
            abi.encodeWithSignature("Error(string)", "alice blacklisted")
        );
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, bob),
            abi.encodeWithSignature("Error(string)", "bob blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, alice),
            abi.encodeWithSignature("Error(string)", "alice blacklisted")
        );
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        vm.startSnapshotGas("RevenueDistributor.transferPendingPayout.configuredRecipient");
        distributor.transferPendingPayout(address(token), bob);
        uint256 retryGas = vm.stopSnapshotGas();

        assertGt(retryGas, 0, "configured-recipient retry gas is recorded");

        assertEq(token.balanceOf(bob), 5, "second recipient receives independent direct retry");
        assertEq(
            distributor.pendingPayout(address(token), alice),
            5,
            "first recipient stays pending"
        );
        assertEq(distributor.pendingPayout(address(token), bob), 0, "second recipient debt clears");
    }

    // Scenarios: RTRY-P02
    function test_givenConfiguredPayout_whenRetried_paysExactAmountAndIsolatesOtherDebt(
        uint256 amount_,
        bool retired_,
        address caller_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        _setAssetState(retired_);
        MockRevertingTransferToken otherAsset = new MockRevertingTransferToken(18);
        distributor.seedPendingForTest(address(token), alice, amount_, 0, 0);
        distributor.seedPendingForTest(address(otherAsset), bob, 7, 0, 0);
        token.mint(address(distributor), amount_);
        otherAsset.mint(address(distributor), 7);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), alice, amount_);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), alice);

        assertEq(token.balanceOf(alice), amount_, "configured recipient receives exact amount");
        _assertPendingPayouts(address(token), alice, 0, 0, 0);
        assertFalse(
            distributor.pendingAssetMemberForTest(address(token)),
            "paid asset leaves pending index"
        );
        assertFalse(
            distributor.pendingRouteMemberForTest(address(token), alice),
            "paid recipient leaves index"
        );
        _assertPendingPayouts(address(otherAsset), bob, 7, 0, 0);
        assertEq(otherAsset.balanceOf(address(distributor)), 7, "other asset custody is isolated");
    }

    // Scenarios: RTRY-P02
    function test_givenConfiguredPayoutAtMaximum_whenRetried_paysExactAmount() public {
        distributor.seedPendingForTest(address(token), alice, type(uint256).max, 0, 0);
        token.mint(address(distributor), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), alice, type(uint256).max);
        distributor.transferPendingPayout(address(token), alice);

        assertEq(
            token.balanceOf(alice),
            type(uint256).max,
            "maximum configured payout is delivered"
        );
        _assertPendingPayouts(address(token), alice, 0, 0, 0);
    }

    // Scenarios: RTRY-L01
    function test_givenPendingTreasury_whenPolicyInactiveAndTreasuryUpgrades_thenRetryWaitsForReactivation()
        public
    {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        token.mint(address(distributor), 10);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, address(treasury)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        vm.stopPrank();

        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        distributor.transferPendingPayout(address(token), address(treasury));
        assertEq(
            token.balanceOf(address(newTreasury)),
            0,
            "inactive distributor transfers nothing"
        );
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        address[] memory pendingRecipients = distributor.getPendingPayoutRecipients(address(token));
        assertEq(pendingRecipients[0], address(newTreasury), "reactivation refreshes Treasury");
        distributor.transferPendingPayout(address(token), address(newTreasury));
        assertEq(token.balanceOf(address(treasury)), 0, "old Treasury receives nothing");
        assertEq(token.balanceOf(address(newTreasury)), 10, "new Treasury receives payout");
    }

    // Scenarios: RTRY-L02
    function test_givenPendingRecipient_whenDistributorDisabled_thenRetryWaitsForReEnable()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 100);
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, alice, 33),
            abi.encode(false)
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();

        vm.prank(emergency);
        distributor.disable("");
        vm.prank(bob);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        distributor.transferPendingPayout(address(token), alice);
        assertEq(distributor.pendingPayout(address(token), alice), 33, "unpaid share remains owed");
        assertEq(token.balanceOf(alice), 0, "disabled distributor transfers nothing");

        vm.prank(admin);
        distributor.reEnable();
        vm.prank(bob);
        distributor.transferPendingPayout(address(token), alice);
        assertEq(token.balanceOf(alice), 33, "re-enabled distributor delivers the share");
        assertEq(distributor.pendingPayout(address(token), alice), 0, "retry clears the debt");
    }

    // Scenarios: RTRY-P04
    function test_givenTreasuryPayoutPending_whenTreasuryUpgrades_thenRetryPaysNewTreasury()
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
        vm.clearMockedCalls();

        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        assertEq(
            distributor.pendingPayout(address(token), address(newTreasury)),
            67,
            "pending residual follows current Treasury"
        );
        address[] memory currentRecipients = distributor.getPendingPayoutRecipients(address(token));
        assertEq(currentRecipients.length, 1, "one current recipient");
        assertEq(currentRecipients[0], address(newTreasury), "recipient follows Treasury upgrade");
        distributor.transferPendingPayout(address(token), address(newTreasury));

        assertEq(token.balanceOf(address(treasury)), 0, "former Treasury receives nothing");
        assertEq(token.balanceOf(address(newTreasury)), 67, "new Treasury receives residual");
        assertEq(distributor.pendingPayout(address(token), address(newTreasury)), 0, "debt clears");
    }

    // Scenarios: RTRY-P04
    function test_givenTreasuryPayout_whenTreasuryUpgrades_retryUsesCurrentRole(
        uint256 amount_,
        bool retired_,
        address caller_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max - 7);
        _setAssetState(retired_);
        distributor.seedPendingForTest(address(token), bob, 7, 0, amount_);
        token.mint(address(distributor), amount_ + 7);
        OlympusTreasury oldTreasury = treasury;
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));

        vm.recordLogs();
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), address(oldTreasury));
        assertEq(vm.getRecordedLogs().length, 0, "former Treasury retry is silent");

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(newTreasury), amount_);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), address(newTreasury));

        assertEq(token.balanceOf(address(oldTreasury)), 0, "former Treasury receives nothing");
        assertEq(
            token.balanceOf(address(newTreasury)),
            amount_,
            "current Treasury receives exact payout"
        );
        _assertPendingPayouts(address(token), bob, 7, 0, 0);
        assertTrue(
            distributor.pendingRouteMemberForTest(address(token), bob),
            "fixed debt remains indexed"
        );
    }

    // Scenarios: RTRY-P04
    function test_givenMaximumTreasuryPayout_whenTreasuryUpgrades_retryPaysMaximum() public {
        distributor.seedPendingForTest(address(token), alice, 0, 0, type(uint256).max);
        token.mint(address(distributor), type(uint256).max);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));

        distributor.transferPendingPayout(address(token), address(newTreasury));

        assertEq(
            token.balanceOf(address(newTreasury)),
            type(uint256).max,
            "maximum Treasury payout is delivered"
        );
        _assertPendingPayouts(address(token), alice, 0, 0, 0);
    }

    // Scenarios: RTRY-P03
    function test_givenYieldPayout_whenRecipientRotates_retryUsesCurrentRole(
        uint256 amount_,
        bool retired_,
        address caller_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max - 7);
        MockYieldRepurchaseRecipient oldRecipient = _newYieldRecipientForAsset(address(token));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(oldRecipient));
        _setAssetState(retired_);
        distributor.seedPendingForTest(address(token), bob, 7, amount_, 0);
        token.mint(address(distributor), amount_ + 7);
        MockYieldRepurchaseRecipient newRecipient = _newYieldRecipientForAsset(address(token));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(newRecipient));

        vm.recordLogs();
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), address(oldRecipient));
        assertEq(vm.getRecordedLogs().length, 0, "former Yield Recipient retry is silent");

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(newRecipient), amount_);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), address(newRecipient));

        assertEq(
            token.balanceOf(address(oldRecipient)),
            0,
            "former Yield Recipient receives nothing"
        );
        assertEq(
            token.balanceOf(address(newRecipient)),
            amount_,
            "current Yield Recipient receives payout"
        );
        _assertPendingPayouts(address(token), bob, 7, 0, 0);
        assertTrue(
            distributor.pendingRouteMemberForTest(address(token), bob),
            "fixed debt remains indexed"
        );
    }

    // Scenarios: RTRY-P03
    function test_givenMaximumYieldPayout_whenRecipientRotates_retryPaysMaximum() public {
        MockYieldRepurchaseRecipient oldRecipient = _newYieldRecipientForAsset(address(token));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(oldRecipient));
        distributor.seedPendingForTest(address(token), alice, 0, type(uint256).max, 0);
        token.mint(address(distributor), type(uint256).max);
        MockYieldRepurchaseRecipient newRecipient = _newYieldRecipientForAsset(address(token));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(newRecipient));

        distributor.transferPendingPayout(address(token), address(newRecipient));

        assertEq(
            token.balanceOf(address(newRecipient)),
            type(uint256).max,
            "maximum yield payout is delivered"
        );
        _assertPendingPayouts(address(token), alice, 0, 0, 0);
    }

    // Scenarios: RTRY-P12
    function test_givenYieldPayout_whenRecipientClears_retryUsesTreasuryFallback(
        uint256 amount_,
        bool retired_,
        address caller_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max - 7);
        MockYieldRepurchaseRecipient oldRecipient = _newYieldRecipientForAsset(address(token));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(oldRecipient));
        _setAssetState(retired_);
        distributor.seedPendingForTest(address(token), bob, 7, amount_, 0);
        token.mint(address(distributor), amount_ + 7);
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(0));

        vm.recordLogs();
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), address(oldRecipient));
        assertEq(
            vm.getRecordedLogs().length,
            0,
            "former Yield Recipient retry is silent after clearing"
        );

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), address(treasury), amount_);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), address(treasury));

        assertEq(
            token.balanceOf(address(oldRecipient)),
            0,
            "former Yield Recipient receives nothing"
        );
        assertEq(token.balanceOf(address(treasury)), amount_, "Treasury fallback receives payout");
        _assertPendingPayouts(address(token), bob, 7, 0, 0);
    }

    // Scenarios: RTRY-P12
    function test_givenMaximumYieldPayout_whenRecipientClears_retryPaysTreasuryMaximum() public {
        MockYieldRepurchaseRecipient oldRecipient = _newYieldRecipientForAsset(address(token));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(oldRecipient));
        distributor.seedPendingForTest(address(token), alice, 0, type(uint256).max, 0);
        token.mint(address(distributor), type(uint256).max);
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(0));

        distributor.transferPendingPayout(address(token), address(treasury));

        assertEq(
            token.balanceOf(address(treasury)),
            type(uint256).max,
            "maximum fallback payout is delivered"
        );
        _assertPendingPayouts(address(token), alice, 0, 0, 0);
    }

    // Scenarios: RTRY-C01
    function test_givenPendingPayout_whenTokenReentersRetry_thenPayoutOccursOnce() public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 10_000});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(callbackToken), 0, routes);
        callbackToken.mint(address(distributor), 10);
        callbackToken.setCallbackFrom(
            address(distributor),
            address(distributor),
            abi.encodeCall(distributor.transferPendingPayout, (address(callbackToken), alice))
        );
        callbackToken.setBubbleCallbackFailure(true);
        distributor.distribute(address(callbackToken));
        assertEq(
            distributor.pendingPayout(address(callbackToken), alice),
            10,
            "failed callback retains debt"
        );

        callbackToken.setBubbleCallbackFailure(false);
        distributor.transferPendingPayout(address(callbackToken), alice);
        assertFalse(callbackToken.callbackSucceeded(), "nested retry is guarded");
        assertEq(callbackToken.balanceOf(alice), 10, "outer retry pays once");
        assertEq(distributor.pendingPayout(address(callbackToken), alice), 0, "debt clears once");
    }

    // Scenarios: RTRY-C01
    function test_givenPendingPayout_whenTokenCatchesAnyGuardedNestedCall_paysOnce(
        uint8 bucketMask_,
        uint8 nestedCallKind_,
        address caller_
    ) public {
        bucketMask_ = uint8(bound(bucketMask_, 1, 7));
        nestedCallKind_ = uint8(bound(nestedCallKind_, 0, 3));
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        address recipient = address(treasury);
        uint256 routeAmount = bucketMask_ & 1 == 0 ? 0 : 10;
        uint256 yieldAmount = bucketMask_ & 2 == 0 ? 0 : 20;
        uint256 treasuryAmount = bucketMask_ & 4 == 0 ? 0 : 30;
        uint256 total = routeAmount + yieldAmount + treasuryAmount;
        distributor.seedPendingForTest(
            address(callbackToken),
            recipient,
            routeAmount,
            yieldAmount,
            treasuryAmount
        );
        callbackToken.mint(address(distributor), total);
        bytes memory callbackData;
        if (nestedCallKind_ == 0) {
            callbackData = abi.encodeCall(
                distributor.transferPendingPayout,
                (address(callbackToken), recipient)
            );
        } else if (nestedCallKind_ == 1) {
            callbackData = abi.encodeCall(distributor.distribute, (address(callbackToken)));
        } else if (nestedCallKind_ == 2) {
            callbackData = abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(callbackToken), recipient, bob, 1)
            );
        } else {
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                0
            );
            callbackData = abi.encodeCall(
                distributor.setAssetRoutes,
                (address(callbackToken), 0, routes)
            );
        }
        callbackToken.setCallbackFrom(address(distributor), address(distributor), callbackData);

        vm.recordLogs();
        vm.prank(caller_);
        distributor.transferPendingPayout(address(callbackToken), recipient);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertFalse(callbackToken.callbackSucceeded(), "nested guarded call is rejected");
        assertEq(
            callbackToken.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "nested call reaches reentrancy guard"
        );
        assertEq(callbackToken.balanceOf(recipient), total, "outer retry pays exactly once");
        assertEq(callbackToken.transferCallCount(), 1, "outer retry performs one token transfer");
        _assertPendingPayouts(address(callbackToken), recipient, 0, 0, 0);
        assertFalse(
            distributor.pendingAssetMemberForTest(address(callbackToken)),
            "paid asset leaves pending index"
        );
        assertFalse(
            distributor.pendingRouteMemberForTest(address(callbackToken), recipient),
            "paid configured recipient leaves pending index"
        );
        assertEq(_countDistributedLogs(logs), 1, "outer retry emits exactly one payout event");
    }

    // Scenarios: RTRY-C01
    function test_givenPendingPayout_whenTokenReadsGetter_callbackSeesPreDeliveryDebt() public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        PendingPayoutCallbackObserver observer = new PendingPayoutCallbackObserver();
        address recipient = address(treasury);
        distributor.seedPendingForTest(address(callbackToken), recipient, 10, 20, 30);
        callbackToken.mint(address(distributor), 60);
        callbackToken.setCallbackFrom(
            address(distributor),
            address(observer),
            abi.encodeCall(observer.observe, (distributor, address(callbackToken), recipient))
        );

        distributor.transferPendingPayout(address(callbackToken), recipient);

        assertTrue(callbackToken.callbackSucceeded(), "read callback succeeds");
        assertEq(observer.observedPendingPayout(), 60, "callback observes full pre-delivery debt");
        assertEq(
            distributor.pendingPayout(address(callbackToken), recipient),
            0,
            "outer retry clears debt afterward"
        );
        assertEq(callbackToken.balanceOf(recipient), 60, "outer retry pays once");
    }

    // Scenarios: RTRY-C02
    function test_givenPendingPayout_whenTokenPropagatesReentrantFailure_defersPayout() public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        distributor.seedPendingForTest(address(callbackToken), alice, 10, 0, 0);
        callbackToken.mint(address(distributor), 10);
        callbackToken.setCallbackFrom(
            address(distributor),
            address(distributor),
            abi.encodeCall(distributor.transferPendingPayout, (address(callbackToken), alice))
        );
        callbackToken.setBubbleCallbackFailure(true);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(address(callbackToken), alice, 10);
        distributor.transferPendingPayout(address(callbackToken), alice);

        assertEq(
            distributor.pendingPayout(address(callbackToken), alice),
            10,
            "propagated callback failure retains debt"
        );
        assertEq(
            callbackToken.balanceOf(address(distributor)),
            10,
            "propagated callback failure retains custody"
        );
        assertEq(callbackToken.balanceOf(alice), 0, "failed retry transfers nothing");
    }

    // Scenarios: RTRY-P05, RTRY-P11
    function test_givenCombinedPendingBuckets_whenRetried_paysOneCombinedTransfer(
        uint8 mask_,
        uint96 route_,
        uint96 yield_,
        uint96 treasury_,
        address caller_
    ) public {
        mask_ = uint8(bound(mask_, 1, 7));
        route_ = uint96(bound(route_, 1, type(uint96).max));
        yield_ = uint96(bound(yield_, 1, type(uint96).max));
        treasury_ = uint96(bound(treasury_, 1, type(uint96).max));
        uint256 routeAmount = mask_ & 1 == 0 ? 0 : route_;
        uint256 yieldAmount = mask_ & 2 == 0 ? 0 : yield_;
        uint256 treasuryAmount = mask_ & 4 == 0 ? 0 : treasury_;
        uint256 total = routeAmount + yieldAmount + treasuryAmount;
        address recipient = address(treasury);
        // A historical fixed recipient can become Treasury after allocation. With the Yield
        // Recipient unset, all selected live-role buckets also resolve to the same address.
        distributor.seedPendingForTest(
            address(token),
            recipient,
            routeAmount,
            yieldAmount,
            treasuryAmount
        );
        token.mint(address(distributor), total);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.Distributed(address(token), recipient, total);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), recipient);

        assertEq(token.balanceOf(recipient), total, "recipient receives combined entitlement once");
        assertEq(token.balanceOf(address(distributor)), 0, "combined payment leaves no custody");
        _assertPendingPayouts(address(token), recipient, 0, 0, 0);
        assertFalse(
            distributor.pendingAssetMemberForTest(address(token)),
            "fully paid asset leaves pending index"
        );
        assertFalse(
            distributor.pendingRouteMemberForTest(address(token), recipient),
            "paid fixed recipient leaves pending index"
        );

        vm.recordLogs();
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), recipient);
        assertEq(vm.getRecordedLogs().length, 0, "repeat retry is silent");
    }

    // Scenarios: RTRY-T01
    function test_givenCombinedPendingBuckets_whenTransferReturnsFalse_defersThenRetries(
        uint8 mask_,
        address caller_
    ) public {
        mask_ = uint8(bound(mask_, 1, 7));
        uint256 routeAmount = mask_ & 1 == 0 ? 0 : 10;
        uint256 yieldAmount = mask_ & 2 == 0 ? 0 : 20;
        uint256 treasuryAmount = mask_ & 4 == 0 ? 0 : 30;
        uint256 total = routeAmount + yieldAmount + treasuryAmount;
        address recipient = address(treasury);
        distributor.seedPendingForTest(
            address(token),
            recipient,
            routeAmount,
            yieldAmount,
            treasuryAmount
        );
        token.mint(address(distributor), total);
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, recipient, total),
            abi.encode(false)
        );

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(address(token), recipient, total);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(token), recipient);

        _assertPendingPayouts(address(token), recipient, routeAmount, yieldAmount, treasuryAmount);
        assertEq(token.balanceOf(address(distributor)), total, "failed transfer retains custody");
        vm.clearMockedCalls();

        distributor.transferPendingPayout(address(token), recipient);
        assertEq(token.balanceOf(recipient), total, "later retry pays retained entitlement");
        _assertPendingPayouts(address(token), recipient, 0, 0, 0);
    }

    // Scenarios: RTRY-T03
    function test_givenPendingPayout_whenTransferReverts_defersThenRetries(address caller_) public {
        MockRevertingTransferToken revertingToken = new MockRevertingTransferToken(18);
        address recipient = address(treasury);
        distributor.seedPendingForTest(address(revertingToken), recipient, 10, 20, 30);
        revertingToken.mint(address(distributor), 60);
        revertingToken.setTransferReverts(recipient, true);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(address(revertingToken), recipient, 60);
        vm.prank(caller_);
        distributor.transferPendingPayout(address(revertingToken), recipient);

        _assertPendingPayouts(address(revertingToken), recipient, 10, 20, 30);
        assertEq(
            revertingToken.balanceOf(address(distributor)),
            60,
            "reverting transfer retains custody"
        );
        revertingToken.setTransferReverts(recipient, false);
        distributor.transferPendingPayout(address(revertingToken), recipient);
        assertEq(revertingToken.balanceOf(recipient), 60, "later retry pays retained entitlement");
    }

    // Scenarios: RTRY-T02
    function test_givenPendingPayoutExceedsCustody_whenRetried_defersUntilFunded() public {
        address recipient = address(treasury);
        distributor.seedPendingForTest(address(token), recipient, 10, 20, 30);

        vm.expectEmit(true, true, false, true, address(distributor));
        emit IRevenueDistributor.DistributionDeferred(address(token), recipient, 60);
        distributor.transferPendingPayout(address(token), recipient);

        _assertPendingPayouts(address(token), recipient, 10, 20, 30);
        token.mint(address(distributor), 60);
        distributor.transferPendingPayout(address(token), recipient);
        assertEq(token.balanceOf(recipient), 60, "funded retry pays full entitlement");
        _assertPendingPayouts(address(token), recipient, 0, 0, 0);
    }

    function _setAssetState(bool retired_) internal {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);
        if (retired_) {
            vm.prank(address(configTimelock));
            distributor.disableAssetRoutes(address(token));
        }
    }

    function _newYieldRecipientForAsset(
        address asset_
    ) internal returns (MockYieldRepurchaseRecipient recipient) {
        recipient = new MockYieldRepurchaseRecipient(kernel);
        recipient.setVaultConfig(asset_, asset_, true);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
    }

    function _countDistributedLogs(Vm.Log[] memory logs_) internal view returns (uint256 count) {
        bytes32 signature = keccak256("Distributed(address,address,uint256)");
        for (uint256 i; i < logs_.length; ++i) {
            if (logs_[i].emitter == address(distributor) && logs_[i].topics[0] == signature)
                ++count;
        }
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast)
