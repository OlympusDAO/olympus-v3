// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";

contract MonoCoolerBorrowTest is MonoCoolerBaseTest {
    event Borrow(
        address indexed caller,
        address indexed onBehalfOf, 
        address indexed recipient, 
        uint128 amount
    );

    function test_borrow_failPaused() public {
        vm.startPrank(OVERSEER);
        cooler.setBorrowPaused(true);

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.Paused.selector));
        cooler.borrow(1_000e18, ALICE, ALICE);
    }

    function test_borrow_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.borrow(0, ALICE, ALICE);
    }

    function test_borrow_failBadRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidAddress.selector));
        cooler.borrow(100, ALICE, address(0));
    }

    function test_borrow_success_newBorrow_sameRecipient() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), borrowAmount);
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
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
                    debtCheckpoint: borrowAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.994170933333333333e18,
                    currentLtv: 1_500e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount,
                    currentLtv: 1_500e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount, 1e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();
        assertEq(prevTimestamp, START_TIMESTAMP);

        // Continous interest for 1yr == 15k * (exp(0.005) - 1)
        uint128 expectedInterest = 75.187812891015945e18;
        skip(365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount);
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
                    debtCheckpoint: borrowAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.984224964309985202e18,
                    currentLtv: 1_500e18 + 7.5187812891015945e18,
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
                    currentLtv: 1_500e18 + 7.5187812891015945e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount + expectedInterest, 1.005012520859401063e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount + expectedInterest);
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
                    debtCheckpoint: borrowAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.984224964309985202e18,
                    currentLtv: 1_500e18 + 7.5187812891015945e18,
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
                    currentLtv: 1_500e18 + 7.5187812891015945e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount + expectedInterest, 1.005012520859401063e27);
        }
    }

    function test_borrow_success_newBorrow_diffRecipient() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, BOB, borrowAmount);
        cooler.borrow(borrowAmount, ALICE, BOB);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(cooler.totalDebt(), borrowAmount);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
        assertEq(usds.balanceOf(ALICE), 0);
        assertEq(usds.balanceOf(BOB), borrowAmount);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: borrowAmount,
                interestAccumulatorRay: 1e27
            })
        );

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: borrowAmount,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.994170933333333333e18,
                currentLtv: 1_500e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: borrowAmount,
                currentLtv: 1_500e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );

        checkGlobalState(borrowAmount, 1e27);
    }

    // Same result as test_borrow_success_newBorrow_sameRecipient
    function test_borrow_twice_immediately() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 10_000e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE, ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE, ALICE);

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount * 2);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.4956282e18,
                    currentLtv: 2_000e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2,
                    currentLtv: 2_000e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount * 2, 1e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();

        // Continous interest for 1yr == 20,000 * (exp(0.005) - 1)
        // ACTUAL via excel:       100.250417188019
        uint128 expectedInterest = 100.25041718802126e18;
        skip(365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2);
            assertEq(cooler.interestAccumulatorUpdatedAt(), prevTimestamp);
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount * 2);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.488168723232488902e18,
                    currentLtv: 2_000e18 + 10.025041718802126e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    currentLtv: 2_000e18 + 10.025041718802126e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.005012520859401063e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + expectedInterest);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.005012520859401063e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount * 2);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.488168723232488902e18,
                    currentLtv: 2_000e18 + 10.025041718802126e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    currentLtv: 2_000e18 + 10.025041718802126e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.005012520859401063e27);
        }
    }

    // Same result as test_borrow_success_newBorrow_sameRecipient
    function test_borrow_twice_1dayLater() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 10_000e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE, ALICE);

        skip(1 days);

        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE, ALICE);

        // 10k * e^(0.05/365)
        uint128 interestDelta = 0.13698723963648e18;

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + interestDelta);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.000013698723963648e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount * 2);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2 + interestDelta,
                    interestAccumulatorRay: 1.000013698723963648e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + interestDelta,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.495617955971233037e18,
                    currentLtv: 2_000e18 + interestDelta/10,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + interestDelta,
                    currentLtv: 2_000e18 + interestDelta/10,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount * 2 + interestDelta, 1.000013698723963648e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();

        // Continous interest for 1yr == 20,000.14 * e^(0.005)
        uint128 expectedInterest = 100.388091079053889629e18;
        skip(365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + interestDelta);
            assertEq(cooler.interestAccumulatorUpdatedAt(), prevTimestamp);
            assertEq(cooler.interestAccumulatorRay(), 1.000013698723963648e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount * 2);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2 + interestDelta,
                    interestAccumulatorRay: 1.000013698723963648e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.488158530296028565e18,
                    currentLtv: 2_000e18 + 10.038809107905388963e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    currentLtv: 2_000e18 + 10.038809107905388963e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.005026288248504325962809062e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        assertEq(vm.getBlockTimestamp(), START_TIMESTAMP + 1 days + 365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + expectedInterest);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.005026288248504325962809062e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowAmount * 2);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2 + interestDelta,
                    interestAccumulatorRay: 1.000013698723963648e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.488158530296028565e18,
                    currentLtv: 2_000e18 + 10.038809107905388963e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    currentLtv: 2_000e18 + 10.038809107905388963e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.005026288248504325962809062e27);
        }
    }

    function test_borrow_notEnoughDebt_single() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 1_000e18 - 1;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IMonoCooler.MinDebtNotMet.selector, 1_000e18, 1_000e18 - 1)
        );
        cooler.borrow(borrowAmount, ALICE, ALICE);
    }

    function test_borrow_fail_originationLtv() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 29_616.4e18 + 1;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.ExceededMaxOriginationLtv.selector,
                2_961.64e18 + 1,
                2_961.64e18
            )
        );
        cooler.borrow(borrowAmount, ALICE, ALICE);
    }

    function test_borrow_success_maxBorrow() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = type(uint128).max;
        int128 expectedMaxBorrow = 29_616.4e18;
        uint128 borrowedAmount = uint128(expectedMaxBorrow);

        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0), 0);
        assertEq(
            cooler.debtDeltaForMaxOriginationLtv(ALICE, int128(collateralAmount)),
            expectedMaxBorrow
        );
        addCollateral(ALICE, collateralAmount);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0), expectedMaxBorrow);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, ALICE, borrowedAmount);
        uint128 borrowed = cooler.borrow(borrowAmount, ALICE, ALICE);
        assertEq(borrowed, borrowedAmount);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(usds, address(cooler)), 0);
            assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), borrowedAmount);
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowedAmount);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(usds.balanceOf(ALICE), borrowedAmount);
            assertEq(usds.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowedAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowedAmount,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.01e18,
                    currentLtv: DEFAULT_OLTV,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowedAmount,
                    currentLtv: DEFAULT_OLTV,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkGlobalState(borrowedAmount, 1e27);
        }
    }

    function test_borrow_fail_maxBorrow_overOriginationLtv() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = type(uint128).max;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        cooler.borrow(borrowAmount, ALICE, ALICE);

        // Second time fails - already at origination LTV
        IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
        assertEq(position.currentLtv, DEFAULT_OLTV);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.ExceededMaxOriginationLtv.selector,
                DEFAULT_OLTV,
                DEFAULT_OLTV
            )
        );
        cooler.borrow(borrowAmount, ALICE, ALICE);

        // Same moving forward in time.
        skip(1 days);
        position = cooler.accountPosition(ALICE);
        assertGt(position.currentLtv, DEFAULT_OLTV);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.ExceededMaxOriginationLtv.selector,
                2_961.680570688839698463e18,
                DEFAULT_OLTV
            )
        );
        cooler.borrow(borrowAmount, ALICE, ALICE);
    }

    function test_borrow_onBehalfOf_fail_noAuthorization() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnathorizedOnBehalfOf.selector));
        cooler.borrow(100, ALICE, ALICE);
    }

    function test_borrow_onBehalfOf_withAuthorization() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = type(uint128).max;
        int128 expectedMaxBorrow = 29_616.4e18;
        uint128 borrowedAmount = uint128(expectedMaxBorrow);

        addCollateral(ALICE, collateralAmount);

        // Alice gives approval for BOB to addCollateral and delegate
        vm.prank(ALICE);
        cooler.setAuthorization(BOB, uint96(block.timestamp + 1 days));

        vm.startPrank(BOB);
        vm.expectEmit(address(cooler));
        emit Borrow(BOB, ALICE, BOB, borrowedAmount);
        uint128 borrowed = cooler.borrow(borrowAmount, ALICE, BOB);
        assertEq(borrowed, borrowedAmount);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(cooler.totalDebt(), borrowedAmount);
        checkGlobalState(borrowedAmount, 1e27);

        // ALICE
        {
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(usds.balanceOf(ALICE), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowedAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowedAmount,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.01e18,
                    currentLtv: DEFAULT_OLTV,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: borrowedAmount,
                    currentLtv: DEFAULT_OLTV,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );
        }

        // BOB
        {
            assertEq(gohm.balanceOf(BOB), 0);
            assertEq(usds.balanceOf(BOB), borrowedAmount);

            checkAccountState(
                BOB,
                IMonoCooler.AccountState({
                    collateral: 0,
                    debtCheckpoint: 0,
                    interestAccumulatorRay: 0
                })
            );

            checkAccountPosition(
                BOB,
                IMonoCooler.AccountPosition({
                    collateral: 0,
                    currentDebt: 0,
                    maxOriginationDebtAmount: 0,
                    liquidationDebtAmount: 0,
                    healthFactor: type(uint256).max,
                    currentLtv: type(uint128).max,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                BOB,
                IMonoCooler.LiquidationStatus({
                    collateral: 0,
                    currentDebt: 0,
                    currentLtv: type(uint128).max,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );
        }
    }

}
