// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {DLGTEv1} from "modules/DLGTE/DLGTE.v1.sol";

contract MonoCoolerAddCollateralTest is MonoCoolerBaseTest {
    event CollateralAdded(address indexed fundedBy, address indexed onBehalfOf, uint128 collateralAmount);

    event DelegateEscrowCreated(
        address indexed caller, 
        address indexed delegate, 
        address indexed escrow
    );

    event DelegationApplied(
        address indexed account,
        address indexed delegate,
        int256 amount
    );

    function test_addCollateral_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.addCollateral(0, ALICE, new DLGTEv1.DelegationRequest[](0));
    }

    function test_addCollateral_failZeroOnBehalfOf() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.addCollateral(100, address(0), new DLGTEv1.DelegationRequest[](0));
    }

    function test_addCollateral_failDelegatingOnBehalfOf() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.addCollateral(100, BOB, new DLGTEv1.DelegationRequest[](1));
    }

    function test_addCollateral_simple() public {
        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, new DLGTEv1.DelegationRequest[](0));
        
        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);

        checkAccountState(ALICE, IMonoCooler.AccountState({
            collateral: collateralAmount,
            debtCheckpoint: 0,
            interestAccumulatorRay: 0
        }));

        expectNoDelegations(ALICE);

        checkAccountPosition(ALICE, IMonoCooler.AccountPosition({
            collateral: collateralAmount,
            currentDebt: 0,
            maxDebt: 46.5e18,
            healthFactor: type(uint256).max,
            currentLtv: 0,
            totalDelegated: 0,
            numDelegateAddresses: 0,
            maxDelegateAddresses: 10
        }));

        checkLiquidityStatus(ALICE, IMonoCooler.LiquidationStatus({
            collateral: collateralAmount,
            currentDebt: 0,
            currentLtv: 0,
            exceededLiquidationLtv: false,
            exceededMaxOriginationLtv: false
        }));
    }

    function test_addCollateral_onBehalfOfNoDelegations() public {
        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, BOB, collateralAmount);
        cooler.addCollateral(collateralAmount, BOB, new DLGTEv1.DelegationRequest[](0));

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);

        checkAccountState(BOB, IMonoCooler.AccountState({
            collateral: collateralAmount,
            debtCheckpoint: 0,
            interestAccumulatorRay: 0
        }));

        expectNoDelegations(BOB);

        checkAccountPosition(BOB, IMonoCooler.AccountPosition({
            collateral: collateralAmount,
            currentDebt: 0,
            maxDebt: 46.5e18,
            healthFactor: type(uint256).max,
            currentLtv: 0,
            totalDelegated: 0,
            numDelegateAddresses: 0,
            maxDelegateAddresses: 10
        }));

        checkLiquidityStatus(BOB, IMonoCooler.LiquidationStatus({
            collateral: collateralAmount,
            currentDebt: 0,
            currentLtv: 0,
            exceededLiquidationLtv: false,
            exceededMaxOriginationLtv: false
        }));
    }

    function test_addCollateral_failTooMuchDelegation() public {
        // Mint extra gOHM into cooler
        gohm.mint(address(cooler), 100e18);

        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededUndelegatedBalance.selector, collateralAmount, collateralAmount + 1));
        cooler.addCollateral(collateralAmount, ALICE, delegationRequest(BOB, collateralAmount + 1));
    }

    function test_addCollateral_withDelegations() public {
        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, int256(uint256(collateralAmount/2)));
        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, delegationRequest(BOB, collateralAmount/2));
        
        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount/2);

        checkAccountState(ALICE, IMonoCooler.AccountState({
            collateral: collateralAmount,
            debtCheckpoint: 0,
            interestAccumulatorRay: 0
        }));

        expectOneDelegation(ALICE, BOB, collateralAmount/2);

        checkAccountPosition(ALICE, IMonoCooler.AccountPosition({
            collateral: collateralAmount,
            currentDebt: 0,
            maxDebt: 46.5e18,
            healthFactor: type(uint256).max,
            currentLtv: 0,
            totalDelegated: collateralAmount/2,
            numDelegateAddresses: 1,
            maxDelegateAddresses: 10
        }));

        checkLiquidityStatus(ALICE, IMonoCooler.LiquidationStatus({
            collateral: collateralAmount,
            currentDebt: 0,
            currentLtv: 0,
            exceededLiquidationLtv: false,
            exceededMaxOriginationLtv: false
        }));
    }

    // Full branch analysis for applying delegations to be done in a separate suite.
    function test_addCollateral_complexDelegations() public {
        // Adds and removes delegations
        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        // undelegated -> BOB: 10
        // undelegated -> OTHERS: 30
        // OTHERS -> BOB: 15
        // OTHERS -> undelegated: 5
        DLGTEv1.DelegationRequest[] memory delegationRequests = new DLGTEv1.DelegationRequest[](5);
        delegationRequests[0] = DLGTEv1.DelegationRequest({
            delegate: BOB,
            amount: 10e18
        });
        delegationRequests[1] = DLGTEv1.DelegationRequest({
            delegate: OTHERS,
            amount: 30e18
        });
        delegationRequests[2] = DLGTEv1.DelegationRequest({
            delegate: OTHERS,
            amount: -15e18
        });
        delegationRequests[3] = DLGTEv1.DelegationRequest({
            delegate: BOB,
            amount: 15e18
        });
        delegationRequests[4] = DLGTEv1.DelegationRequest({
            delegate: OTHERS,
            amount: -5e18
        });

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, 10e18);

        address othersEscrow = 0x6F67DD53F065131901fC8B45f183aD4977F75161;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), OTHERS, othersEscrow);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, OTHERS, 30e18);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, OTHERS, -15e18);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, 15e18);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, OTHERS, -5e18);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, delegationRequests);
        assertEq(cooler.totalCollateral(), collateralAmount);

        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount - 10e18 - 30e18 + 5e18);
        assertEq(gohm.balanceOf(othersEscrow), 10e18);

        checkAccountState(ALICE, IMonoCooler.AccountState({
            collateral: collateralAmount,
            debtCheckpoint: 0,
            interestAccumulatorRay: 0
        }));

        expectTwoDelegations(ALICE,
            BOB, 25e18,
            OTHERS, 10e18
        );

        checkAccountPosition(ALICE, IMonoCooler.AccountPosition({
            collateral: collateralAmount,
            currentDebt: 0,
            maxDebt: 46.5e18,
            healthFactor: type(uint256).max,
            currentLtv: 0,
            totalDelegated: 35e18,
            numDelegateAddresses: 2,
            maxDelegateAddresses: 10
        }));

        checkLiquidityStatus(ALICE, IMonoCooler.LiquidationStatus({
            collateral: collateralAmount,
            currentDebt: 0,
            currentLtv: 0,
            exceededLiquidationLtv: false,
            exceededMaxOriginationLtv: false
        }));
    }
}

contract MonoCoolerWithdrawCollateralTest is MonoCoolerBaseTest {
    event CollateralWithdrawn(address indexed account, address indexed recipient, uint128 collateralAmount);

    function test_withdrawCollateral_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.withdrawCollateral(0, ALICE, new DLGTEv1.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_failZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.withdrawCollateral(100, address(0), new DLGTEv1.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_failNoCollateral_noGohm() public {
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededPolicyAccountBalance.selector, 0, 100));
        cooler.withdrawCollateral(100, ALICE, new DLGTEv1.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_failNoCollateral_withGohm() public {
        deal(address(gohm), address(DLGTE), 1e18);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededPolicyAccountBalance.selector, 0, 100));
        cooler.withdrawCollateral(100, ALICE, new DLGTEv1.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_failNotEnoughCollateral() public {
        addCollateral(ALICE, 100e18);
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(DLGTEv1.DLGTE_ExceededPolicyAccountBalance.selector, 100e18, 100e18 + 1));
        cooler.withdrawCollateral(100e18 + 1, ALICE, new DLGTEv1.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_successSameRecipient() public {
        addCollateral(ALICE, 100e18);
        vm.startPrank(ALICE);

        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(ALICE, ALICE, 25e18);
        cooler.withdrawCollateral(25e18, ALICE, new DLGTEv1.DelegationRequest[](0));

        // assertEq(cooler.totalCollateral(), 75e18);
        // assertEq(gohm.balanceOf(ALICE), 25e18);
        // assertEq(gohm.balanceOf(address(cooler)), 0);
        // assertEq(gohm.balanceOf(address(DLGTE)), 75e18);

        // checkAccountState(ALICE, IMonoCooler.AccountState({
        //     collateral: 75e18,
        //     debtCheckpoint: 0,
        //     interestAccumulatorRay: 0
        // }));

        // expectNoDelegations(ALICE);

        // checkAccountPosition(ALICE, IMonoCooler.AccountPosition({
        //     collateral: 75e18,
        //     currentDebt: 0,
        //     maxDebt: 69.75e18,
        //     healthFactor: type(uint256).max,
        //     currentLtv: 0,
        //     totalDelegated: 0,
        //     numDelegateAddresses: 0,
        //     maxDelegateAddresses: 10
        // }));

        // checkLiquidityStatus(ALICE, IMonoCooler.LiquidationStatus({
        //     collateral: 75e18,
        //     currentDebt: 0,
        //     currentLtv: 0,
        //     exceededLiquidationLtv: false,
        //     exceededMaxOriginationLtv: false
        // }));
    }

    function test_withdrawCollateral_successDifferentRecipient() public {
        addCollateral(ALICE, 100e18);
        vm.startPrank(ALICE);

        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(ALICE, BOB, 25e18);
        cooler.withdrawCollateral(25e18, BOB, new DLGTEv1.DelegationRequest[](0));

        assertEq(cooler.totalCollateral(), 75e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 25e18);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), 75e18);

        checkAccountState(ALICE, IMonoCooler.AccountState({
            collateral: 75e18,
            debtCheckpoint: 0,
            interestAccumulatorRay: 0
        }));

        expectNoDelegations(ALICE);

        checkAccountPosition(ALICE, IMonoCooler.AccountPosition({
            collateral: 75e18,
            currentDebt: 0,
            maxDebt: 69.75e18,
            healthFactor: type(uint256).max,
            currentLtv: 0,
            totalDelegated: 0,
            numDelegateAddresses: 0,
            maxDelegateAddresses: 10
        }));

        checkLiquidityStatus(ALICE, IMonoCooler.LiquidationStatus({
            collateral: 75e18,
            currentDebt: 0,
            currentLtv: 0,
            exceededLiquidationLtv: false,
            exceededMaxOriginationLtv: false
        }));
    }

    // @todo Fail undelegated collateral after applying delegations
    // @todo Fail LTV check
}

