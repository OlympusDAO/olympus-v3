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

    event DelegateEscrowCreated(
        address indexed caller,
        address indexed delegate,
        address indexed escrow
    );

    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    event Borrow(address indexed account, address indexed recipient, uint128 amount);

    function test_addCollateralAndBorrow_successNew() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = type(uint128).max;
        uint128 borrowedAmount = 9_300e18;

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
        assertEq(dai.balanceOf(ALICE), 0);
        assertEq(dai.balanceOf(BOB), borrowedAmount);

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
                currentLtv: 0.93e18,
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
                currentLtv: 0.93e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowedAmount, 1e27);
    }

    function test_addCollateralAndBorrow_successExisting() public {
        uint128 collateralAmount = 5_000e18;
        uint128 borrowAmount = type(uint128).max;
        uint128 borrowedAmount = 9_300e18;

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
        assertEq(dai.balanceOf(ALICE), borrowedAmount);
        assertEq(dai.balanceOf(BOB), 0);

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
                maxOriginationDebtAmount: 9_300e18,
                liquidationDebtAmount: 9_400e18,
                healthFactor: 1.010752688172043010e18,
                currentLtv: 0.93e18,
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
                currentLtv: 0.93e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowedAmount, 1e27);
    }

    function test_addCollateralAndBorrowOnBehalfOf_successNew() public {
        uint128 collateralAmount = 10_000e18;
        uint128 borrowAmount = type(uint128).max;
        uint128 borrowedAmount = 9_300e18;

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
        assertEq(dai.balanceOf(ALICE), 0);
        assertEq(dai.balanceOf(BOB), borrowedAmount);

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
                maxOriginationDebtAmount: 9_300e18,
                liquidationDebtAmount: 9_400e18,
                healthFactor: 1.010752688172043010e18,
                currentLtv: 0.93e18,
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
                currentLtv: 0.93e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowedAmount, 1e27);
    }

    function test_addCollateralAndBorrowOnBehalfOf_successExisting() public {
        uint128 collateralAmount = 5_000e18;
        uint128 borrowAmount = type(uint128).max;

        // Bob max borrows himself first
        vm.startPrank(BOB);
        gohm.mint(BOB, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);
        cooler.addCollateralAndBorrow(collateralAmount, borrowAmount, BOB, noDelegationRequest());

        // Then Alice does the same on behalf of Bob
        uint128 borrowedAmount = 9_300e18;
        vm.startPrank(ALICE);
        gohm.mint(ALICE, collateralAmount);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, BOB, collateralAmount);
        vm.expectEmit(address(cooler));
        emit Borrow(BOB, BOB, 4_650e18);
        uint128 borrowed = cooler.addCollateralAndBorrowOnBehalfOf(
            BOB,
            collateralAmount,
            borrowAmount
        );
        assertEq(borrowed, 4_650e18);

        assertEq(cooler.totalCollateral(), collateralAmount * 2);
        assertEq(cooler.totalDebt(), borrowedAmount);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount * 2);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(dai.balanceOf(ALICE), 0);
        assertEq(dai.balanceOf(BOB), borrowedAmount);

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
                maxOriginationDebtAmount: 9_300e18,
                liquidationDebtAmount: 9_400e18,
                healthFactor: 1.010752688172043010e18,
                currentLtv: 0.93e18,
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
                currentLtv: 0.93e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );

        checkGlobalState(borrowedAmount, 1e27);
    }

    function test_addCollateralAndBorrowOnBehalfOf_failHigherLtv() public {
        uint128 collateralAmount = 5_000e18;
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
            abi.encodeWithSelector(IMonoCooler.ExceededPreviousLtv.selector, 0.8e18, 0.8e18 + 1)
        );
        cooler.addCollateralAndBorrowOnBehalfOf(
            BOB,
            collateralAmount,
            borrowAmount+1
        );
    }
}
