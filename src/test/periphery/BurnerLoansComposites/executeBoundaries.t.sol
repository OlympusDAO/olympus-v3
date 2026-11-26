// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";

// Contracts
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";

contract BurnerLoansCompositesExecuteBoundariesTest is BurnerLoansCompositesGrantModesTest {
    // Scenarios: BLREX-N04.
    function test_whenPositiveDepositIsFunded(
        bool inlineGrant_,
        bool multiple_,
        uint128 amount_
    ) public {
        _assertDeposit(inlineGrant_, multiple_, uint128(bound(amount_, 1, type(uint128).max)));
    }

    // Scenarios: BLREX-N04.
    function test_whenDepositMatchesBoundarySeeds(bool inlineGrant_, bool multiple_) public {
        uint256 snapshot = vm.snapshotState();
        _assertDeposit(inlineGrant_, multiple_, 1);
        assertTrue(vm.revertToState(snapshot), "Restore one-unit deposit case");
        _assertDeposit(inlineGrant_, multiple_, type(uint128).max - 1);
        assertTrue(vm.revertToState(snapshot), "Restore maximum-minus-one deposit case");
        _assertDeposit(inlineGrant_, multiple_, type(uint128).max);
    }

    // Scenarios: BLREX-N04.
    function test_whenDepositTouchesPositionCreditLimit(
        bool inlineGrant_,
        bool multiple_,
        bool exceeds_
    ) public {
        _asset.mint(_borrower, type(uint128).max);
        _seedCollateral(type(uint128).max - 1);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        uint128 amount = exceeds_ ? 2 : 1;
        uint256 wallet = _asset.balanceOf(_borrower);
        if (exceeds_) vm.expectRevert(stdError.arithmeticError);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), amount),
            _single(_deposit(amount)),
            new IExecutor.Output[](0)
        );
        uint128 deposited = exceeds_ ? 0 : 1;
        _assertSettled(type(uint128).max - 1 + deposited, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            wallet - deposited,
            "Credit overflow rolls back additional funding"
        );
    }

    function _assertDeposit(bool inlineGrant_, bool multiple_, uint128 amount_) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _asset.mint(_borrower, amount_);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), amount_),
            _single(_deposit(amount_)),
            new IExecutor.Output[](0)
        );
        _assertSettled(amount_, 0);
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Deposited exact raw input");
    }

    // Scenarios: BLREX-N08.
    function test_givenCollateralPosition_whenBorrowAmountVaries(
        bool inlineGrant_,
        bool multiple_,
        uint8 limit_,
        uint128 amount_
    ) public givenCollateralPosition {
        uint8 limitType = limit_ % 3;
        uint128 limit = _setBorrowLimit(limitType);
        _assertBorrow(inlineGrant_, multiple_, limitType, limit, uint128(bound(amount_, 1, limit)));
    }

    // Scenarios: BLREX-N08.
    function test_givenCollateralPosition_whenBorrowMatchesBoundarySeeds(
        bool inlineGrant_,
        bool multiple_,
        uint8 limit_
    ) public givenCollateralPosition {
        uint8 limitType = limit_ % 3;
        uint128 limit = _setBorrowLimit(limitType);
        uint256 snapshot = vm.snapshotState();
        _assertBorrow(inlineGrant_, multiple_, limitType, limit, 1);
        assertTrue(vm.revertToState(snapshot), "Restore one-unit borrow case");
        _assertBorrow(inlineGrant_, multiple_, limitType, limit, limit - 1);
        assertTrue(vm.revertToState(snapshot), "Restore limit-minus-one borrow case");
        _assertBorrow(inlineGrant_, multiple_, limitType, limit, limit);
        assertTrue(vm.revertToState(snapshot), "Restore exact-limit borrow case");
        _assertBorrow(inlineGrant_, multiple_, limitType, limit, limit + 1);
        assertTrue(vm.revertToState(snapshot), "Restore limit-plus-one borrow case");
        _assertBorrow(inlineGrant_, multiple_, limitType, limit, type(uint128).max);
    }

    function _setBorrowLimit(uint8 limitType_) private returns (uint128) {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(0), uint256(0))
        );
        if (limitType_ == 1) {
            vm.prank(_fixtureAdmin);
            _config.setAssetDebtCap(address(_asset), 500e9);
            return 500e9;
        }
        if (limitType_ == 2) {
            vm.prank(_fixtureAdmin);
            _inventory.setGlobalDebtCap(500e9);
            return 500e9;
        }
        // Both assets price at 1e18 USD. Backing requires 125% collateral, giving
        // 2,000 / 1.25 = 1,600 OHM (9 decimals), tighter than 85% market LTV.
        return 1600e9;
    }

    function _assertBorrow(
        bool inlineGrant_,
        bool multiple_,
        uint8 limitType_,
        uint128 limit_,
        uint128 amount_
    ) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        if (amount_ > limit_) {
            if (limitType_ == 2 || amount_ == type(uint128).max) {
                uint256 capacity = limitType_ == 2 ? limit_ : 100_000e9;
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                        amount_,
                        capacity
                    )
                );
            } else if (limitType_ == 1) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IBurnerLoansDebt.BurnerLoans_AssetDebtCapExceeded.selector,
                        address(_asset),
                        amount_,
                        limit_
                    )
                );
            } else {
                // Raw OHM converts to PRICE decimals by x1e9. The 125% requirement
                // is exact here. Health floors (2,000e18 * 1e18) / required USD.
                uint256 requiredUsd = (uint256(amount_) * 1e9 * 125) / 100;
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition.selector,
                        (uint256(2000e18) * 1e18) / requiredUsd
                    )
                );
            }
        }
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_borrow(amount_, 0, _borrower)),
            new IExecutor.Output[](0)
        );
        uint128 expected = amount_ <= limit_ ? amount_ : 0;
        _assertSettled(2000e6, expected);
        assertEq(_ohm.balanceOf(_borrower), expected, "Wallet receives only admitted OHM");
    }

    // Scenarios: BLREX-N09.
    function test_givenOlderDebt_whenRepayAmountVaries(
        bool inlineGrant_,
        bool multiple_,
        bool grantless_,
        uint128 amount_
    ) public givenOlderDebt {
        _assertRepay(inlineGrant_, multiple_, grantless_, uint128(bound(amount_, 1, 100e9)));
    }

    // Scenarios: BLREX-N09.
    function test_givenOlderDebt_whenRepayMatchesBoundarySeeds(
        bool inlineGrant_,
        bool multiple_,
        bool grantless_
    ) public givenOlderDebt {
        uint128[6] memory amounts = [uint128(0), 1, 100e9 - 1, 100e9, 100e9 + 1, type(uint128).max];
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < amounts.length; ++i) {
            _assertRepay(inlineGrant_, multiple_, grantless_, amounts[i]);
            assertTrue(vm.revertToState(snapshot), "Restore repayment boundary case");
        }
    }

    function _assertRepay(
        bool inlineGrant_,
        bool multiple_,
        bool grantless_,
        uint128 amount_
    ) private {
        IExecutor.SignedGrant memory signed;
        if (!grantless_) signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        if (amount_ > 100e9) _ohm.mint(_borrower, amount_ - 100e9);
        IExecutor.Funding[] memory funding = _funding(address(_ohm), amount_);
        IExecutor.Operation[] memory operations = _single(_repay(amount_));
        uint256 supply = _ohm.totalSupply();
        uint256 wallet = _ohm.balanceOf(_borrower);
        if (grantless_) {
            vm.prank(_borrower);
            _ohm.approve(address(_executor), amount_);
        }
        if (amount_ == 0) {
            vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector);
        } else if (amount_ > 100e9) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansDebt.BurnerLoans_RepayExceedsDebt.selector,
                    amount_,
                    100e9
                )
            );
        }
        if (grantless_) {
            vm.prank(_borrower);
            _executor.execute(
                funding,
                operations,
                new IExecutor.Output[](0),
                IExecutor.FlashLoan(0, 0),
                type(uint48).max
            );
        } else {
            _executeGrantMode(inlineGrant_, signed, funding, operations, new IExecutor.Output[](0));
        }
        uint128 repaid = amount_ <= 100e9 ? amount_ : 0;
        _assertSettled(2000e6, 100e9 - repaid);
        assertEq(_ohm.totalSupply(), supply - repaid, "Only accepted repayment burns OHM");
        assertEq(
            _ohm.balanceOf(_borrower),
            wallet - repaid,
            "Wallet spends only accepted repayment"
        );
    }

    // Scenarios: BLREX-N10.
    function test_givenCollateralPosition_whenWithdrawalAmountVaries(
        bool inlineGrant_,
        bool multiple_,
        uint128 amount_
    ) public givenCollateralPosition {
        _assertWithdrawal(inlineGrant_, multiple_, uint128(bound(amount_, 1, 2000e6)), 0);
    }

    // Scenarios: BLREX-N10.
    function test_givenCollateralPosition_whenWithdrawalMatchesBoundarySeeds(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        uint128[5] memory amounts = [uint128(1), 2000e6 - 1, 2000e6, 2000e6 + 1, type(uint128).max];
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < amounts.length; ++i) {
            _assertWithdrawal(inlineGrant_, multiple_, amounts[i], 0);
            assertTrue(vm.revertToState(snapshot), "Restore withdrawal boundary case");
        }
    }

    // Scenarios: BLREX-N06.
    function test_givenCollateralPosition_whenWithdrawalMinimumVaries(
        bool inlineGrant_,
        bool multiple_,
        bool aboveOutput_,
        uint256 minimum_
    ) public givenCollateralPosition {
        uint256 minimum = aboveOutput_
            ? bound(minimum_, 101, type(uint256).max)
            : bound(minimum_, 0, 100);
        _assertWithdrawal(inlineGrant_, multiple_, 100, minimum);
    }

    // Scenarios: BLREX-N06.
    function test_givenCollateralPosition_whenWithdrawalMinimumMatchesBoundarySeeds(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        uint256[6] memory minimums = [uint256(0), 1, 99, 100, 101, type(uint256).max];
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < minimums.length; ++i) {
            _assertWithdrawal(inlineGrant_, multiple_, 100, minimums[i]);
            assertTrue(vm.revertToState(snapshot), "Restore minimum boundary case");
        }
    }

    function _assertWithdrawal(
        bool inlineGrant_,
        bool multiple_,
        uint128 amount_,
        uint256 minimum_
    ) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        if (amount_ > 2000e6) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansCollateral.BurnerLoans_InsufficientCollateral.selector,
                    amount_,
                    2000e6
                )
            );
        } else if (minimum_ > amount_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IExecutor.BurnerLoansComposites_InsufficientOutput.selector,
                    minimum_,
                    amount_
                )
            );
        }
        IExecutor.Operation memory operation = IExecutor.Operation(
            IExecutor.OperationKind.Withdraw,
            abi.encode(
                IExecutor.Withdraw(
                    address(_asset),
                    amount_,
                    address(_executor),
                    address(_asset),
                    minimum_
                )
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(operation),
            new IExecutor.Output[](0)
        );
        uint128 withdrawn = amount_ <= 2000e6 && minimum_ <= amount_ ? amount_ : 0;
        _assertSettled(2000e6 - withdrawn, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            8000e6 + withdrawn,
            "Wallet receives only admitted output"
        );
    }

    // Scenarios: BLREX-N05, BLREX-N11.
    function test_givenOlderDebt_whenExtensionTermsVary(
        bool inlineGrant_,
        bool multiple_,
        uint16 terms_
    ) public givenOlderDebt {
        _assertExtension(inlineGrant_, multiple_, uint16(bound(terms_, 1, type(uint16).max)), 7, 7);
    }

    // Scenarios: BLREX-N05, BLREX-N11.
    function test_givenOlderDebt_whenTermAndFeeMatchBoundarySeeds(
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        uint256 snapshot = vm.snapshotState();
        _assertExtension(inlineGrant_, multiple_, 1, 0, 1);
        assertTrue(vm.revertToState(snapshot), "Restore fee-minus-one case");
        _assertExtension(inlineGrant_, multiple_, 1, 1, 1);
        assertTrue(vm.revertToState(snapshot), "Restore exact fee case");
        _assertExtension(inlineGrant_, multiple_, 1, 2, 1);
        assertTrue(vm.revertToState(snapshot), "Restore fee-plus-one case");
        _assertExtension(inlineGrant_, multiple_, 2, type(uint256).max, 7);
        assertTrue(vm.revertToState(snapshot), "Restore exact maturity horizon case");
        _assertExtension(inlineGrant_, multiple_, type(uint16).max, type(uint256).max, 7);
    }

    // Scenarios: BLREX-N05, BLREX-N11.
    function test_givenOlderDebt_whenMaturityTouchesHorizon(
        bool inlineGrant_,
        bool multiple_,
        uint8 seed_
    ) public givenOlderDebt {
        // Three new terms extend the original 30 days to 120 days. Near day 30,
        // the resulting maturity is exactly within, or one second either side of 90 days away.
        vm.warp(uint256(_position().maturity) + (seed_ % 3) - 1);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _assertExtension(inlineGrant_, multiple_, 3, 7, 7);
    }

    function _assertExtension(
        bool inlineGrant_,
        bool multiple_,
        uint16 terms_,
        uint256 cap_,
        uint256 fee_
    ) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        uint256 maturity = _position().maturity;
        uint256 nextMaturity = maturity + uint256(terms_) * 30 days;
        uint256 horizon = vm.getBlockTimestamp() + 90 days;
        uint256 wallet = _asset.balanceOf(_borrower);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(fee_, uint256(0))
        );
        if (nextMaturity > horizon) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansDebt.BurnerLoans_MaturityHorizonExceeded.selector,
                    nextMaturity,
                    horizon
                )
            );
        } else if (cap_ < fee_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                    fee_,
                    cap_
                )
            );
        }
        IExecutor.Operation memory operation = IExecutor.Operation(
            IExecutor.OperationKind.Extend,
            abi.encode(IExecutor.Extend(address(_asset), terms_, cap_, address(0)))
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), fee_ + 1),
            _single(operation),
            new IExecutor.Output[](0)
        );
        bool accepted = nextMaturity <= horizon && cap_ >= fee_;
        _assertSettled(2000e6, 100e9);
        assertEq(
            _position().maturity,
            accepted ? nextMaturity : maturity,
            "Only valid extension moves maturity"
        );
        assertEq(
            _asset.balanceOf(_borrower),
            accepted ? wallet - fee_ : wallet,
            "Only accepted fee is spent"
        );
    }
}
