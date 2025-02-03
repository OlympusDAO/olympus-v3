// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {DLGTEv1} from "modules/DLGTE/OlympusGovDelegation.sol";
import {ICoolerLtvOracle} from "policies/interfaces/cooler/ICoolerLtvOracle.sol";
import {DelegateEscrow} from "src/external/cooler/DelegateEscrow.sol";

contract MonoCoolerComputeLiquidityTest is MonoCoolerBaseTest {
    function test_computeLiquidity_noBorrowsNoCollateral() external view {
        checkLiquidityStatus(
            ALICE,
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

    function test_computeLiquidity_noBorrowsWithCollateral() external {
        uint128 collateralAmount = 100_000;
        addCollateral(ALICE, collateralAmount);
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

    function test_computeLiquidity_withBorrowUnderOLTV() external {
        uint128 collateralAmount = 10e18;
        uint128 borrowAmount = 15_000e18;
        addCollateral(ALICE, collateralAmount);
        borrow(ALICE, ALICE, borrowAmount, ALICE);
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
    }

    function test_computeLiquidity_withBorrowAtOLTV() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));

        borrow(ALICE, ALICE, borrowAmount, ALICE);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: borrowAmount,
                currentLtv: DEFAULT_OLTV,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );
    }

    function test_computeLiquidity_withBorrowOverOLTV() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(1);

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: borrowAmount + 4695649389328,
                currentLtv: DEFAULT_OLTV + 469564938933,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0
            })
        );
    }

    function test_computeLiquidity_withBorrowAboveLLTV() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 363.19 days);

        // By default, the LTVs are dripping - a target would need to be set first (see below test)
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, DEFAULT_OLTV);
        assertEq(lltv, DEFAULT_LLTV);

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: borrowAmount + 296.166396168051594267e18,
                currentLtv: DEFAULT_OLTV + 29.616639616805159427e18,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0.000000801057392337e18 // gOHM
            })
        );
    }

    function test_computeLiquidity_withBorrow_ltvDrip_underLLTV() external {
        vm.prank(OVERSEER);
        ltvOracle.setOriginationLtvAt(DEFAULT_OLTV+1e18, uint32(vm.getBlockTimestamp()) + 2 * 365 days);

        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 363.19 days);

        // LTV's have increased slightly now
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, 2_962.635041095835038912e18);
        assertEq(lltv, 2_992.261391506793389301e18);

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 29_912.566396168051594267e18,
                currentLtv: 2_991.256639616805159427e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0
            })
        );
    }

    function test_computeLiquidity_withBorrow_ltvDrip_overLLTV() external {
        vm.prank(OVERSEER);
        ltvOracle.setOriginationLtvAt(DEFAULT_OLTV+1e18, uint32(vm.getBlockTimestamp()) + 2 * 365 days);

        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2.1 * 365 days);

        // LTV's have increased slightly now
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, DEFAULT_OLTV + 1e18);
        assertEq(lltv, 2_992.2664e18);

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 29_929.010533195278954852e18,
                currentLtv: 2_992.901053319527895486e18,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0.002120978665294960e18 // gOHM
            })
        );
    }

    function test_computeLiquidity_afterRepayAll() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(365 days);

        // Alice needs more USDS to pay the accrued debt
        uint256 expectedInterest = 148.452822780365642234e18;
        deal(address(usds), ALICE, borrowAmount+expectedInterest);
        repay(ALICE, ALICE, type(uint128).max);

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

        withdrawCollateral(ALICE, ALICE, ALICE, collateralAmount, noDelegationRequest());

        checkLiquidityStatus(
            ALICE,
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

contract MonoCoolerLiquidationsTest is MonoCoolerBaseTest {
    event Liquidated(address indexed caller, address indexed account, uint128 collateralSeized, uint128 debtWiped, uint128 incentives);

    function noAddresses() private pure returns (address[] memory accounts) {
        accounts = new address[](0);
    }

    function oneAddress(address acct) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = acct;
    }

    function twoAddresses(address acct1, address acct2) private pure returns (address[] memory accounts) {
        accounts = new address[](2);
        accounts[0] = acct1;
        accounts[1] = acct2;
    }


    function noDelegationRequests() private pure returns (DLGTEv1.DelegationRequest[][] memory requests) {
        requests = new DLGTEv1.DelegationRequest[][](0);
    }

    function oneDelegationRequest(
        DLGTEv1.DelegationRequest[] memory request
    ) private pure returns (DLGTEv1.DelegationRequest[][] memory requests) {
        requests = new DLGTEv1.DelegationRequest[][](1);
        requests[0] = request;
    }

    function twoDelegationRequests(
        DLGTEv1.DelegationRequest[] memory request1,
        DLGTEv1.DelegationRequest[] memory request2
    ) private pure returns (DLGTEv1.DelegationRequest[][] memory requests) {
        requests = new DLGTEv1.DelegationRequest[][](2);
        requests[0] = request1;
        requests[1] = request2;
    }

    function test_batchLiquidate_fail_paused() external {
        vm.prank(OVERSEER);
        cooler.setLiquidationsPaused(true);

        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.Paused.selector));
        cooler.batchLiquidate(oneAddress(ALICE), oneDelegationRequest(noDelegationRequest()));
    }

    function test_batchLiquidate_noAccounts() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 365 days);

        // Can be liquidated
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 29_914.049768431554843335e18,
                currentLtv: 2_991.404976843155484334e18,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0.000496703803644129e18 // gOHM
            })
        );

        checkBatchLiquidate(noAddresses(), noDelegationRequests(), 0, 0, 0);

        // No change
        assertEq(cooler.totalCollateral(), collateralAmount);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 29_914.049768431554843335e18,
                currentLtv: 2_991.404976843155484334e18,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0.000496703803644129e18 // gOHM
            })
        );
    }

    function test_batchLiquidate_oneAccount_noLiquidate() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(1 days);

        assertEq(cooler.totalCollateral(), collateralAmount);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 29_616.805706888396984628e18,
                currentLtv: 2_961.680570688839698463e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0
            })
        );

        checkBatchLiquidate(oneAddress(ALICE), noDelegationRequests(), 0, 0, 0);

        // No change
        assertEq(cooler.totalCollateral(), collateralAmount);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 29_616.805706888396984628e18,
                currentLtv: 2_961.680570688839698463e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0
            })
        );
    }

    function test_batchLiquidate_oneAccount_noLiquidateAtMax() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 363.19 days);

        // Set the LLTV such that ALICE has exactly the same debt - not liquidatable
        uint128 expectedCurrentLtv = DEFAULT_OLTV + 29.616639616805159427e18;
        vm.mockCall(
            address(ltvOracle),
            abi.encodeWithSelector(ICoolerLtvOracle.currentLtvs.selector),
            abi.encode(DEFAULT_OLTV, expectedCurrentLtv)
        );

        // By default, the LTVs are dripping - a target would need to be set first (see below test)
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, DEFAULT_OLTV);
        assertEq(lltv, expectedCurrentLtv);

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: borrowAmount + 296.166396168051594267e18,
                currentLtv: expectedCurrentLtv,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0.0
            })
        );

        checkBatchLiquidate(oneAddress(ALICE), noDelegationRequests(), 0, 0, 0);
    }

    function test_batchLiquidate_oneAccount_canLiquidateAboveMax() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 363.19 days);

        // Reduce the LLTV to be one less such that it JUST ticks over
        // to be liquidatable
        uint128 expectedCurrentLtv = DEFAULT_OLTV + 29.616639616805159427e18;
        vm.mockCall(
            address(ltvOracle),
            abi.encodeWithSelector(ICoolerLtvOracle.currentLtvs.selector),
            abi.encode(DEFAULT_OLTV, expectedCurrentLtv - 1)
        );

        // By default, the LTVs are dripping - a target would need to be set first (see below test)
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, DEFAULT_OLTV);
        assertEq(lltv, expectedCurrentLtv-1);

        uint128 expectedDebt = borrowAmount + 296.166396168051594267e18;
        uint128 expectedIncentives = 1;
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedDebt,
                currentLtv: expectedCurrentLtv,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: expectedIncentives
            })
        );

        vm.startPrank(OTHERS);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, ALICE, collateralAmount, expectedDebt, expectedIncentives);
        checkBatchLiquidate(oneAddress(ALICE), noDelegationRequests(), collateralAmount, expectedDebt, expectedIncentives);

        // Check position is empty now (debt + collateral)
        {
            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: 0,
                    currentDebt: 0,
                    currentLtv: type(uint128).max,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkAccountPosition(
                ALICE,
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
        }

        // caller gets the incentive
        assertEq(gohm.balanceOf(OTHERS), expectedIncentives);
    }

    function test_batchLiquidate_twoAccounts_oneLiquidate() external {
        // Alice borrows just under, Bob borrow's max
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        addCollateral(BOB, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount-10, ALICE);
        borrow(BOB, BOB, borrowAmount, BOB);

        skip(2 * 363.19 days);

        // Reduce the LLTV to be one less such that it JUST ticks over
        // to be liquidatable
        uint128 expectedCurrentLtv = DEFAULT_OLTV + 29.616639616805159427e18;
        vm.mockCall(
            address(ltvOracle),
            abi.encodeWithSelector(ICoolerLtvOracle.currentLtvs.selector),
            abi.encode(DEFAULT_OLTV, expectedCurrentLtv - 1)
        );

        // By default, the LTVs are dripping - a target would need to be set first (see below test)
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, DEFAULT_OLTV);
        assertEq(lltv, expectedCurrentLtv-1);

        uint128 expectedDebt = borrowAmount + 296.166396168051594267e18;
        uint128 expectedIncentives = 1;
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedDebt-10,
                currentLtv: expectedCurrentLtv-1,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: true,
                currentIncentive: 0
            })
        );
        checkLiquidityStatus(
            BOB,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedDebt,
                currentLtv: expectedCurrentLtv,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: expectedIncentives
            })
        );

        vm.startPrank(OTHERS);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, BOB, collateralAmount, expectedDebt, expectedIncentives);
        checkBatchLiquidate(twoAddresses(ALICE, BOB), noDelegationRequests(), collateralAmount, expectedDebt, expectedIncentives);

        // Alice is still just healthy
        {
            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: expectedDebt-10,
                    currentLtv: expectedCurrentLtv-1,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: true,
                    currentIncentive: 0
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: expectedDebt-10,
                    maxOriginationDebtAmount: 29616400000000000000000,
                    liquidationDebtAmount: 29_912.566396168051594260e18,
                    healthFactor: 1e18,
                    currentLtv: 2_991.256639616805159426e18,
                    totalDelegated: 0,
                    numDelegateAddresses: 0,
                    maxDelegateAddresses: 10
                })
            );
        }

        // Check position is empty now (debt + collateral)
        {
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
        }

        // Caller gets the incentive
        assertEq(gohm.balanceOf(OTHERS), expectedIncentives);
    }

    function test_batchLiquidate_twoAccounts_bothLiquidate() external {
        // Alice borrows just under, Bob borrow's max
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        addCollateral(BOB, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);
        borrow(BOB, BOB, borrowAmount, BOB);

        skip(2 * 363.19 days);

        // Reduce the LLTV to be one less such that it JUST ticks over
        // to be liquidatable
        uint128 expectedCurrentLtv = DEFAULT_OLTV + 29.616639616805159427e18;
        vm.mockCall(
            address(ltvOracle),
            abi.encodeWithSelector(ICoolerLtvOracle.currentLtvs.selector),
            abi.encode(DEFAULT_OLTV, expectedCurrentLtv - 1)
        );

        // By default, the LTVs are dripping - a target would need to be set first (see below test)
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, DEFAULT_OLTV);
        assertEq(lltv, expectedCurrentLtv-1);

        uint128 expectedDebt = borrowAmount + 296.166396168051594267e18;
        uint128 expectedIncentives = 1;
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedDebt,
                currentLtv: expectedCurrentLtv,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: expectedIncentives
            })
        );
        checkLiquidityStatus(
            BOB,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedDebt,
                currentLtv: expectedCurrentLtv,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: expectedIncentives
            })
        );

        vm.startPrank(OTHERS);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, ALICE, collateralAmount, expectedDebt, expectedIncentives);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, BOB, collateralAmount, expectedDebt, expectedIncentives);
        checkBatchLiquidate(twoAddresses(ALICE, BOB), noDelegationRequests(), collateralAmount*2, expectedDebt*2, expectedIncentives*2);

        // Check position is empty now (debt + collateral)
        {
            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: 0,
                    currentDebt: 0,
                    currentLtv: type(uint128).max,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: false,
                    currentIncentive: 0
                })
            );

            checkAccountPosition(
                ALICE,
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
        }

        // Check position is empty now (debt + collateral)
        {
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
        }

        // Caller gets the total incentives
        assertEq(gohm.balanceOf(OTHERS), expectedIncentives*2);
    }

    function test_batchLiquidate_emptyDelegationRequests() external {
        // Alice borrows just under, Bob borrow's max
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        addCollateral(BOB, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);
        borrow(BOB, BOB, borrowAmount, BOB);

        skip(2 * 363.19 days);

        // Reduce the LLTV to be one less such that it JUST ticks over
        // to be liquidatable
        uint128 expectedCurrentLtv = DEFAULT_OLTV + 29.616639616805159427e18;
        vm.mockCall(
            address(ltvOracle),
            abi.encodeWithSelector(ICoolerLtvOracle.currentLtvs.selector),
            abi.encode(DEFAULT_OLTV, expectedCurrentLtv - 1)
        );

        uint128 expectedDebt = borrowAmount + 296.166396168051594267e18;
        uint128 expectedIncentives = 1;
        vm.startPrank(OTHERS);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, ALICE, collateralAmount, expectedDebt, expectedIncentives);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, BOB, collateralAmount, expectedDebt, expectedIncentives);
        checkBatchLiquidate(
            twoAddresses(ALICE, BOB),
            twoDelegationRequests(noDelegationRequest(), noDelegationRequest()),
            collateralAmount*2,
            expectedDebt*2,
            expectedIncentives*2
        );
    }

    function test_batchLiquidate_wrongSizeDelegationRequests() external {
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidDelegationRequests.selector));
        cooler.batchLiquidate(
            twoAddresses(ALICE, BOB),
            oneDelegationRequest(noDelegationRequest())
        );
    }

    function test_batchLiquidate_fail_withPositiveDelegation() external {
        // Alice delegates some to BOB
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 365 days);

        // No 'delegation' requests allowed - only undelegations        
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidDelegationRequests.selector));
        cooler.batchLiquidate(
            oneAddress(ALICE),
            oneDelegationRequest(delegationRequest(BOB, 3.3e18))
        );
    }

    function test_batchLiquidate_fail_undelegateTooMuch() external {
        // Alice delegates some to BOB
        uint128 collateralAmount = 10e18;
        uint128 delegationAmount = 3e18;
        addCollateral(ALICE, ALICE, collateralAmount, delegationRequest(BOB, delegationAmount));
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 365 days);

        // No 'delegation' requests allowed - only undelegations        
        vm.expectRevert(abi.encodeWithSelector(DelegateEscrow.ExceededDelegationBalance.selector));
        cooler.batchLiquidate(
            oneAddress(ALICE),
            oneDelegationRequest(unDelegationRequest(BOB, 3.3e18))
        );
    }

    // @todo batchLiquidate with undelegates
    // @todo applyUnhealthyDelegations
}