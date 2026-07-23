// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

contract BurnerLoansPreviewExtendTest is BurnerLoansBorrowTestBase {
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function setUp() public override {
        super.setUp();
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 2_000e18,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );
    }

    function test_givenHealthyPosition_previewExtendReturnsFeeMaturityAndHealth() public view {
        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        assertGt(preview.fee, 0, "fee");
        assertEq(preview.maturity, block.timestamp + 60 days, "maturity");
        assertGt(preview.healthFactor, 1e18, "health");
        assertTrue(preview.executable, "executable");
    }

    function test_givenZeroTerms_previewExtendReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.previewExtend(address(usds), alice, 0);
    }

    function test_givenNoDebt_previewExtendReverts() public {
        address bob = makeAddr("bob");
        burnerLoans.setPositionForTest(
            address(usds),
            bob,
            IBurnerLoans.Position({
                depositedCollateral: 1e18,
                debtOhm: 0,
                maturity: 0,
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );

        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.previewExtend(address(usds), bob, 1);
    }

    function test_givenAmbiguousMarket_previewExtendReverts() public {
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    function test_givenMissingMarket_previewExtendReverts() public {
        address unknownAsset = makeAddr("unknown asset");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unknownAsset
            )
        );
        burnerLoans.previewExtend(unknownAsset, alice, 1);
    }

    function test_givenAssetDisabled_previewExtendReverts() public {
        vm.prank(burnerLoansAdmin);
        burnerLoans.disableAsset(address(usds));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotEnabled.selector, address(usds))
        );
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    function test_givenGlobalPolicyDisabled_previewExtendReverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    function test_givenStalePrice_previewExtendReverts() public {
        vm.warp(block.timestamp + 1 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    function test_givenUnavailablePrice_previewExtendReverts() public {
        price.setPrice(address(usds), 0);

        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    function test_givenUnhealthyPosition_previewExtendReverts() public {
        price.setPrice(address(usds), 0.1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnhealthyPosition.selector,
                173_913_043_478_260_869
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 1);
    }

    function test_givenExtensionBeyondHorizon_previewExtendReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_MaturityHorizonExceeded.selector,
                block.timestamp + 120 days,
                block.timestamp + 90 days
            )
        );
        burnerLoans.previewExtend(address(usds), alice, 3);
    }

    function test_givenMaturedHealthyPosition_previewExtendUsesCurrentTimestampAsBase() public {
        vm.warp(block.timestamp + 31 days);
        price.setTimestamp(uint48(block.timestamp));

        IBurnerLoans.ExtendPreview memory preview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        assertEq(preview.maturity, block.timestamp + 30 days, "maturity from current time");
    }

    function test_givenTwoTerms_previewExtendReturnsLinearFee() public view {
        IBurnerLoans.ExtendPreview memory single = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        IBurnerLoans.ExtendPreview memory doubleTerm = burnerLoans.previewExtend(
            address(usds),
            alice,
            2
        );

        assertEq(doubleTerm.fee, single.fee * 2, "linear fee");
        assertEq(doubleTerm.maturity, single.maturity + 30 days, "second term");
    }
}
