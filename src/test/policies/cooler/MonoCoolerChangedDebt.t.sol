// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/cooler/IMonoCooler.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockCoolerTreasuryBorrower} from "./MockCoolerTreasuryBorrower.m.sol";
import {Actions} from "src/Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract MonoCoolerChangeDebtToken18dpTest is MonoCoolerBaseTest {
    MockERC20 internal dai;
    MockCoolerTreasuryBorrower internal mockTreasuryBorrower;

    uint256 internal constant INITIAL_TRSRY_MINT_DAI = 200_000_000e18;

    function setUp() public override {
        MonoCoolerBaseTest.setUp();
        dai = new MockERC20("dai", "DAI", 18);
        mockTreasuryBorrower = new MockCoolerTreasuryBorrower(address(kernel), address(dai));
    }

    function changeDebtToken() private returns (uint128) {
        // 1. Net settle the debt - so clear out debt in the old TB
        uint256 outstandingDebt = TRSRY.reserveDebt(usds, address(treasuryBorrower));
        vm.startPrank(TB_ADMIN);
        treasuryBorrower.setDebt(0);

        // 2. Deactivate the old TB, activate the new TB
        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.DeactivatePolicy, address(treasuryBorrower));
        kernel.executeAction(Actions.ActivatePolicy, address(mockTreasuryBorrower));

        // Enable the mock TB
        vm.startPrank(TB_ADMIN);
        mockTreasuryBorrower.enable(abi.encode(""));
        vm.stopPrank();

        // 3. Set the outstanding debt on the new treasuryBorrower
        // It's up to the admin to do the correct decimals conversions.
        vm.startPrank(TB_ADMIN);
        mockTreasuryBorrower.setDebt(outstandingDebt);

        // 4. Set to the new TB on cooler
        vm.startPrank(OVERSEER);
        cooler.setTreasuryBorrower(address(mockTreasuryBorrower));

        // Seed the treasury with DAI for new borrows
        dai.mint(address(TRSRY), INITIAL_TRSRY_MINT_DAI);

        assertEq(address(cooler.debtToken()), address(dai));
        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), 0);
        assertEq(TRSRY.reserveDebt(dai, address(mockTreasuryBorrower)), outstandingDebt);

        vm.stopPrank();
        return uint128(outstandingDebt);
    }

    function test_changeDebt_existingPosition() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowedAmountUsds = 10_000e18;
        uint128 repayAmountUsds = 2_000e18;
        uint128 borrowedAmountDai = 5_000e18;
        uint128 repayAmountDai = 1_000e18;

        addCollateral(ALICE, collateralAmount);

        // Borrow USDS
        vm.startPrank(ALICE);
        cooler.borrow(borrowedAmountUsds, ALICE, ALICE);
        skip(365 days);

        // Repay USDS
        usds.approve(address(cooler), repayAmountUsds);
        cooler.repay(repayAmountUsds, ALICE);

        // Check Treasury
        {
            assertEq(usds.balanceOf(address(TRSRY)), 0);
            assertEq(
                susds.balanceOf(address(TRSRY)),
                INITIAL_TRSRY_MINT - (borrowedAmountUsds - repayAmountUsds)
            );
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                borrowedAmountUsds - repayAmountUsds
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);

            assertEq(dai.balanceOf(address(TRSRY)), 0);
            assertEq(TRSRY.reserveDebt(dai, address(mockTreasuryBorrower)), 0);
            assertEq(TRSRY.withdrawApproval(address(mockTreasuryBorrower), dai), 0);
        }

        uint128 inheritedDebt = changeDebtToken();

        // Repay DAI
        vm.startPrank(ALICE);
        dai.mint(ALICE, repayAmountDai);
        dai.approve(address(cooler), repayAmountDai);
        cooler.repay(repayAmountDai, ALICE);

        assertEq(
            TRSRY.reserveDebt(dai, address(mockTreasuryBorrower)),
            inheritedDebt - repayAmountDai
        );

        // Borrow DAI
        cooler.borrow(borrowedAmountDai, ALICE, ALICE);

        // Check Treasury
        {
            // No change here...
            assertEq(usds.balanceOf(address(TRSRY)), 0);
            assertEq(susds.balanceOf(address(TRSRY)), INITIAL_TRSRY_MINT - inheritedDebt);
            assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), 0);
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);

            assertEq(
                dai.balanceOf(address(TRSRY)),
                INITIAL_TRSRY_MINT_DAI - (borrowedAmountDai - repayAmountDai)
            );
            assertEq(
                TRSRY.reserveDebt(dai, address(mockTreasuryBorrower)),
                inheritedDebt - repayAmountDai + borrowedAmountDai
            );
            assertEq(TRSRY.withdrawApproval(address(mockTreasuryBorrower), dai), 0);
        }

        uint128 expectedInterest = 50.125208594010630000e18;
        uint128 expectedTotalDebt = inheritedDebt -
            repayAmountDai +
            borrowedAmountDai +
            expectedInterest;
        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(cooler.totalDebt(), expectedTotalDebt);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1.005012520859401063e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(usds.balanceOf(ALICE), borrowedAmountUsds - repayAmountUsds);
        assertEq(dai.balanceOf(ALICE), borrowedAmountDai); // started off with already having 1k DAI

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: expectedTotalDebt,
                interestAccumulatorRay: 1.005012520859401063e27
            })
        );

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: expectedTotalDebt,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 2.482344662997086833e18,
                currentLtv: 1_205.012520859401063e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedTotalDebt,
                currentLtv: 1_205.012520859401063e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );

        checkGlobalState(expectedTotalDebt, 1.005012520859401063e27);
    }
}

contract MonoCoolerChangeDebtToken6dpTest is MonoCoolerBaseTest {
    MockERC20 internal usdc;
    MockCoolerTreasuryBorrower internal mockTreasuryBorrower;

    uint256 internal constant INITIAL_TRSRY_MINT_USDC = 200_000_000e6;
    uint128 internal constant USDC_TO_18DP_SCALAR = 1e12;

    function setUp() public override {
        MonoCoolerBaseTest.setUp();
        usdc = new MockERC20("usdc", "USDC", 6);
        mockTreasuryBorrower = new MockCoolerTreasuryBorrower(address(kernel), address(usdc));
    }

    function changeDebtToken() private returns (uint128) {
        // 1. Net settle the debt - so clear out debt in the old TB
        uint256 outstandingDebt = TRSRY.reserveDebt(usds, address(treasuryBorrower));
        vm.startPrank(TB_ADMIN);
        treasuryBorrower.setDebt(0);

        // 2. Deactivate the old TB, activate the new TB
        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.DeactivatePolicy, address(treasuryBorrower));
        kernel.executeAction(Actions.ActivatePolicy, address(mockTreasuryBorrower));

        // Enable the mock TB
        vm.startPrank(TB_ADMIN);
        mockTreasuryBorrower.enable(abi.encode(""));
        vm.stopPrank();

        // 3. Set the outstanding debt on the new treasuryBorrower
        // It's up to the admin to do the correct decimals conversions.
        vm.startPrank(TB_ADMIN);
        mockTreasuryBorrower.setDebt(outstandingDebt / USDC_TO_18DP_SCALAR);

        // 4. Set to the new TB on cooler
        vm.startPrank(OVERSEER);
        cooler.setTreasuryBorrower(address(mockTreasuryBorrower));

        // Seed the treasury with usdc for new borrows
        usdc.mint(address(TRSRY), INITIAL_TRSRY_MINT_USDC);

        assertEq(address(cooler.debtToken()), address(usdc));
        assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), 0);
        assertEq(
            TRSRY.reserveDebt(usdc, address(mockTreasuryBorrower)),
            outstandingDebt / USDC_TO_18DP_SCALAR
        );

        vm.stopPrank();
        return uint128(outstandingDebt);
    }

    function test_changeDebt_existingPosition() public {
        uint128 collateralAmount = 10e18;
        uint128 borrowedAmountUsds = 10_000e18;
        uint128 repayAmountUsds = 2_000e18;
        uint128 borrowedAmountUsdc = 5_000e6;
        uint128 repayAmountUsdc = 1_000e6;

        {
            (IERC20 dToken, uint256 dTokenAmount) = treasuryBorrower.convertToDebtTokenAmount(1e18);
            assertEq(address(dToken), address(usds));
            assertEq(dTokenAmount, 1e18);

            (dToken, dTokenAmount) = mockTreasuryBorrower.convertToDebtTokenAmount(1e18);
            assertEq(address(dToken), address(usdc));
            assertEq(dTokenAmount, 1e6);
        }

        addCollateral(ALICE, collateralAmount);

        // Borrow USDS
        vm.startPrank(ALICE);
        cooler.borrow(borrowedAmountUsds, ALICE, ALICE);
        skip(365 days);

        // Repay USDS
        usds.approve(address(cooler), repayAmountUsds);
        cooler.repay(repayAmountUsds, ALICE);

        // Check Treasury
        {
            assertEq(usds.balanceOf(address(TRSRY)), 0);
            assertEq(
                susds.balanceOf(address(TRSRY)),
                INITIAL_TRSRY_MINT - (borrowedAmountUsds - repayAmountUsds)
            );
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                borrowedAmountUsds - repayAmountUsds
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);

            assertEq(usdc.balanceOf(address(TRSRY)), 0);
            assertEq(TRSRY.reserveDebt(usdc, address(mockTreasuryBorrower)), 0);
            assertEq(TRSRY.withdrawApproval(address(mockTreasuryBorrower), usdc), 0);
        }

        uint128 inheritedDebt = changeDebtToken();

        // Repay USDC
        vm.startPrank(ALICE);
        usdc.mint(ALICE, repayAmountUsdc);
        usdc.approve(address(cooler), repayAmountUsdc);
        cooler.repay(repayAmountUsdc * USDC_TO_18DP_SCALAR, ALICE);

        assertEq(
            TRSRY.reserveDebt(usdc, address(mockTreasuryBorrower)),
            (inheritedDebt / USDC_TO_18DP_SCALAR) - repayAmountUsdc
        );

        // Borrow USDC
        cooler.borrow(borrowedAmountUsdc * USDC_TO_18DP_SCALAR, ALICE, ALICE);

        // Check Treasury
        {
            // No change here...
            assertEq(usds.balanceOf(address(TRSRY)), 0);
            assertEq(susds.balanceOf(address(TRSRY)), INITIAL_TRSRY_MINT - inheritedDebt);
            assertEq(TRSRY.reserveDebt(usds, address(treasuryBorrower)), 0);
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);

            assertEq(
                usdc.balanceOf(address(TRSRY)),
                INITIAL_TRSRY_MINT_USDC - (borrowedAmountUsdc - repayAmountUsdc)
            );
            assertEq(
                TRSRY.reserveDebt(usdc, address(mockTreasuryBorrower)),
                inheritedDebt / USDC_TO_18DP_SCALAR - repayAmountUsdc + borrowedAmountUsdc
            );
            assertEq(TRSRY.withdrawApproval(address(mockTreasuryBorrower), usdc), 0);
        }

        uint128 expectedInterest = 50.125208594010630000e18;
        uint128 expectedTotalDebt = inheritedDebt -
            repayAmountUsdc *
            USDC_TO_18DP_SCALAR +
            borrowedAmountUsdc *
            USDC_TO_18DP_SCALAR +
            expectedInterest;
        assertEq(cooler.totalCollateral(), collateralAmount);
        assertEq(cooler.totalDebt(), expectedTotalDebt);
        assertEq(cooler.interestAccumulatorUpdatedAt(), vm.getBlockTimestamp());
        assertEq(cooler.interestAccumulatorRay(), 1.005012520859401063e27);
        assertEq(gohm.balanceOf(ALICE), 0);
        assertEq(gohm.balanceOf(address(cooler)), 0);
        assertEq(usds.balanceOf(ALICE), borrowedAmountUsds - repayAmountUsds);
        assertEq(usdc.balanceOf(ALICE), borrowedAmountUsdc); // started off with already having 1k USDC

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({
                collateral: collateralAmount,
                debtCheckpoint: expectedTotalDebt,
                interestAccumulatorRay: 1.005012520859401063e27
            })
        );

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: expectedTotalDebt,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 2.482344662997086833e18,
                currentLtv: 1_205.012520859401063e18,
                totalDelegated: 0,
                numDelegateAddresses: 0,
                maxDelegateAddresses: 10
            })
        );

        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedTotalDebt,
                currentLtv: 1_205.012520859401063e18,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );

        checkGlobalState(expectedTotalDebt, 1.005012520859401063e27);
    }
}
