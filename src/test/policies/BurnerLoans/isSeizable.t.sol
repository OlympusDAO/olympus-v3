// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

contract BurnerLoansIsSeizableTest is BurnerLoansBorrowTestBase {
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _position(
        uint256 collateral_,
        uint256 debt_,
        uint48 maturity_
    ) internal pure returns (IBurnerLoans.Position memory) {
        return
            IBurnerLoans.Position({
                depositedCollateral: collateral_,
                debtOhm: debt_,
                maturity: maturity_,
                lastBorrowBlock: 0,
                status: debt_ == 0
                    ? IBurnerLoans.PositionStatus.NoDebt
                    : IBurnerLoans.PositionStatus.Active
            });
    }

    function test_givenHealthyActivePosition_isSeizable_returnsFalse() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "healthy position");
    }

    function test_givenHealthBelowOneWad_isSeizable_returnsTrue() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(1_149e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "unhealthy position");
    }

    function test_givenHealthExactlyOneWad_isSeizable_returnsFalse() public {
        // debt value = 100 OHM * $10 = $1,000
        // required collateral = $1,000 * 11,500 / 10,000 = $1,150
        // health = $1,150 / $1,150 = 1e18
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(1_150e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "exact health boundary");
    }

    function test_givenMaturedHealthyPosition_isSeizable_returnsTrue() public {
        uint48 maturity = uint48(block.timestamp + 1 days);
        burnerLoans.setPositionForTest(address(usds), alice, _position(2_000e18, 100e9, maturity));
        vm.warp(maturity);
        price.setTimestamp(uint48(block.timestamp));

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "matured position");
    }

    function test_givenDebtFreePosition_isSeizable_returnsFalseWithoutPriceRead() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 0, uint48(block.timestamp + 30 days))
        );
        vm.warp(block.timestamp + 9 hours);

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "debt-free position");
    }

    function test_givenStalePrice_isSeizable_reverts() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.isSeizable(address(usds), alice);
    }

    function test_givenMissingMarket_isSeizable_reverts() public {
        address otherAsset = makeAddr("otherAsset");

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, otherAsset)
        );
        burnerLoans.isSeizable(otherAsset, alice);
    }

    function test_givenAmbiguousMarket_isSeizable_reverts() public {
        _createDuplicateUsdsMarketForTest();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(usds),
                2
            )
        );
        burnerLoans.isSeizable(address(usds), alice);
    }
}
