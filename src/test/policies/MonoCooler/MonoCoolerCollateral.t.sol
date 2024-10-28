// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";

contract MonoCoolerAddCollateralTest is MonoCoolerBaseTest {
    event CollateralAdded(address indexed fundedBy, address indexed onBehalfOf, uint128 collateralAmount);
    event DelegateEscrowCreated(address indexed delegate, address indexed escrow);
    event DelegationApplied(
        address indexed account, 
        address indexed fromDelegate, 
        address indexed toDelegate, 
        uint256 collateralAmount
    );

    function test_addCollateral_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.addCollateral(0, ALICE, new IMonoCooler.DelegationRequest[](0));
    }

    function test_addCollateral_failZeroOnBehalfOf() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.addCollateral(100, address(0), new IMonoCooler.DelegationRequest[](0));
    }

    function test_addCollateral_failDelegatingOnBehalfOf() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.addCollateral(100, BOB, new IMonoCooler.DelegationRequest[](1));
    }

    function test_addCollateral_simple() public {
        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, new IMonoCooler.DelegationRequest[](0));
        
        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), collateralAmount);

        // Check Account State
        {
            IMonoCooler.AccountState memory aState = cooler.accountState(ALICE);
            assertEq(aState.collateral, collateralAmount);
            assertEq(aState.debtCheckpoint, 0);
            assertEq(aState.interestAccumulatorRay, 0);
        }

        // Check delegations
        {
            IMonoCooler.AccountDelegation[] memory delegations = cooler.accountDelegations(ALICE, 0, 100);
            assertEq(delegations.length, 0);
        }

        // Check account position
        {
            IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
            assertEq(position.collateral, collateralAmount);
            assertEq(position.currentDebt, 0);
            assertEq(position.maxDebt, 46.5e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, 0);
            assertEq(position.numDelegateAddresses, 0);
            assertEq(position.maxDelegateAddresses, 10);
        }

        // Check liquidation status
        {
            address[] memory accounts = new address[](1);
            accounts[0] = ALICE;
            IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
            assertEq(status.length, 1);
            assertEq(status[0].collateral, collateralAmount);
            assertEq(status[0].currentDebt, 0);
            assertEq(status[0].currentLtv, 0);
            assertEq(status[0].exceededLiquidationLtv, false);
            assertEq(status[0].exceededMaxOriginationLtv, false);
        }
    }

    function test_addCollateral_onBehalfOfNoDelegations() public {
        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, BOB, collateralAmount);
        cooler.addCollateral(collateralAmount, BOB, new IMonoCooler.DelegationRequest[](0));

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), collateralAmount);

        // Check Account State
        {
            IMonoCooler.AccountState memory aState = cooler.accountState(BOB);
            assertEq(aState.collateral, collateralAmount);
            assertEq(aState.debtCheckpoint, 0);
            assertEq(aState.interestAccumulatorRay, 0);
        }

        // Check delegations
        {
            IMonoCooler.AccountDelegation[] memory delegations = cooler.accountDelegations(BOB, 0, 100);
            assertEq(delegations.length, 0);
        }

        // Check account position
        {
            IMonoCooler.AccountPosition memory position = cooler.accountPosition(BOB);
            assertEq(position.collateral, collateralAmount);
            assertEq(position.currentDebt, 0);
            assertEq(position.maxDebt, 46.5e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, 0);
            assertEq(position.numDelegateAddresses, 0);
            assertEq(position.maxDelegateAddresses, 10);
        }

        // Check liquidation status
        {
            address[] memory accounts = new address[](1);
            accounts[0] = BOB;
            IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
            assertEq(status.length, 1);
            assertEq(status[0].collateral, collateralAmount);
            assertEq(status[0].currentDebt, 0);
            assertEq(status[0].currentLtv, 0);
            assertEq(status[0].exceededLiquidationLtv, false);
            assertEq(status[0].exceededMaxOriginationLtv, false);
        }
    }

    function test_addCollateral_failTooMuchDelegation() public {
        // Mint extra gOHM into cooler
        gohm.mint(address(cooler), 100e18);

        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        IMonoCooler.DelegationRequest[] memory delegationRequests = new IMonoCooler.DelegationRequest[](1);
        delegationRequests[0] = IMonoCooler.DelegationRequest({
            fromDelegate: address(0),
            toDelegate: BOB,
            collateralAmount: collateralAmount + 1
        });

        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExceededCollateralBalance.selector, collateralAmount, collateralAmount + 1));
        cooler.addCollateral(collateralAmount, ALICE, delegationRequests);
    }

    function test_addCollateral_withDelegations() public {
        uint128 collateralAmount = 50e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        IMonoCooler.DelegationRequest[] memory delegationRequests = new IMonoCooler.DelegationRequest[](1);
        delegationRequests[0] = IMonoCooler.DelegationRequest({
            fromDelegate: address(0),
            toDelegate: BOB,
            collateralAmount: collateralAmount/2
        });

        address bobEscrow = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
        vm.expectEmit(address(cooler));
        emit DelegateEscrowCreated(BOB, bobEscrow);
        vm.expectEmit(address(cooler));
        emit DelegationApplied(ALICE, address(0), BOB, collateralAmount/2);
        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, delegationRequests);
        
        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), collateralAmount/2);

        // Check Account State
        {
            IMonoCooler.AccountState memory aState = cooler.accountState(ALICE);
            assertEq(aState.collateral, collateralAmount);
            assertEq(aState.debtCheckpoint, 0);
            assertEq(aState.interestAccumulatorRay, 0);
        }

        // Check delegations
        {
            IMonoCooler.AccountDelegation[] memory delegations = cooler.accountDelegations(ALICE, 0, 100);
            assertEq(delegations.length, 1);
            assertEq(delegations[0].delegate, BOB);
            assertEq(delegations[0].delegationAmount, collateralAmount/2);
            assertEq(gohm.balanceOf(delegations[0].delegateEscrow), collateralAmount/2);
        }

        // Check account position
        {
            IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
            assertEq(position.collateral, collateralAmount);
            assertEq(position.currentDebt, 0);
            assertEq(position.maxDebt, 46.5e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, collateralAmount/2);
            assertEq(position.numDelegateAddresses, 1);
            assertEq(position.maxDelegateAddresses, 10);
        }

        // Check liquidation status
        {
            address[] memory accounts = new address[](1);
            accounts[0] = ALICE;
            IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
            assertEq(status.length, 1);
            assertEq(status[0].collateral, collateralAmount);
            assertEq(status[0].currentDebt, 0);
            assertEq(status[0].currentLtv, 0);
            assertEq(status[0].exceededLiquidationLtv, false);
            assertEq(status[0].exceededMaxOriginationLtv, false);
        }
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
        IMonoCooler.DelegationRequest[] memory delegationRequests = new IMonoCooler.DelegationRequest[](4);
        delegationRequests[0] = IMonoCooler.DelegationRequest({
            fromDelegate: address(0),
            toDelegate: BOB,
            collateralAmount: 10e18
        });
        delegationRequests[1] = IMonoCooler.DelegationRequest({
            fromDelegate: address(0),
            toDelegate: OTHERS,
            collateralAmount: 30e18
        });
        delegationRequests[2] = IMonoCooler.DelegationRequest({
            fromDelegate: OTHERS,
            toDelegate: BOB,
            collateralAmount: 15e18
        });
        delegationRequests[3] = IMonoCooler.DelegationRequest({
            fromDelegate: OTHERS,
            toDelegate: address(0),
            collateralAmount: 5e18
        });

        address bobEscrow = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
        vm.expectEmit(address(cooler));
        emit DelegateEscrowCreated(BOB, bobEscrow);
        vm.expectEmit(address(cooler));
        emit DelegationApplied(ALICE, address(0), BOB, 10e18);

        address othersEscrow = 0xD6C5fA22BBE89db86245e111044a880213b35705;
        vm.expectEmit(address(cooler));
        emit DelegateEscrowCreated(OTHERS, othersEscrow);
        vm.expectEmit(address(cooler));
        emit DelegationApplied(ALICE, address(0), OTHERS, 30e18);

        vm.expectEmit(address(cooler));
        emit DelegationApplied(ALICE, OTHERS, BOB, 15e18);

        vm.expectEmit(address(cooler));
        emit DelegationApplied(ALICE, OTHERS, address(0), 5e18);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, delegationRequests);
        assertEq(cooler.totalCollateral(), collateralAmount);

        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), collateralAmount - 10e18 - 30e18 + 5e18);
        assertEq(gohm.balanceOf(othersEscrow), 10e18);

        // Check Account State
        {
            IMonoCooler.AccountState memory aState = cooler.accountState(ALICE);
            assertEq(aState.collateral, collateralAmount);
            assertEq(aState.debtCheckpoint, 0);
            assertEq(aState.interestAccumulatorRay, 0);
        }

        // Check delegations
        {
            IMonoCooler.AccountDelegation[] memory delegations = cooler.accountDelegations(ALICE, 0, 100);
            assertEq(delegations.length, 2);
            assertEq(delegations[0].delegate, BOB);
            assertEq(delegations[0].delegationAmount, 25e18);
            assertEq(gohm.balanceOf(delegations[0].delegateEscrow), 25e18);
            assertEq(delegations[1].delegate, OTHERS);
            assertEq(delegations[1].delegationAmount, 10e18);
            assertEq(gohm.balanceOf(delegations[1].delegateEscrow), 10e18);
        }

        // Check account position
        {
            IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
            assertEq(position.collateral, collateralAmount);
            assertEq(position.currentDebt, 0);
            assertEq(position.maxDebt, 46.5e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, collateralAmount/2);
            assertEq(position.numDelegateAddresses, 2);
            assertEq(position.maxDelegateAddresses, 10);
        }

        // Check liquidation status
        {
            address[] memory accounts = new address[](1);
            accounts[0] = ALICE;
            IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
            assertEq(status.length, 1);
            assertEq(status[0].collateral, collateralAmount);
            assertEq(status[0].currentDebt, 0);
            assertEq(status[0].currentLtv, 0);
            assertEq(status[0].exceededLiquidationLtv, false);
            assertEq(status[0].exceededMaxOriginationLtv, false);
        }
    }
}

contract MonoCoolerRemoveCollateralTest is MonoCoolerBaseTest {
    event CollateralRemoved(address indexed account, address indexed recipient, uint128 collateralAmount);

    function test_withdrawCollateral_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.withdrawCollateral(0, ALICE, new IMonoCooler.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_failZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.withdrawCollateral(100, address(0), new IMonoCooler.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_failNoCollateral() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExceededUndelegatedCollateralBalance.selector, 0, 100));
        cooler.withdrawCollateral(100, ALICE, new IMonoCooler.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_failNotEnoughCollateral() public {
        addCollateral(ALICE, 100e18);
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExceededUndelegatedCollateralBalance.selector, 100e18, 100e18 + 1));
        cooler.withdrawCollateral(100e18 + 1, ALICE, new IMonoCooler.DelegationRequest[](0));      
    }

    function test_withdrawCollateral_successSameRecipient() public {
        addCollateral(ALICE, 100e18);
        vm.startPrank(ALICE);

        vm.expectEmit(address(cooler));
        emit CollateralRemoved(ALICE, ALICE, 25e18);
        cooler.withdrawCollateral(25e18, ALICE, new IMonoCooler.DelegationRequest[](0));

        assertEq(cooler.totalCollateral(), 75e18);
        assertEq(gohm.balanceOf(ALICE), 25e18);
        assertEq(gohm.balanceOf(address(cooler)), 75e18);

        // Check Account State
        {
            IMonoCooler.AccountState memory aState = cooler.accountState(ALICE);
            assertEq(aState.collateral, 75e18);
            assertEq(aState.debtCheckpoint, 0);
            assertEq(aState.interestAccumulatorRay, 0);
        }

        // Check delegations
        {
            IMonoCooler.AccountDelegation[] memory delegations = cooler.accountDelegations(ALICE, 0, 100);
            assertEq(delegations.length, 0);
        }

        // Check account position
        {
            IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
            assertEq(position.collateral, 75e18);
            assertEq(position.currentDebt, 0);
            assertEq(position.maxDebt, 69.75e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, 0);
            assertEq(position.numDelegateAddresses, 0);
            assertEq(position.maxDelegateAddresses, 10);
        }

        // Check liquidation status
        {
            address[] memory accounts = new address[](1);
            accounts[0] = ALICE;
            IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
            assertEq(status.length, 1);
            assertEq(status[0].collateral, 75e18);
            assertEq(status[0].currentDebt, 0);
            assertEq(status[0].currentLtv, 0);
            assertEq(status[0].exceededLiquidationLtv, false);
            assertEq(status[0].exceededMaxOriginationLtv, false);
        }
    }

    function test_withdrawCollateral_successDifferentRecipient() public {
        addCollateral(ALICE, 100e18);
        vm.startPrank(ALICE);

        vm.expectEmit(address(cooler));
        emit CollateralRemoved(ALICE, BOB, 25e18);
        cooler.withdrawCollateral(25e18, BOB, new IMonoCooler.DelegationRequest[](0));

        assertEq(cooler.totalCollateral(), 75e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 25e18);
        assertEq(gohm.balanceOf(address(cooler)), 75e18);

        // Check Account State
        {
            IMonoCooler.AccountState memory aState = cooler.accountState(ALICE);
            assertEq(aState.collateral, 75e18);
            assertEq(aState.debtCheckpoint, 0);
            assertEq(aState.interestAccumulatorRay, 0);
        }

        // Check delegations
        {
            IMonoCooler.AccountDelegation[] memory delegations = cooler.accountDelegations(ALICE, 0, 100);
            assertEq(delegations.length, 0);
        }

        // Check account position
        {
            IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
            assertEq(position.collateral, 75e18);
            assertEq(position.currentDebt, 0);
            assertEq(position.maxDebt, 69.75e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, 0);
            assertEq(position.numDelegateAddresses, 0);
            assertEq(position.maxDelegateAddresses, 10);
        }

        // Check liquidation status
        {
            address[] memory accounts = new address[](1);
            accounts[0] = ALICE;
            IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
            assertEq(status.length, 1);
            assertEq(status[0].collateral, 75e18);
            assertEq(status[0].currentDebt, 0);
            assertEq(status[0].currentLtv, 0);
            assertEq(status[0].exceededLiquidationLtv, false);
            assertEq(status[0].exceededMaxOriginationLtv, false);
        }
    }

    // @todo Fail undelegated collateral after applying delegations
    // @todo Fail LTV check
}

