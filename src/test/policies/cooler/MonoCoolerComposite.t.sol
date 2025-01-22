// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";

contract MonoCoolerAddCollatAndBorrowTest is MonoCoolerBaseTest {
    event CollateralAdded(
        address indexed fundedBy,
        address indexed onBehalfOf,
        uint128 collateralAmount
    );
    event CollateralWithdrawn(
        address indexed account,
        address indexed recipient,
        uint128 collateralAmount
    );
    event DelegateEscrowCreated(
        address indexed caller,
        address indexed delegate,
        address indexed escrow
    );
    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);
    event Borrow(address indexed account, address indexed recipient, uint128 amount);
    event Repay(address indexed fundedBy, address indexed onBehalfOf, uint128 repayAmount);

    function test_addCollateralAndBorrow_successNew() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = type(uint128).max;
        uint128 borrowedAmount = 29_616.4e18;

        vm.startPrank(ALICE);
        gohm.mint(ALICE, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, int256(int128(collateralAmount)));
        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, BOB, borrowedAmount);
        uint128 borrowed = cooler.addCollateralAndBorrow(
            collateralAmount,
            borrowAmount,
            BOB,
            delegationRequest(BOB, collateralAmount)
        );
        assertEq(borrowed, borrowedAmount);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(cooler.totalDebt(), borrowedAmount);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(bobEscrow)), collateralAmount);
        assertEq(usds.balanceOf(ALICE), 0);
        assertEq(usds.balanceOf(BOB), borrowedAmount);

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
                currentLtv: 2_961.64e18,
                totalDelegated: collateralAmount,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: borrowedAmount,
                currentLtv: 2_961.64e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowedAmount, 1e27);
    }

    function test_addCollateralAndBorrow_successExisting() public {
        uint128 collateralAmount = 5e18;
        uint128 borrowAmount = type(uint128).max;
        uint128 borrowedAmount = 29_616.4e18;

        // Alice Borrows once
        vm.startPrank(ALICE);
        gohm.mint(ALICE, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);
        cooler.addCollateralAndBorrow(collateralAmount, borrowAmount, ALICE, noDelegationRequest());

        // And again
        gohm.mint(ALICE, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);
        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        vm.expectEmit(address(cooler));
        emit Borrow(ALICE, ALICE, borrowedAmount / 2);
        uint128 borrowed = cooler.addCollateralAndBorrow(
            collateralAmount,
            borrowAmount,
            ALICE,
            noDelegationRequest()
        );
        assertEq(borrowed, borrowedAmount / 2);

        assertEq(cooler.totalCollateral(), collateralAmount * 2);
        assertEq(cooler.totalDebt(), borrowedAmount);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount * 2);
        assertEq(usds.balanceOf(ALICE), borrowedAmount);
        assertEq(usds.balanceOf(BOB), 0);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount * 2,
                debtCheckpoint: borrowedAmount,
                interestAccumulatorRay: 1e27
            })
        );

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount * 2,
                currentDebt: borrowedAmount,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.01e18,
                currentLtv: 2_961.64e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount * 2,
                currentDebt: borrowedAmount,
                currentLtv: 2_961.64e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowedAmount, 1e27);
    }

    function test_addCollateralAndBorrowOnBehalfOf_successNew() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = type(uint128).max;
        uint128 borrowedAmount = 29_616.4e18;

        vm.startPrank(ALICE);
        gohm.mint(ALICE, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, BOB, collateralAmount);
        vm.expectEmit(address(cooler));
        emit Borrow(BOB, BOB, borrowedAmount);
        uint128 borrowed = cooler.addCollateralAndBorrowOnBehalfOf(
            BOB,
            collateralAmount,
            borrowAmount
        );
        assertEq(borrowed, borrowedAmount);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(cooler.totalDebt(), borrowedAmount);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(usds.balanceOf(ALICE), 0);
        assertEq(usds.balanceOf(BOB), borrowedAmount);

        checkAccountState(
            BOB,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: borrowedAmount,
                interestAccumulatorRay: 1e27
            })
        );

        checkAccountPosition(
            BOB,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: borrowedAmount,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.01e18,
                currentLtv: 2_961.64e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            BOB,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: borrowedAmount,
                currentLtv: 2_961.64e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowedAmount, 1e27);
    }

    function test_addCollateralAndBorrowOnBehalfOf_successExisting() public {
        uint128 collateralAmount = 5e18;

        // Bob max borrows himself first
        {
            uint128 borrowAmount = type(uint128).max;
            vm.startPrank(BOB);
            gohm.mint(BOB, collateralAmount);
            gohm.approve(address(cooler), collateralAmount);
            cooler.addCollateralAndBorrow(collateralAmount, borrowAmount, BOB, noDelegationRequest());
        }

        // Then Alice does the same on behalf of Bob
        {
            uint128 borrowAmount = type(uint128).max;
            vm.startPrank(ALICE);
            gohm.mint(ALICE, collateralAmount);
            gohm.approve(address(cooler), collateralAmount);

            vm.expectEmit(address(cooler));
            emit CollateralAdded(ALICE, BOB, collateralAmount);
            vm.expectEmit(address(cooler));
            emit Borrow(BOB, BOB, 14_808.2e18);
            uint128 borrowed = cooler.addCollateralAndBorrowOnBehalfOf(
                BOB,
                collateralAmount,
                borrowAmount
            );
            assertEq(borrowed, 14_808.2e18);
        }

        // verify
        {
            uint128 borrowedAmount = 29_616.4e18;
            assertEq(cooler.totalCollateral(), collateralAmount * 2);
            assertEq(cooler.totalDebt(), borrowedAmount);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), 0);
            assertEq(gohm.balanceOf(BOB), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount * 2);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(usds.balanceOf(ALICE), 0);
            assertEq(usds.balanceOf(BOB), borrowedAmount);

            checkAccountState(
                BOB,
                IMonoCooler.AccountState({
                    collateral: collateralAmount * 2,
                    debtCheckpoint: borrowedAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                BOB,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount * 2,
                    currentDebt: borrowedAmount,
                    maxOriginationDebtAmount: 29_616.4e18,
                    liquidationDebtAmount: 29_912.564e18,
                    healthFactor: 1.01e18,
                    currentLtv: 2_961.64e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                BOB,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount * 2,
                    currentDebt: borrowedAmount,
                    currentLtv: 2_961.64e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(borrowedAmount, 1e27);
        }
    }

    function test_addCollateralAndBorrowOnBehalfOf_failHigherLtv() public {
        uint128 collateralAmount = 5e18;
        uint128 borrowAmount = 4_000e18;

        // Bob max borrows himself first
        vm.startPrank(BOB);
        gohm.mint(BOB, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);
        cooler.addCollateralAndBorrow(collateralAmount, borrowAmount, BOB, noDelegationRequest());

        // Then Alice does the same on behalf of Bob
        // but at a higher LTV
        vm.startPrank(ALICE);
        gohm.mint(ALICE, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);
        vm.expectRevert(
            abi.encodeWithSelector(IMonoCooler.ExceededPreviousLtv.selector, 800e18, 800e18 + 1)
        );
        cooler.addCollateralAndBorrowOnBehalfOf(
            BOB,
            collateralAmount,
            borrowAmount+1
        );
    }

    function test_repayAndWithdrawCollateral_successFixedAmount() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = type(uint128).max;

        // Bob max borrows himself first
        vm.startPrank(BOB);
        gohm.mint(BOB, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);
        uint128 amountBorrowed = cooler.addCollateralAndBorrow(
            collateralAmount,
            borrowAmount,
            BOB,
            noDelegationRequest()
        );
        assertEq(amountBorrowed, 29_616.4e18);

        // Then repays and withdraws in one step
        uint128 repayAmount = 15_000e18;
        uint128 withdrawAmount = 1e18;
        usds.approve(address(cooler), repayAmount);
        vm.expectEmit(address(cooler));
        emit Repay(BOB, BOB, repayAmount);
        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(BOB, ALICE, withdrawAmount);
        (uint128 repaidAmount, uint128 collateralWithdrawn) = cooler.repayAndWithdrawCollateral(repayAmount, withdrawAmount, ALICE, noDelegationRequest());
        assertEq(repaidAmount, repayAmount);
        assertEq(collateralWithdrawn, withdrawAmount);

        {
            assertEq(cooler.totalCollateral(), collateralAmount-withdrawAmount);
            assertEq(cooler.totalDebt(), amountBorrowed-repayAmount);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1e27);
            assertEq(gohm.balanceOf(ALICE), withdrawAmount);
            assertEq(gohm.balanceOf(BOB), 0);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount-withdrawAmount);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(usds.balanceOf(ALICE), 0);
            assertEq(usds.balanceOf(BOB), amountBorrowed-repayAmount);

            checkAccountState(
                BOB,
                IMonoCooler.AccountState({
                    collateral: collateralAmount-withdrawAmount,
                    debtCheckpoint: amountBorrowed-repayAmount,
                    interestAccumulatorRay: 1e27
                })
            );

            checkAccountPosition(
                BOB,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount-withdrawAmount,
                    currentDebt: amountBorrowed-repayAmount,
                    maxOriginationDebtAmount: 26_654.76e18,
                    liquidationDebtAmount: 26_921.3076e18,
                    healthFactor: 1.841856243671492296e18,
                    currentLtv: 1_624.044444444444444445e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                BOB,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount-withdrawAmount,
                    currentDebt: amountBorrowed-repayAmount,
                    currentLtv: 1_624.044444444444444445e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(amountBorrowed-repayAmount, 1e27);
        }

        // Bob delegates some collateral
        cooler.applyDelegations(delegationRequest(ALICE, 3.3e18));

        skip(30 days);

        // Repays and withdraws in one step including an undelegation
        uint128 repayAmount2 = 1_000e18;
        uint128 withdrawAmount2 = 1e18;
        usds.approve(address(cooler), repayAmount2);
        vm.expectEmit(address(cooler));
        emit Repay(BOB, BOB, repayAmount2);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(BOB, ALICE, -3.3e18);
        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(BOB, BOB, withdrawAmount2);
        {
            (uint128 repaidAmount2, uint128 collateralWithdrawn2) = cooler.repayAndWithdrawCollateral(repayAmount2, withdrawAmount2, BOB, unDelegationRequest(ALICE, 3.3e18));
            assertEq(repaidAmount2, repayAmount2);
            assertEq(collateralWithdrawn2, withdrawAmount2);
        }

        {
            uint128 expectedDebtInterest = 6.007974156709225580e18;
            assertEq(cooler.totalCollateral(), collateralAmount-withdrawAmount-withdrawAmount2);
            assertEq(cooler.totalDebt(), amountBorrowed-repayAmount-repayAmount2+expectedDebtInterest);
            assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
            assertEq(cooler.interestAccumulatorRay(), 1.000411043359288828e27);
            assertEq(gohm.balanceOf(ALICE), withdrawAmount);
            assertEq(gohm.balanceOf(BOB), withdrawAmount2);
            assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount-withdrawAmount-withdrawAmount2);
            assertEq(gohm.balanceOf(address(cooler)), 0);
            assertEq(usds.balanceOf(ALICE), 0);
            assertEq(usds.balanceOf(BOB), amountBorrowed-repayAmount-repayAmount2);

            checkAccountState(
                BOB,
                IMonoCooler.AccountState({
                    collateral: collateralAmount-withdrawAmount-withdrawAmount2,
                    debtCheckpoint: amountBorrowed-repayAmount-repayAmount2+expectedDebtInterest,
                    interestAccumulatorRay: 1.000411043359288828e27
                })
            );

            checkAccountPosition(
                BOB,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount-withdrawAmount-withdrawAmount2,
                    currentDebt: amountBorrowed-repayAmount-repayAmount2+expectedDebtInterest,
                    maxOriginationDebtAmount: 23_693.12e18,
                    liquidationDebtAmount: 23_930.0512e18,
                    healthFactor: 1.756668222343515747e18,
                    currentLtv: 1_702.800996769588653198e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );

            checkLiquidityStatus(
                BOB,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount-withdrawAmount-withdrawAmount2,
                    currentDebt: amountBorrowed-repayAmount-repayAmount2+expectedDebtInterest,
                    currentLtv: 1_702.800996769588653198e18,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false
                })
            );

            checkGlobalState(amountBorrowed-repayAmount-repayAmount2+expectedDebtInterest, 1.000411043359288828e27);
        }
    }

    function test_repayAndWithdrawCollateral_maxAmounts() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;

        vm.startPrank(BOB);
        gohm.mint(BOB, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);
        cooler.addCollateralAndBorrow(
            collateralAmount,
            borrowAmount,
            BOB,
            noDelegationRequest()
        );

        usds.approve(address(cooler), type(uint128).max);
        (uint128 repaidAmount, uint128 collateralWithdrawn) = cooler.repayAndWithdrawCollateral(type(uint128).max, type(uint128).max, ALICE, noDelegationRequest());
        assertEq(repaidAmount, 15_000e18);
        assertEq(collateralWithdrawn, 10e18);

        checkAccountState(
            BOB,
            IMonoCooler.AccountState({
                collateral: 0,
                debtCheckpoint: 0,
                interestAccumulatorRay: 1e27
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
                currentLtv: type(uint256).max,
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
                currentLtv: type(uint256).max,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(0, 1e27);
    }
}
