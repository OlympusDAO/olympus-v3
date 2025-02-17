// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/cooler/IMonoCooler.sol";
import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";

contract MonoCoolerAddCollateralTest is MonoCoolerBaseTest {
    event CollateralAdded(
        address indexed caller,
        address indexed onBehalfOf,
        uint128 collateralAmount
    );

    event DelegateEscrowCreated(
        address indexed caller,
        address indexed delegate,
        address indexed escrow
    );

    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    function test_addCollateral_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.addCollateral(0, ALICE, noDelegationRequest());
    }

    function test_addCollateral_failZeroOnBehalfOf() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidAddress.selector));
        cooler.addCollateral(100, address(0), noDelegationRequest());
    }

    function test_addCollateral_simple() public {
        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, noDelegationRequest());

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectNoDelegations(ALICE);
        expectAccountDelegationSummary(ALICE, 5e18, 0, 0, 10);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 14_808.2e18,
                liquidationDebtAmount: 14_956.282e18,
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
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_addCollateral_onBehalfOfNoDelegations() public {
        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, BOB, collateralAmount);
        cooler.addCollateral(collateralAmount, BOB, noDelegationRequest());

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount);

        checkAccountState(
            BOB,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectNoDelegations(BOB);
        expectAccountDelegationSummary(BOB, 5e18, 0, 0, 10);
        expectNoDelegations(ALICE);
        expectAccountDelegationSummary(ALICE, 0, 0, 0, 10);

        checkAccountPosition(
            BOB,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 14_808.2e18,
                liquidationDebtAmount: 14_956.282e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            BOB,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 0,
                currentLtv: 0,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_addCollateral_failTooMuchDelegation() public {
        // Mint extra gOHM into cooler
        gohm.mint(address(cooler), 100e18);

        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDLGTEv1.DLGTE_ExceededUndelegatedBalance.selector,
                collateralAmount,
                collateralAmount + 1
            )
        );
        cooler.addCollateral(collateralAmount, ALICE, delegationRequest(BOB, collateralAmount + 1));
    }

    function test_addCollateral_withDelegations_direct() public {
        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, int256(uint256(collateralAmount / 2)));
        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, delegationRequest(BOB, collateralAmount / 2));

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount / 2);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectOneDelegation(ALICE, BOB, collateralAmount / 2);
        expectAccountDelegationSummary(BOB, 0, 0, 0, 10);
        expectAccountDelegationSummary(ALICE, 5e18, 2.5e18, 1, 10);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 14_808.2e18,
                liquidationDebtAmount: 14_956.282e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: collateralAmount / 2,
                numDelegateAddresses: 1,
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
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_addCollateral_withDelegations_onBehalfOf_failUnauthorized() public {
        gohm.mint(ALICE, 100);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), 100);

        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnauthorizedOnBehalfOf.selector));
        cooler.addCollateral(100, BOB, new IDLGTEv1.DelegationRequest[](1));
    }

    function test_addCollateral_withDelegations_onBehalfOf_withAuthorization() public {
        // Alice gives approval for BOB to addCollateral and delegate
        vm.prank(ALICE);
        cooler.setAuthorization(BOB, uint96(block.timestamp + 1 days));

        uint128 collateralAmount = 5e18;
        gohm.mint(BOB, collateralAmount);
        vm.startPrank(BOB);
        gohm.approve(address(cooler), collateralAmount);

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, int256(uint256(collateralAmount / 2)));
        vm.expectEmit(address(cooler));
        emit CollateralAdded(BOB, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, delegationRequest(BOB, collateralAmount / 2));

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount / 2);

        // Alice
        {
            checkAccountState(
                ALICE,
                IMonoCooler.AccountState({
                    collateral: collateralAmount,
                    debtCheckpoint: 0,
                    interestAccumulatorRay: 0
                })
            );
            expectOneDelegation(ALICE, BOB, collateralAmount / 2);
            expectAccountDelegationSummary(ALICE, 5e18, 2.5e18, 1, 10);

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: 0,
                    maxOriginationDebtAmount: 14_808.2e18,
                    liquidationDebtAmount: 14_956.282e18,
                    healthFactor: type(uint256).max,
                    currentLtv: 0,
                    totalDelegated: collateralAmount / 2,
                    numDelegateAddresses: 1,
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
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );
        }

        // Bob
        {
            checkAccountState(
                BOB,
                IMonoCooler.AccountState({
                    collateral: 0,
                    debtCheckpoint: 0,
                    interestAccumulatorRay: 0
                })
            );

            expectAccountDelegationSummary(BOB, 0, 0, 0, 10);

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

    function test_addCollateral_thenApplyDelegations_sameUser() public {
        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, noDelegationRequest());

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, int256(uint256(collateralAmount / 2)));
        (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance) = cooler
            .applyDelegations(delegationRequest(BOB, collateralAmount / 2), ALICE);
        assertEq(totalDelegated, collateralAmount / 2);
        assertEq(totalUndelegated, 0);
        assertEq(undelegatedBalance, collateralAmount + totalUndelegated - totalDelegated);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount / 2);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectOneDelegation(ALICE, BOB, collateralAmount / 2);
        expectAccountDelegationSummary(BOB, 0, 0, 0, 10);
        expectAccountDelegationSummary(ALICE, 5e18, 2.5e18, 1, 10);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 14_808.2e18,
                liquidationDebtAmount: 14_956.282e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: collateralAmount / 2,
                numDelegateAddresses: 1,
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
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_addCollateral_thenApplyDelegations_onBehalfOf_noAuthorization() public {
        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, BOB, collateralAmount);
        cooler.addCollateral(collateralAmount, BOB, noDelegationRequest());

        // Need to prank BOB
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IDLGTEv1.DLGTE_ExceededUndelegatedBalance.selector,
                    0,
                    2.5e18
                )
            );
            cooler.applyDelegations(delegationRequest(BOB, collateralAmount / 2), ALICE);
        }

        // Need authorization to do it on behalf of BOB
        {
            vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnauthorizedOnBehalfOf.selector));
            cooler.applyDelegations(delegationRequest(BOB, collateralAmount / 2), BOB);
        }

        vm.startPrank(BOB);
        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(BOB, BOB, int256(uint256(collateralAmount / 2)));
        (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance) = cooler
            .applyDelegations(delegationRequest(BOB, collateralAmount / 2), BOB);
        assertEq(totalDelegated, collateralAmount / 2);
        assertEq(totalUndelegated, 0);
        assertEq(undelegatedBalance, collateralAmount + totalUndelegated - totalDelegated);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount / 2);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({collateral: 0, debtCheckpoint: 0, interestAccumulatorRay: 0})
        );
        checkAccountState(
            BOB,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectOneDelegation(BOB, BOB, collateralAmount / 2);
        expectAccountDelegationSummary(BOB, 5e18, 2.5e18, 1, 10);
        expectAccountDelegationSummary(ALICE, 0, 0, 0, 10);

        checkAccountPosition(
            BOB,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 14_808.2e18,
                liquidationDebtAmount: 14_956.282e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: collateralAmount / 2,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            BOB,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 0,
                currentLtv: 0,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_addCollateral_thenApplyDelegations_onBehalfOf_withAuthorization() public {
        vm.prank(BOB);
        cooler.setAuthorization(ALICE, uint96(block.timestamp + 1 days));

        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, BOB, collateralAmount);
        cooler.addCollateral(collateralAmount, BOB, noDelegationRequest());

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(BOB, BOB, int256(uint256(collateralAmount / 2)));
        (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance) = cooler
            .applyDelegations(delegationRequest(BOB, collateralAmount / 2), BOB);
        assertEq(totalDelegated, collateralAmount / 2);
        assertEq(totalUndelegated, 0);
        assertEq(undelegatedBalance, collateralAmount + totalUndelegated - totalDelegated);

        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount / 2);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({collateral: 0, debtCheckpoint: 0, interestAccumulatorRay: 0})
        );
        checkAccountState(
            BOB,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectOneDelegation(BOB, BOB, collateralAmount / 2);
        expectAccountDelegationSummary(BOB, 5e18, 2.5e18, 1, 10);
        expectAccountDelegationSummary(ALICE, 0, 0, 0, 10);

        checkAccountPosition(
            BOB,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 14_808.2e18,
                liquidationDebtAmount: 14_956.282e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: collateralAmount / 2,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            BOB,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 0,
                currentLtv: 0,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    // Full branch analysis for applying delegations to be done in a separate suite.
    function test_addCollateral_complexDelegations() public {
        // Adds and removes delegations
        uint128 collateralAmount = 5e18;
        gohm.mint(ALICE, collateralAmount);
        vm.startPrank(ALICE);
        gohm.approve(address(cooler), collateralAmount);

        // undelegated -> BOB: 1
        // undelegated -> OTHERS: 3
        // OTHERS -> BOB: 1.5
        // OTHERS -> undelegated: 0.5
        IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](
            5
        );
        delegationRequests[0] = IDLGTEv1.DelegationRequest({delegate: BOB, amount: 1e18});
        delegationRequests[1] = IDLGTEv1.DelegationRequest({delegate: OTHERS, amount: 3e18});
        delegationRequests[2] = IDLGTEv1.DelegationRequest({delegate: OTHERS, amount: -1.5e18});
        delegationRequests[3] = IDLGTEv1.DelegationRequest({delegate: BOB, amount: 1.5e18});
        delegationRequests[4] = IDLGTEv1.DelegationRequest({delegate: OTHERS, amount: -0.5e18});

        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), BOB, bobEscrow);
        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, 1e18);

        address othersEscrow = 0x6F67DD53F065131901fC8B45f183aD4977F75161;
        vm.expectEmit(address(escrowFactory));
        emit DelegateEscrowCreated(address(DLGTE), OTHERS, othersEscrow);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, OTHERS, 3e18);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, OTHERS, -1.5e18);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, BOB, 1.5e18);

        vm.expectEmit(address(DLGTE));
        emit DelegationApplied(ALICE, OTHERS, -0.5e18);

        vm.expectEmit(address(cooler));
        emit CollateralAdded(ALICE, ALICE, collateralAmount);
        cooler.addCollateral(collateralAmount, ALICE, delegationRequests);
        assertEq(cooler.totalCollateral(), collateralAmount);

        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), collateralAmount - 1e18 - 3e18 + 0.5e18);
        assertEq(gohm.balanceOf(othersEscrow), 1e18);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectTwoDelegations(ALICE, BOB, 2.5e18, OTHERS, 1e18);
        expectAccountDelegationSummary(ALICE, 5e18, 3.5e18, 2, 10);
        expectAccountDelegationSummary(BOB, 0, 0, 0, 10);
        expectAccountDelegationSummary(OTHERS, 0, 0, 0, 10);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 14_808.2e18,
                liquidationDebtAmount: 14_956.282e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: 3.5e18,
                numDelegateAddresses: 2,
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
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }
}

contract MonoCoolerWithdrawCollateralTest is MonoCoolerBaseTest {
    event CollateralWithdrawn(
        address indexed caller,
        address indexed onBehalfOf,
        address indexed recipient,
        uint128 collateralAmount
    );

    function test_withdrawCollateral_failZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExpectedNonZero.selector));
        cooler.withdrawCollateral(0, ALICE, ALICE, noDelegationRequest());
    }

    function test_withdrawCollateral_failZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidAddress.selector));
        cooler.withdrawCollateral(100, ALICE, address(0), noDelegationRequest());
    }

    function test_withdrawCollateral_failNoCollateral_noGohm() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExceededCollateralBalance.selector));
        cooler.withdrawCollateral(100, ALICE, ALICE, noDelegationRequest());
    }

    function test_withdrawCollateral_failNoCollateral_withGohm() public {
        deal(address(gohm), address(DLGTE), 1e18);
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExceededCollateralBalance.selector));
        cooler.withdrawCollateral(100, ALICE, ALICE, noDelegationRequest());
    }

    function test_withdrawCollateral_failNotEnoughCollateral() public {
        addCollateral(ALICE, 10e18);
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.ExceededCollateralBalance.selector));
        cooler.withdrawCollateral(100e18 + 1, ALICE, ALICE, noDelegationRequest());
    }

    function test_withdrawCollateral_successSameRecipient() public {
        addCollateral(ALICE, 10e18);
        vm.startPrank(ALICE);

        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(ALICE, ALICE, ALICE, 2.5e18);
        assertEq(cooler.withdrawCollateral(2.5e18, ALICE, ALICE, noDelegationRequest()), 2.5e18);

        assertEq(cooler.totalCollateral(), 7.5e18);
        assertEq(gohm.balanceOf(ALICE), 2.5e18);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), 7.5e18);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: 7.5e18,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectNoDelegations(ALICE);
        expectAccountDelegationSummary(ALICE, 7.5e18, 0, 0, 10);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: 7.5e18,
                currentDebt: 0,
                maxOriginationDebtAmount: 22_212.3e18,
                liquidationDebtAmount: 22_434.423e18,
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
                collateral: 7.5e18,
                currentDebt: 0,
                currentLtv: 0,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_withdrawCollateral_successDifferentRecipient() public {
        addCollateral(ALICE, 10e18);
        vm.startPrank(ALICE);

        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(ALICE, ALICE, BOB, 2.5e18);
        assertEq(cooler.withdrawCollateral(2.5e18, ALICE, BOB, noDelegationRequest()), 2.5e18);

        assertEq(cooler.totalCollateral(), 7.5e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 2.5e18);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), 7.5e18);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: 7.5e18,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectNoDelegations(ALICE);
        expectAccountDelegationSummary(ALICE, 7.5e18, 0, 0, 10);
        expectAccountDelegationSummary(BOB, 0, 0, 0, 10);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: 7.5e18,
                currentDebt: 0,
                maxOriginationDebtAmount: 22_212.3e18,
                liquidationDebtAmount: 22_434.423e18,
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
                collateral: 7.5e18,
                currentDebt: 0,
                currentLtv: 0,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_withdrawCollateral_fail_notEnoughUndelgated() public {
        addCollateral(ALICE, ALICE, 100e18, delegationRequest(BOB, 50e18));

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDLGTEv1.DLGTE_ExceededUndelegatedBalance.selector,
                50e18,
                50e18 + 1
            )
        );
        cooler.withdrawCollateral(50e18 + 1, ALICE, BOB, noDelegationRequest());
    }

    function test_withdrawCollateral_success_withDelegations() public {
        address bobEscrow = 0x9914ff9347266f1949C557B717936436402fc636;
        addCollateral(ALICE, ALICE, 100e18, delegationRequest(BOB, 50e18));

        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(ALICE, ALICE, ALICE, 50e18 + 1);
        assertEq(
            cooler.withdrawCollateral(50e18 + 1, ALICE, ALICE, unDelegationRequest(BOB, 1)),
            50e18 + 1
        );

        assertEq(cooler.totalCollateral(), 50e18 - 1);
        assertEq(gohm.balanceOf(ALICE), 50e18 + 1);
        assertEq(gohm.balanceOf(BOB), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(gohm.balanceOf(address(DLGTE)), 0);
        assertEq(gohm.balanceOf(address(bobEscrow)), 50e18 - 1);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: 50e18 - 1,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        expectOneDelegation(ALICE, BOB, 50e18 - 1);
        expectAccountDelegationSummary(ALICE, 50e18 - 1, 50e18 - 1, 1, 10);
        expectAccountDelegationSummary(BOB, 0, 0, 0, 10);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: 50e18 - 1,
                currentDebt: 0,
                maxOriginationDebtAmount: 148_081.999999999999997038e18,
                liquidationDebtAmount: 149_562.819999999999997008e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: 50e18 - 1,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: 50e18 - 1,
                currentDebt: 0,
                currentLtv: 0,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_withdrawCollateral_fail_originationLtv() public {
        addCollateral(ALICE, 10e18);

        // Borrow up to the max
        borrow(ALICE, ALICE, 29_616.4e18, ALICE);
        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: 10e18,
                currentDebt: 29_616.4e18,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.01e18,
                currentLtv: 2_961.64e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.ExceededMaxOriginationLtv.selector,
                2_961.64e18 + 297,
                2_961.64e18
            )
        );
        cooler.withdrawCollateral(1, ALICE, ALICE, noDelegationRequest());
    }

    function test_withdrawCollateral_success_maxOriginationLtv() public {
        addCollateral(ALICE, 10e18);
        borrow(ALICE, ALICE, 15_000e18, ALICE);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: 10e18,
                currentDebt: 15_000e18,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 1.994170933333333333e18,
                currentLtv: 1_500e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        vm.startPrank(ALICE);
        assertEq(
            cooler.withdrawCollateral(type(uint128).max, ALICE, ALICE, noDelegationRequest()),
            4.935238584027768398e18
        );

        assertEq(cooler.totalCollateral(), 10e18 - 4.935238584027768398e18);
        assertEq(gohm.balanceOf(ALICE), 4.935238584027768398e18);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: 5.064761415972231602e18,
                currentDebt: 15_000e18,
                maxOriginationDebtAmount: 15_000e18 + 1747,
                liquidationDebtAmount: 15_150e18 + 1764,
                healthFactor: 1.01e18,
                currentLtv: 2_961.639999999999999656e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: 5.064761415972231602e18,
                currentDebt: 15_000e18,
                currentLtv: 2_961.639999999999999656e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_withdrawCollateral_fail_max() public {
        addCollateral(ALICE, 10e18);
        borrow(ALICE, ALICE, type(uint128).max, ALICE);

        skip(1 days);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: 10e18,
                currentDebt: 29_616.805706888396984628e18,
                currentLtv: 2_961.680570688839698463e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0
            })
        );

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMonoCooler.ExceededMaxOriginationLtv.selector,
                2_961.680570688839698463e18,
                2_961.64e18
            )
        );
        cooler.withdrawCollateral(type(uint128).max, ALICE, ALICE, noDelegationRequest());
    }

    function test_withdrawCollateral_onBehalfOf_notAuthorized() public {
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnauthorizedOnBehalfOf.selector));
        cooler.withdrawCollateral(100, ALICE, ALICE, noDelegationRequest());
    }

    function test_withdrawCollateral_onBehalfOf_withAuthorization() public {
        addCollateral(ALICE, 10e18);

        // Alice gives approval for BOB to addCollateral and delegate
        vm.prank(ALICE);
        cooler.setAuthorization(BOB, uint96(block.timestamp + 1 days));

        vm.startPrank(BOB);
        vm.expectEmit(address(cooler));
        emit CollateralWithdrawn(BOB, ALICE, BOB, 1e18);
        assertEq(cooler.withdrawCollateral(1e18, ALICE, BOB, noDelegationRequest()), 1e18);

        assertEq(cooler.totalCollateral(), 9e18);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(BOB), 1e18);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: 9e18,
                debtCheckpoint: 0,
                interestAccumulatorRay: 0
            })
        );

        checkAccountState(
            BOB,
            IMonoCooler.AccountState({collateral: 0, debtCheckpoint: 0, interestAccumulatorRay: 0})
        );
    }
}

contract MonoCoolerCollateralViewTest is MonoCoolerBaseTest {
    function test_debtDeltaForMaxOriginationLtv() public {
        uint128 collateralAmount = 10e18;

        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0), 0);
        assertEq(
            cooler.debtDeltaForMaxOriginationLtv(ALICE, int128(collateralAmount)),
            29_616.4e18
        );
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 9e18), 26_654.760e18);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidCollateralDelta.selector));
        cooler.debtDeltaForMaxOriginationLtv(ALICE, -1);

        addCollateral(ALICE, collateralAmount);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0), 29_616.4e18);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, -1e18), 26_654.760e18);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 1e18), 32_578.04e18);

        // Borrow reduces available debt
        vm.startPrank(ALICE);
        cooler.borrow(1_000e18, ALICE, ALICE);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0), 28_616.4e18);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, -1e18), 25_654.76e18);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 1e18), 31_578.04e18);

        // Borrow max
        cooler.borrow(type(uint128).max, ALICE, ALICE);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0), 0); // Already at max
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, -1e18), -2_961.64e18); // If removing collateral, need to reduce borrow
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 1e18), 2_961.64e18); // If removing collateral, can borrow more

        skip(30 days);
        IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
        assertEq(position.currentDebt, 29_616.4e18 + 12.173624546041645580e18);
        assertEq(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0), -12.173624546041645580e18); // Above max - would need to reduce some
        assertEq(
            cooler.debtDeltaForMaxOriginationLtv(ALICE, -1e18),
            -2_961.64e18 - 12.173624546041645580e18
        ); // If removing collateral, need to reduce borrow
        assertEq(
            cooler.debtDeltaForMaxOriginationLtv(ALICE, 1e18),
            2_961.64e18 - 12.173624546041645580e18
        ); // If removing collateral, can borrow more
    }
}

contract MonoCoolerCollateralApplyDelegationsTest is MonoCoolerBaseTest {
    function test_applyDelegations_fail_zeroDelegate() public {
        addCollateral(ALICE, 10e18);
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidDelegationRequests.selector));
        cooler.applyDelegations(new IDLGTEv1.DelegationRequest[](0), ALICE);
    }

    function test_applyDelegations_fail_notAuthorized() public {
        addCollateral(ALICE, 10e18);

        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnauthorizedOnBehalfOf.selector));
        cooler.applyDelegations(delegationRequest(BOB, 10e18), ALICE);
    }

    function test_applyDelegations_success_self() public {
        addCollateral(ALICE, 10e18);

        IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](
            3
        );
        delegationRequests[0] = IDLGTEv1.DelegationRequest(BOB, 10e18);
        delegationRequests[1] = IDLGTEv1.DelegationRequest(BOB, -int256(2e18));
        delegationRequests[2] = IDLGTEv1.DelegationRequest(OTHERS, 1e18);

        vm.startPrank(ALICE);
        (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance) = cooler
            .applyDelegations(delegationRequests, ALICE);
        assertEq(totalDelegated, 11e18);
        assertEq(totalUndelegated, 2e18);
        assertEq(undelegatedBalance, 10e18 + totalUndelegated - totalDelegated);

        expectTwoDelegations(ALICE, BOB, 8e18, OTHERS, 1e18);
        expectAccountDelegationSummary(ALICE, 10e18, 9e18, 2, 10);
    }

    function test_applyDelegations_success_onBehalfOf() public {
        address operator = makeAddr("operator");

        addCollateral(ALICE, 10e18);

        vm.startPrank(ALICE);
        cooler.setAuthorization(operator, type(uint32).max);

        IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](
            3
        );
        delegationRequests[0] = IDLGTEv1.DelegationRequest(BOB, 10e18);
        delegationRequests[1] = IDLGTEv1.DelegationRequest(BOB, -int256(2e18));
        delegationRequests[2] = IDLGTEv1.DelegationRequest(OTHERS, 1e18);

        vm.startPrank(operator);
        (uint256 totalDelegated, uint256 totalUndelegated, uint256 undelegatedBalance) = cooler
            .applyDelegations(delegationRequests, ALICE);
        assertEq(totalDelegated, 11e18);
        assertEq(totalUndelegated, 2e18);
        assertEq(undelegatedBalance, 10e18 + totalUndelegated - totalDelegated);

        expectTwoDelegations(ALICE, BOB, 8e18, OTHERS, 1e18);
        expectAccountDelegationSummary(ALICE, 10e18, 9e18, 2, 10);
    }
}
