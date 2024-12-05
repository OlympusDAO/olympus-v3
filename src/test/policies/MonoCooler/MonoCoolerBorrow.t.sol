// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";

contract MonoCoolerBorrowTest is MonoCoolerBaseTest {
    event Borrow(address indexed account, address indexed recipient, uint128 amount);

    function test_borrow_failPaused() public {
        vm.startPrank(OVERSEER);
        cooler.setBorrowPaused(true);

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.Paused.selector));
        cooler.borrow(1_000e18, ALICE);
    }

    function test_borrow_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.borrow(0, ALICE);
    }

    function test_borrow_failBadRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidAddress.selector));
        cooler.borrow(100, address(0));
    }

    function test_borrow_success_newBorrow_sameRecipient() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(dai, address(cooler)), borrowAmount);
            assertEq(TRSRY.withdrawApproval(address(cooler), dai), 0);
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
            assertEq(dai.balanceOf(ALICE), borrowAmount);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.88e18,
                    currentLtv: 0.5e18,
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
                    currentLtv: 0.5e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount, 1e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();
        assertEq(prevTimestamp, START_TIMESTAMP);

        // Continous interest for 1yr == 5,000 * (exp(0.005) - 1)
        uint128 expectedInterest = 25.0626041513991e18;
        skip(365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount);
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
                    debtCheckpoint: borrowAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest,
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.870623460936445935e18,
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
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
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount + expectedInterest, 1.00501252083027982e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount + expectedInterest);
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
                    debtCheckpoint: borrowAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount + expectedInterest,
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.870623460936445935e18,
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
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
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount + expectedInterest, 1.00501252083027982e27);
        }
    }

    function test_borrow_success_newBorrow_diffRecipient() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 5_000e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, BOB, borrowAmount);
        cooler.borrow(borrowAmount, BOB);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(cooler.totalDebt(), borrowAmount);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
        assertEq(dai.balanceOf(ALICE), 0);
        assertEq(dai.balanceOf(BOB), borrowAmount);

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
                maxOriginationDebtAmount: 9_300e18,
                liquidationDebtAmount: 9_400e18,
                healthFactor: 1.88e18,
                currentLtv: 0.5e18,
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
                currentLtv: 0.5e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowAmount, 1e27);
    }

    // Same result as test_borrow_success_newBorrow_sameRecipient
    function test_borrow_twice_immediately() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 2_500e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE);

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount * 2);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.88e18,
                    currentLtv: 0.5e18,
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
                    currentLtv: 0.5e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount * 2, 1e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();

        // Continous interest for 1yr == 5,000 * (exp(0.005) - 1)
        // ACTUAL via excel:       25.0626042970048
        uint128 expectedInterest = 25.0626041513991e18;
        skip(365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2);
            assertEq(cooler.interestAccumulatorUpdatedAt(), prevTimestamp);
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount * 2);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.870623460936445935e18,
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
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
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.00501252083027982e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + expectedInterest);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.00501252083027982e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount * 2);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.870623460936445935e18,
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
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
                    currentLtv: 0.5e18 + 0.0025062604151399100e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.00501252083027982e27);
        }
    }

    // Same result as test_borrow_success_newBorrow_sameRecipient
    function test_borrow_twice_1dayLater() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 2_500e18;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE);

        skip(1 days);

        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, borrowAmount);
        cooler.borrow(borrowAmount, ALICE);

        uint128 interestDelta = 0.034246809710652500e18;

        // Immediate checks
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + interestDelta);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.000013698723884261e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount * 2);
            assertEq(dai.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2 + interestDelta,
                    interestAccumulatorRay: 1.000013698723884261e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + interestDelta,
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.879987123287746057e18,
                    currentLtv: 0.500003424680971066e18,
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
                    currentLtv: 0.500003424680971066e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount * 2 + interestDelta, 1.000013698723884261e27);
        }

        // Checks 365 days later
        uint256 prevTimestamp = vm.getBlockTimestamp();

        // Continous interest for 1yr == 5,000 * (exp(0.005) - 1)
        uint128 expectedInterest = 25.097022623956797775e18;
        skip(365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + interestDelta);
            assertEq(cooler.interestAccumulatorUpdatedAt(), prevTimestamp);
            assertEq(cooler.interestAccumulatorRay(), 1.000013698723884261e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount * 2);
            assertEq(dai.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2 + interestDelta,
                    interestAccumulatorRay: 1.000013698723884261e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.870610648447061918e18,
                    currentLtv: 0.502509702262395680e18,
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
                    currentLtv: 0.502509702262395680e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.005026288219302899109948573e27);
        }

        // Manually checkpoint and check again
        cooler.checkpointDebt();
        assertEq(vm.getBlockTimestamp(), START_TIMESTAMP + 1 days + 365 days);
        {
            assertEq(cooler.totalCollateral(), collateralAmount);
            assertEq(cooler.totalDebt(), borrowAmount * 2 + expectedInterest);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.005026288219302899109948573e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
            assertEq(dai.balanceOf(ALICE), borrowAmount * 2);
            assertEq(dai.balanceOf(BOB), 0);

            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: borrowAmount * 2 + interestDelta,
                    interestAccumulatorRay: 1.000013698723884261e27
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: borrowAmount * 2 + expectedInterest,
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.870610648447061918e18,
                    currentLtv: 0.502509702262395680e18,
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
                    currentLtv: 0.502509702262395680e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowAmount * 2 + expectedInterest, 1.005026288219302899109948573e27);
        }
    }

    function test_borrow_notEnoughDebt_single() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 1_000e18 - 1;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IMonoCooler.MinDebtNotMet.selector, 1_000e18, 1_000e18 - 1)
        );
        cooler.borrow(borrowAmount, ALICE);
    }

    function test_borrow_fail_originationLtv() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = 9_300e18 + 1;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.ExceededMaxOriginationLtv.selector,
                0.93e18 + 1,
                0.93e18
            )
        );
        cooler.borrow(borrowAmount, ALICE);
    }

    function test_borrow_success_maxBorrow() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = type(uint128).max;
        int128 expectedMaxBorrow = 9_300e18;
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
        emit Borrow(ALICE, ALICE, borrowedAmount);
        uint128 borrowed = cooler.borrow(borrowAmount, ALICE);
        assertEq(borrowed, borrowedAmount);

        // Treasury Checks
        {
            assertEq(TRSRY.reserveDebt(dai, address(cooler)), borrowedAmount);
            assertEq(TRSRY.withdrawApproval(address(cooler), dai), 0);
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
            assertEq(dai.balanceOf(ALICE), borrowedAmount);
            assertEq(dai.balanceOf(BOB), 0);

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
                    maxOriginationDebtAmount: 9_300e18,
                    liquidationDebtAmount: 9_400e18,
                    healthFactor: 1.010752688172043010e18,
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
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowedAmount, 1e27);
        }
    }

    function test_borrow_fail_maxBorrow_overOriginationLtv() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = type(uint128).max;
        addCollateral(ALICE, collateralAmount);

        vm.startPrank(ALICE);
        cooler.borrow(borrowAmount, ALICE);

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
        cooler.borrow(borrowAmount, ALICE);

        // Same moving forward in time.
        skip(1 days);
        position = cooler.accountPosition(ALICE);
        assertGt(position.currentLtv, DEFAULT_OLTV);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.ExceededMaxOriginationLtv.selector,
                0.930012739813212363e18,
                DEFAULT_OLTV
            )
        );
        cooler.borrow(borrowAmount, ALICE);
    }
}
