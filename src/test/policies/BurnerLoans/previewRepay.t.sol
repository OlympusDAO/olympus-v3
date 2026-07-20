// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansPreviewRepayTest is BurnerLoansTest {
    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 1_000e6,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );
        vm.roll(block.number + 1);
    }

    function test_givenPartialRepayment_previewRepayReturnsConservativeQuote() public view {
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            40e9,
            alice
        );
        assertEq(preview.repayAmount, 40e9, "repay amount");
        assertEq(preview.remainingDebtOhm, 60e9, "remaining debt");
        assertEq(preview.resultingHealthFactor, 0, "unknown health sentinel");
        assertTrue(preview.executable, "executable");
    }

    function test_givenFullRepayment_previewRepayReturnsDebtFreeHealth() public view {
        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            100e9,
            alice
        );
        assertEq(preview.remainingDebtOhm, 0, "remaining debt");
        assertEq(preview.resultingHealthFactor, type(uint256).max, "health");
        assertTrue(preview.executable, "executable");
    }

    function test_givenAmountExceedsDebt_previewRepayReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_RepayExceedsDebt.selector,
                100e9 + 1,
                100e9
            )
        );
        burnerLoans.previewRepay(address(usds), 100e9 + 1, alice);
    }

    function test_givenZeroAmount_previewRepayReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewRepay(address(usds), 0, alice);
    }

    function test_givenAssetDisabledAndPriceStale_previewRepayRemainsExecutable() public {
        vm.prank(burnerLoansAdmin);
        burnerLoans.disableAsset(address(usds));
        vm.warp(block.timestamp + 10 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        IBurnerLoans.RepayPreview memory preview = burnerLoans.previewRepay(
            address(usds),
            1e9,
            alice
        );
        assertEq(preview.remainingDebtOhm, 99e9, "remaining debt");
        assertTrue(preview.executable, "executable");
    }

    function test_givenGlobalPolicyDisabled_previewRepayReverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewRepay(address(usds), 1e9, alice);
    }

    function test_givenAmbiguousMarket_previewRepayReverts() public {
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoans.previewRepay(address(usds), 1e9, alice);
    }
}
