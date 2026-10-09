// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Libraries
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansTransferPendingSeizurePayoutTest is BurnerLoansSeizureTestBase {
    // Scenarios: BLTRY-P03
    function test_givenPendingSeizure_retryPaysEveryQuantityAndPreservesOtherToken(
        bool upgradeTreasury_,
        bool useMaximum_,
        uint256 amountSeed_,
        address caller_
    ) public {
        uint256 amount = useMaximum_
            ? type(uint256).max
            : bound(amountSeed_, 1, type(uint256).max - 1);
        MockRevertingTransferToken token = new MockRevertingTransferToken(_collateralDecimals());
        MockRevertingTransferToken otherToken = new MockRevertingTransferToken(
            _collateralDecimals()
        );
        address formerTreasury = address(trsry);
        token.setTransferReverts(formerTreasury, true);
        token.mint(address(burnerLoans), amount);
        burnerLoans.recordPendingSeizedCollateralForTest(address(token), formerTreasury, amount);
        uint256 unrelated = 41;
        otherToken.setTransferReverts(keeper, true);
        otherToken.mint(address(burnerLoans), unrelated);
        burnerLoans.recordPendingSeizureRewardForTest(address(otherToken), keeper, unrelated);
        token.setTransferReverts(formerTreasury, false);

        address currentTreasury = formerTreasury;
        if (upgradeTreasury_) {
            _deactivatePolicy(address(burnerLoans));
            OlympusTreasury upgraded = new OlympusTreasury(kernel);
            vm.prank(admin);
            kernel.executeAction(Actions.UpgradeModule, address(upgraded));
            _activatePolicy(address(burnerLoans));
            currentTreasury = address(upgraded);
        }

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(token),
            currentTreasury,
            IBurnerLoans.PayoutKind.Seizure,
            amount
        );
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), currentTreasury),
            amount,
            "retry returns exact seized collateral"
        );

        assertEq(
            token.balanceOf(currentTreasury),
            amount,
            "current Treasury receives exact amount"
        );
        assertEq(burnerLoans.pendingSeizureForTest(address(token)), 0, "seizure bucket clears");
        assertEq(burnerLoans.totalPendingForTest(address(token)), 0, "seizure reserve clears");
        assertEq(
            burnerLoans.pendingSeizureRewardForTest(address(otherToken), keeper),
            unrelated,
            "other-token reward remains exact"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(otherToken)),
            unrelated,
            "other-token reserve remains exact"
        );
        assertEq(
            burnerLoans.getPendingPayoutTokens().length,
            1,
            "only other token remains indexed"
        );
    }

    // Scenarios: BLTRY-T02, BLTRY-T06
    function test_givenTwoOrderedBuckets_retryRetainsOnlyFailedRemainder(
        bool underfundSecondTransfer_,
        address caller_
    ) public {
        uint256 fee = 3;
        uint256 seizure = 5;
        MockRevertingTransferToken implementation = new MockRevertingTransferToken(
            _collateralDecimals()
        );
        vm.etch(address(usds), address(implementation).code);
        MockRevertingTransferToken liveToken = MockRevertingTransferToken(address(usds));
        liveToken.setTransferReverts(address(trsry), true);
        liveToken.mint(alice, fee);
        vm.prank(alice);
        assertTrue(liveToken.approve(address(burnerLoans), fee), "fee approval succeeds");
        burnerLoans.recordPendingFeeForTest(address(usds), alice, address(trsry), fee);
        liveToken.mint(address(burnerLoans), seizure);
        burnerLoans.recordPendingSeizedCollateralForTest(address(usds), address(trsry), seizure);
        liveToken.setTransferReverts(address(trsry), false);
        if (underfundSecondTransfer_) {
            liveToken.burn(address(burnerLoans), seizure);
        } else {
            liveToken.setRevertOnTransferCall(2);
        }

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(usds),
            address(trsry),
            IBurnerLoans.PayoutKind.Fee,
            fee
        );
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutDeferred(
            address(usds),
            address(trsry),
            IBurnerLoans.PayoutKind.Seizure,
            seizure
        );
        vm.prank(caller_);
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), address(trsry));

        assertEq(transferred, fee, "retry reports only the successful fee");
        assertEq(liveToken.balanceOf(address(trsry)), fee, "Treasury receives only the fee");
        assertEq(burnerLoans.pendingFeeForTest(address(usds)), 0, "fee bucket clears");
        assertEq(
            burnerLoans.pendingSeizureForTest(address(usds)),
            seizure,
            "seizure bucket remains"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(usds)),
            seizure,
            "reserve retains remainder"
        );
        assertEq(
            burnerLoans.getPendingPayoutRecipients(address(usds)).length,
            1,
            "Treasury remains discoverable"
        );

        if (underfundSecondTransfer_) liveToken.mint(address(burnerLoans), seizure);
        else liveToken.setRevertOnTransferCall(0);
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), address(trsry)),
            seizure,
            "later retry pays only the remainder"
        );
        assertEq(liveToken.balanceOf(address(trsry)), fee + seizure, "Treasury paid exactly once");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "reserve clears");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "token index clears");
    }

    // given the fee destination resolves to Treasury
    //   given the seizure recipient and keeper also resolve to Treasury
    //     given their token transfers revert
    //       when the pending recipient is enumerated and retried
    //         [X] Treasury appears once and receives all three obligations
    // Scenarios: BLTRY-P04
    function test_givenKeeperAndFeeAndSeizureShareTreasury_listsAndPaysOnce() public {
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "Treasury blacklisted")
        );
        _makeUnhealthy(alice);
        uint256 fee = burnerLoans.pendingPayout(address(usds), address(trsry));
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.prank(address(trsry));
        (address tokenOut, uint256 keeperReward, uint256 seizedCollateral) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(tokenOut, address(usds), "seizure outputs the collateral token");
        assertEq(keeperReward, preview.keeperReward, "seizure records the keeper reward");
        assertEq(
            seizedCollateral,
            preview.collateralToTreasury,
            "seizure records Treasury collateral"
        );
        vm.clearMockedCalls();

        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "overlapping obligations list one recipient");
        assertEq(recipients[0], address(trsry), "Treasury is the sole pending recipient");
        uint256 expected = fee + preview.keeperReward + preview.collateralToTreasury;
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            expected,
            "all three obligations are owed"
        );

        uint256 beforeBalance = usds.balanceOf(address(trsry));
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), address(trsry));
        assertEq(transferred, expected, "retry reports all three payments");
        assertEq(
            usds.balanceOf(address(trsry)) - beforeBalance,
            expected,
            "Treasury receives all three payments"
        );
        assertEq(
            burnerLoans.getPendingPayoutRecipients(address(usds)).length,
            0,
            "no recipient remains pending"
        );
    }

    // given a fee transfer to Treasury reverts
    //   given a seized-collateral transfer to Treasury also reverts
    //     when Treasury is enumerated and retried
    //       [X] it appears once and receives both obligations
    // Scenarios: BLTRY-P04
    function test_givenFeeAndSeizurePending_transfersBothAmounts() public {
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "Treasury blacklisted")
        );
        _makeUnhealthy(alice);
        uint256 fee = burnerLoans.pendingPayout(address(usds), address(trsry));
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 seizedCollateral) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(tokenOut, address(usds), "seizure pays USDS collateral");
        assertEq(keeperReward, preview.keeperReward, "seizure returns keeper reward");
        assertEq(
            seizedCollateral,
            preview.collateralToTreasury,
            "seizure returns Treasury obligation"
        );
        vm.clearMockedCalls();

        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "fee and seizure share one destination");
        assertEq(recipients[0], address(trsry), "Treasury is listed once");
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        vm.startSnapshotGas("BurnerLoans.transferPendingPayout.feeAndSeizure");
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), address(trsry));
        uint256 gasUsed = vm.stopSnapshotGas();

        assertGt(gasUsed, 0, "retry gas is recorded");
        assertGt(fee, 0, "fee was owed before retry");
        assertEq(transferred, fee + preview.collateralToTreasury, "retry returns both payouts");
        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            transferred,
            "Treasury receives both payouts"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            0,
            "Treasury obligations clear"
        );
    }

    // given the keeper reward transfer reverts
    //   given the seized-collateral transfer to Treasury also reverts
    //     when Treasury is retried
    //       [X] only the seized-collateral obligation clears
    function test_givenKeeperAndTreasuryPending_leavesKeeperOwed() public {
        _makeUnhealthy(alice);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, keeper),
            abi.encodeWithSignature("Error(string)", "keeper blacklisted")
        );
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "Treasury blacklisted")
        );
        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 seizedCollateral) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(tokenOut, address(usds), "seizure pays USDS collateral");
        assertEq(keeperReward, preview.keeperReward, "seizure returns keeper obligation");
        assertEq(
            seizedCollateral,
            preview.collateralToTreasury,
            "seizure returns Treasury obligation"
        );
        vm.clearMockedCalls();

        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), address(trsry));
        assertEq(transferred, preview.collateralToTreasury, "retry pays Treasury allocation");

        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            preview.collateralToTreasury,
            "Treasury receives its collateral"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), keeper),
            preview.keeperReward,
            "original keeper remains owed"
        );
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "only keeper remains listed");
        assertEq(recipients[0], keeper, "original keeper remains recipient");
    }

    // given seized collateral remains pending
    //   given its token calls the retry function during transfer
    //     when Treasury is retried
    //       [X] the nested call fails and Treasury is paid once
    // Scenarios: BLTRY-C01
    function test_givenPendingSeizure_whenTokenReentersRetry_paysOnce() public {
        _makeUnhealthy(alice);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 seizedCollateral) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(tokenOut, address(usds), "seizure pays USDS collateral");
        assertEq(keeperReward, preview.keeperReward, "seizure returns keeper reward");
        assertEq(
            seizedCollateral,
            preview.collateralToTreasury,
            "seizure returns Treasury obligation"
        );
        vm.clearMockedCalls();
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        vm.etch(address(usds), address(callbackToken).code);
        ReentrantFeeToken(address(usds)).setCallbackFrom(
            address(burnerLoans),
            address(burnerLoans),
            abi.encodeCall(burnerLoans.transferPendingPayout, (address(usds), address(trsry)))
        );

        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), address(trsry));
        assertEq(transferred, preview.collateralToTreasury, "retry reports one collateral payout");

        assertFalse(ReentrantFeeToken(address(usds)).callbackSucceeded(), "nested retry fails");
        assertEq(
            ReentrantFeeToken(address(usds)).callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "shared guard rejects nested retry"
        );
        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            preview.collateralToTreasury,
            "Treasury receives collateral once"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            0,
            "pending collateral clears"
        );
    }

    // given seized collateral is pending
    //   given the facility becomes Kernel-inactive
    //     when Treasury upgrades and the facility is reactivated
    //       [X] retry pays only the new Treasury
    // Scenarios: BLTRY-P03, BLTRY-P09
    function test_givenPendingSeizure_whenTreasuryUpgradesWhileInactive_paysNewTreasury() public {
        _makeUnhealthy(alice);
        uint256 formerTreasuryBefore = usds.balanceOf(address(trsry));
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 seizedCollateral) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(tokenOut, address(usds), "seizure pays USDS collateral");
        assertEq(keeperReward, preview.keeperReward, "seizure returns keeper reward");
        assertEq(
            seizedCollateral,
            preview.collateralToTreasury,
            "seizure returns Treasury obligation"
        );
        vm.clearMockedCalls();
        _deactivatePolicy(address(burnerLoans));
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));

        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        // The call reverts before a return value can exist.
        // forge-lint: disable-next-line(unused-return)
        burnerLoans.transferPendingPayout(address(usds), address(newTreasury));
        _activatePolicy(address(burnerLoans));
        uint256 transferred = burnerLoans.transferPendingPayout(
            address(usds),
            address(newTreasury)
        );
        assertEq(transferred, preview.collateralToTreasury, "retry reports seized collateral");

        assertEq(
            usds.balanceOf(address(trsry)),
            formerTreasuryBefore,
            "former Treasury receives no collateral"
        );
        assertEq(
            usds.balanceOf(address(newTreasury)),
            preview.collateralToTreasury,
            "new Treasury receives collateral"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(newTreasury)),
            0,
            "pending collateral clears"
        );
    }
}
