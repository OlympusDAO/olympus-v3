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
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = 4_000e18 + 1;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IMonoCooler.MinDebtNotMet.selector, 1_000e18, 1_000e18 - 1)
        );
        cooler.repay(repayAmount, ALICE);
    }

    function test_repay_failNoApproval() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = borrowAmount;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        cooler.repay(repayAmount, ALICE);
    }

    function test_repay_success_full() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = borrowAmount;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        assertEq(dai.balanceOf(ALICE), repayAmount);
        dai.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(dai, address(cooler)), 0);
            assertEq(TRSRY.withdrawApproval(address(cooler), dai), 0);
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
            assertEq(dai.balanceOf(ALICE), 0);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
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
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = borrowAmount + 1e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(ALICE);
        dai.approve(address(cooler), borrowAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, borrowAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(dai, address(cooler)), 0);
            assertEq(TRSRY.withdrawApproval(address(cooler), dai), 0);
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
            assertEq(dai.balanceOf(ALICE), 0);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
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
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = 1_000e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);
        deal(address(dai), BOB, repayAmount);

        vm.startPrank(BOB);
        dai.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(BOB, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(dai, address(cooler)), 4_000e18);
            assertEq(TRSRY.withdrawApproval(address(cooler), dai), 0);
            assertEq(sdai.balanceOf(address(TRSRY)), INITIAL_TRSRY_MINT - 4_000e18);
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
            assertEq(dai.balanceOf(ALICE), 5_000e18);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 2.35e18,
                    currentLtv: 0.4e18,
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
                    currentLtv: 0.4e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(4_000e18, 1e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();

        // Continous interest for 1yr == 5,000 * (exp(0.005) - 1)
        uint128 expectedInterest = 20.05008332111928e18;
        vm.warp(START_TIMESTAMP + 365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 4_000e18);
            assertEq(cooler.interestAccumulatorUpdatedAt(), prevTimestamp);
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 2.338279326170557419e18,
                    currentLtv: 0.402005008332111928e18,
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
                    currentLtv: 0.402005008332111928e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(4_000e18 + expectedInterest, 1.00501252083027982e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 4_000e18 + expectedInterest);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.00501252083027982e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 2.338279326170557419e18,
                    currentLtv: 0.402005008332111928e18,
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
                    currentLtv: 0.402005008332111928e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(4_000e18 + expectedInterest, 1.00501252083027982e27);
        }
    }

    function test_repay_success_partialNotEnoughDebt() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = 4_000e18 + 1e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.warp(START_TIMESTAMP + 1 days);

        vm.startPrank(ALICE);
        dai.approve(address(cooler), repayAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.MinDebtNotMet.selector,
                1_000e18,
                999.068493619421305000e18
            )
        );
        cooler.repay(repayAmount, ALICE);
    }

    function test_repay_success_partialWithDelay() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = 4_000e18 + 123;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.warp(START_TIMESTAMP + 1 days);

        vm.startPrank(ALICE);
        dai.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(dai, address(cooler)), 999.999999999999999877e18);
            assertEq(TRSRY.withdrawApproval(address(cooler), dai), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 1_000.068493619421304877e18);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.000013698723884261e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), 999.999999999999999877e18);
            assertEq(dai.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 1_000.068493619421304877e18,
                    interestAccumulatorRay: 1.000013698723884261e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 1_000.068493619421304877e18,
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 9.399356204073352918e18,
                    currentLtv: 0.100006849361942131e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 1_000.068493619421304877e18,
                    currentLtv: 0.100006849361942131e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(1_000.068493619421304877e18, 1.000013698723884261e27);
        }
    }

    function test_repay_success_afterUnhealthy() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 9_300e18;
        uint128 repayAmount = 1_000e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        // Only becomes unhealthy about 2 years and 2 months later (!)
        vm.warp(START_TIMESTAMP + 2 * 365 days + 60 days);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 9_401.190384477093159900e18,
                currentLtv: 0.940119038447709316e18,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true
            })
        );

        vm.startPrank(ALICE);
        dai.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(dai, address(cooler)), 8_300e18);
            assertEq(TRSRY.withdrawApproval(address(cooler), dai), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), 8_401.190384477093159900e18);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.010880686502913243e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), 8_300e18);
            assertEq(dai.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 8_401.190384477093159900e18,
                    interestAccumulatorRay: 1.010880686502913243e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 8_401.190384477093159900e18,
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.118889058551560814e18,
                    currentLtv: 0.840119038447709316e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: 8_401.190384477093159900e18,
                    currentLtv: 0.840119038447709316e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(8_401.190384477093159900e18, 1.010880686502913243e27);
        }
    }

    function test_repay_success_evenWhenPaused() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        uint128 repayAmount = 1_000e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, borrowAmount, ALICE);

        vm.startPrank(OVERSEER);
        cooler.setLiquidationsPaused(true);
        cooler.setBorrowPaused(true);

        vm.startPrank(ALICE);
        dai.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(ALICE, ALICE, repayAmount);
        cooler.repay(repayAmount, ALICE);
    }
}
