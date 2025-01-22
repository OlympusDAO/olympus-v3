// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";

contract MonoCoolerRepayTest is MonoCoolerBaseTest {
    event Repay(address indexed fundedBy, address indexed onBehalfOf, uint128 repayAmount);

    function test_repay_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.repay(0, ALICE);
    }

    function test_repay_failBadOnBehalfOf() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidAddress.selector));
        cooler.repay(100, address(0));
    }

    function test_repay_failNoDebt() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.repay(100, ALICE);
    }

    function test_repay_failUnderMinRequired() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = 14_000e18 + 1;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IMonoCooler.MinDebtNotMet.selector, 1_000e18, 1_000e18 - 1)
        );
        cooler.repay(repayAmount, ALICE);
    }

    function test_repay_failNoApproval() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = borrowAmount;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        cooler.repay(repayAmount, ALICE);
    }

    function test_repay_success_full() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = borrowAmount;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        assertEq(usds.balanceOf(ALICE), repayAmount);
        usds.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(usds, address(cooler)), 0);
            assertEq(TRSRY.withdrawApproval(address(cooler), usds), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 0);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), 0);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 0,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 0,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: type(uint256).max,
                    currentLtv: 0,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 0,
                    currentLtv: 0,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(0, 1e27);
        }
    }

    function test_repay_success_overFull() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = borrowAmount + 1e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        usds.approve(address(cooler), borrowAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, borrowAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(usds, address(cooler)), 0);
            assertEq(TRSRY.withdrawApproval(address(cooler), usds), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 0);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), 0);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 0,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 0,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: type(uint256).max,
                    currentLtv: 0,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 0,
                    currentLtv: 0,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(0, 1e27);
        }
    }

    function test_repay_success_partial_onBehalfOf() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = 11_000e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);
        deal(address(usds), BOB, repayAmount);

        vm.startPrank(BOB);
        usds.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(BOB, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(usds, address(cooler)), 4_000e18);
            assertEq(TRSRY.withdrawApproval(address(cooler), usds), 0);
            assertEq(susds.balanceOf(address(TRSRY)), INITIAL_TRSRY_MINT - 4_000e18);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 4_000e18);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), 15_000e18);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 4_000e18,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 4_000e18,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 7.478141e18,
                    currentLtv: 400e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 4_000e18,
                    currentLtv: 400e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(4_000e18, 1e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();

        // Continous interest for 1yr == 4,000 * (exp(0.005) - 1)
        uint128 expectedInterest = 20.050083437604252000e18;
        vm.warp(START_TIMESTAMP + 365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 4_000e18);
            assertEq(cooler.interestAccumulatorUpdatedAt(), prevTimestamp);
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 4_000e18,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 4_000e18 + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 7.440843616162444510e18,
                    currentLtv: 402.005008343760425200e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 4_000e18 + expectedInterest,
                    currentLtv: 402.005008343760425200e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(4_000e18 + expectedInterest, 1.005012520859401063e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 4_000e18 + expectedInterest);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.005012520859401063e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 4_000e18,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 4_000e18 + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 7.440843616162444510e18,
                    currentLtv: 402.005008343760425200e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 4_000e18 + expectedInterest,
                    currentLtv: 402.005008343760425200e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(4_000e18 + expectedInterest, 1.005012520859401063e27);
        }
    }

    function test_repay_success_partialNotEnoughDebt() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = 14_000e18 + 1.5e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.warp(START_TIMESTAMP + 1 days);

        vm.startPrank(ALICE);
        usds.approve(address(cooler), repayAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.MinDebtNotMet.selector,
                1_000e18,
                998.705480859454720000e18
            )
        );
        cooler.repay(repayAmount, ALICE);
    }

    function test_repay_success_partialWithDelay() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = 14_000e18 + 123;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.warp(START_TIMESTAMP + 1 days);

        vm.startPrank(ALICE);
        usds.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(usds, address(cooler)), 999.999999999999999877e18);
            assertEq(TRSRY.withdrawApproval(address(cooler), usds), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 1_000.205480859454719877e18);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.000013698723963648e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), 999.999999999999999877e18);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 1_000.205480859454719877e18,
                    interestAccumulatorRay: 1.000013698723963648e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 1_000.205480859454719877e18,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 29.906418803361072571e18,
                    currentLtv: 100.020548085945471988e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 1_000.205480859454719877e18,
                    currentLtv: 100.020548085945471988e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(1_000.205480859454719877e18, 1.000013698723963648e27);
        }
    }

    function test_repay_success_afterUnhealthy() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 29_616.4e18;
        uint128 repayAmount = 1_000e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        // Only becomes unhealthy a litle under 2 years later (!)
        uint128 expectedInterest = 296.420449180681035496e18;
        {
            vm.warp(START_TIMESTAMP + 365 days + 361 days);
            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 29_912.410687323588075754e18,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.000005125386850779e18,
                    currentLtv: 2_991.241068732358807576e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );
            skip(1 days);
            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 0.999991426780329299e18,
                    currentLtv: 2_991.282044918068103550e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );
            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest,
                    currentLtv: 2_991.282044918068103550e18,
                    exceededLiquidationLtv: true,
                    exceededMaxOriginationLtv: true
                })
            );
        }

        vm.startPrank(ALICE);
        usds.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(usds, address(cooler)), borrowAmount - repayAmount);
            assertEq(TRSRY.withdrawApproval(address(cooler), usds), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount + expectedInterest - repayAmount);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.01000865902610314e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount - repayAmount);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount + expectedInterest - repayAmount,
                    interestAccumulatorRay: 1.01000865902610314e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest - repayAmount,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.034577863220800005e18,
                    currentLtv: 2_891.282044918068103550e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest - repayAmount,
                    currentLtv: 2_891.282044918068103550e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount + expectedInterest - repayAmount, 1.01000865902610314e27);
        }
    }

    function test_repay_success_evenWhenPaused() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        uint128 repayAmount = 1_000e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(OVERSEER);
        cooler.setLiquidationsPaused(true);
        cooler.setBorrowPaused(true);

        vm.startPrank(ALICE);
        usds.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);
    }
}
