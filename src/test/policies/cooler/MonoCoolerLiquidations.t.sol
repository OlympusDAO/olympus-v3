// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/cooler/IMonoCooler.sol";
import {IDLGTEv1} from "modules/DLGTE/IDLGTE.v1.sol";
import {ICoolerLtvOracle} from "policies/interfaces/cooler/ICoolerLtvOracle.sol";
import {MonoCooler} from "policies/cooler/MonoCooler.sol";
import {Actions} from "policies/RolesAdmin.sol";
import {MockStakingReal} from "test/mocks/MockStakingReal.sol";

import {console2} from "forge-std/console2.sol";

contract MonoCoolerComputeLiquidityBaseTest is MonoCoolerBaseTest {
    function noAddresses() internal pure returns (address[] memory accounts) {
        accounts = new address[](0);
    }

    function oneAddress(address acct) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = acct;
    }

    function twoAddresses(
        address acct1,
        address acct2
    ) internal pure returns (address[] memory accounts) {
        accounts = new address[](2);
        accounts[0] = acct1;
        accounts[1] = acct2;
    }

    function noDelegationRequests()
        internal
        pure
        returns (IDLGTEv1.DelegationRequest[][] memory requests)
    {
        requests = new IDLGTEv1.DelegationRequest[][](0);
    }

    function oneDelegationRequest(
        IDLGTEv1.DelegationRequest[] memory request
    ) internal pure returns (IDLGTEv1.DelegationRequest[][] memory requests) {
        requests = new IDLGTEv1.DelegationRequest[][](1);
        requests[0] = request;
    }

    function twoDelegationRequests(
        IDLGTEv1.DelegationRequest[] memory request1,
        IDLGTEv1.DelegationRequest[] memory request2
    ) internal pure returns (IDLGTEv1.DelegationRequest[][] memory requests) {
        requests = new IDLGTEv1.DelegationRequest[][](2);
        requests[0] = request1;
        requests[1] = request2;
    }

    function _cooler2Setup(
        uint128 collateralAmount,
        uint256 delegationAmount
    ) internal returns (MonoCooler newCooler) {
        // Setup a second cooler so there's shared delegations going into the same
        // escrows and DLGTE tracking
        newCooler = new MonoCooler(
            address(ohm),
            address(gohm),
            address(staking),
            address(kernel),
            address(ltvOracle),
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );
        newCooler.setTreasuryBorrower(address(treasuryBorrower));
        rolesAdmin.grantRole("treasuryborrower_cooler", address(newCooler));

        vm.prank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(newCooler));

        // Alice supplies collateral into both coolers and delegates to BOB
        addCollateral(
            cooler,
            ALICE,
            ALICE,
            collateralAmount,
            delegationRequest(BOB, delegationAmount)
        );
        addCollateral(
            newCooler,
            ALICE,
            ALICE,
            collateralAmount,
            delegationRequest(BOB, delegationAmount)
        );

        // DLGTE reports back the total delegated across all policies
        expectOneDelegation(cooler, ALICE, BOB, 2 * delegationAmount);
        expectOneDelegation(newCooler, ALICE, BOB, 2 * delegationAmount);

        // Alice max borrows in both coolers
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(cooler, ALICE, ALICE, borrowAmount, ALICE);
        borrow(newCooler, ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 365 days);

        checkAccountPosition(
            cooler,
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 29_914.049768431554843335e18,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 0.999950332086659734e18,
                currentLtv: 2_991.404976843155484334e18,
                totalDelegated: 2 * delegationAmount,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );
        checkAccountPosition(
            newCooler,
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 29_914.049768431554843335e18,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: 0.999950332086659734e18,
                currentLtv: 2_991.404976843155484334e18,
                totalDelegated: 2 * delegationAmount,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );
    }
}

contract MonoCoolerComputeLiquidityTest is MonoCoolerComputeLiquidityBaseTest {
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
        ltvOracle.setOriginationLtvAt(
            DEFAULT_OLTV + 1e18,
            uint32(vm.getBlockTimestamp()) + 2 * 365 days
        );

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
        ltvOracle.setOriginationLtvAt(
            DEFAULT_OLTV + 1e18,
            uint32(vm.getBlockTimestamp()) + 2 * 365 days
        );

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
        deal(address(usds), ALICE, borrowAmount + expectedInterest);
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

    function test_computeLiquidity_overLLTV_cappedToCollateral() external {
        vm.prank(OVERSEER);
        cooler.setInterestRateWad(0.1e18); // 10% APR

        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(7 * 365 days);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 59_640.105685528620836545e18,
                currentLtv: 5_964.010568552862083655e18,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: 9.938145618519569515e18 // gOHM
            })
        );

        skip(1 * 365 days);
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: 65_912.510354604317547106e18,
                currentLtv: 6_591.251035460431754711e18,
                exceededLiquidationLtv: true,
                exceededMaxOriginationLtv: true,
                currentIncentive: collateralAmount // capped to gOHM collateral
            })
        );
    }
}

contract MonoCoolerApplyUnhealthyDelegations is MonoCoolerComputeLiquidityBaseTest {
    function test_applyUnhealthyDelegations_fail_paused() external {
        vm.prank(OVERSEER);
        cooler.setLiquidationsPaused(true);

        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.Paused.selector));
        cooler.applyUnhealthyDelegations(ALICE, type(uint256).max);
    }

    function test_applyUnhealthyDelegations_fail_cannotLiquidate() external {
        addCollateral(ALICE, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.CannotLiquidate.selector));
        cooler.applyUnhealthyDelegations(ALICE, type(uint256).max);
    }

    function test_applyUnhealthyDelegations_fail_noUndelegations() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, ALICE, collateralAmount, delegationRequest(BOB, 8e18));
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 365 days);

        vm.expectRevert(abi.encodeWithSelector(IDLGTEv1.DLGTE_InvalidAmount.selector));
        cooler.applyUnhealthyDelegations(ALICE, 0);
    }

    function test_applyUnhealthyDelegations_success_oneUndelegation() external {
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, ALICE, collateralAmount, delegationRequest(BOB, 8e18));
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 365 days);

        (uint256 totalUndelegated, uint256 undelegatedBalance) = cooler.applyUnhealthyDelegations(
            ALICE,
            1
        );
        assertEq(totalUndelegated, 8e18);
        assertEq(undelegatedBalance, collateralAmount);

        expectNoDelegations(ALICE);
        expectAccountDelegationSummary(ALICE, 10e18, 0, 0, 10);
    }

    function test_applyUnhealthyDelegations_success_twoUndelegations() external {
        uint128 collateralAmount = 10e18;

        IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](
            2
        );
        delegationRequests[0] = IDLGTEv1.DelegationRequest(BOB, 3e18);
        delegationRequests[1] = IDLGTEv1.DelegationRequest(OTHERS, 6e18);

        addCollateral(ALICE, ALICE, collateralAmount, delegationRequests);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(2 * 365 days);

        (uint256 totalUndelegated, uint256 undelegatedBalance) = cooler.applyUnhealthyDelegations(
            ALICE,
            2
        );
        assertEq(totalUndelegated, 3e18 + 6e18);
        assertEq(undelegatedBalance, collateralAmount);

        expectNoDelegations(ALICE);
        expectAccountDelegationSummary(ALICE, collateralAmount, 0, 0, 10);
    }

    function test_applyUnhealthyDelegations_fromOtherPolicy_empty() external {
        // 20 total, 2x5=10e18 delegated, 10e18 undelegated
        // So there's enough undelegated already - not allowed to undelegate anymore.
        uint128 collateralAmount = 10e18;
        uint256 delegationAmount = 5e18;
        MonoCooler cooler2 = _cooler2Setup(collateralAmount, delegationAmount);

        (uint256 totalUndelegated, uint256 undelegatedBalance) = cooler.applyUnhealthyDelegations(
            ALICE,
            10
        );
        assertEq(totalUndelegated, 0);
        assertEq(undelegatedBalance, collateralAmount);

        expectOneDelegation(cooler, ALICE, BOB, 2 * delegationAmount);
        expectOneDelegation(cooler2, ALICE, BOB, 2 * delegationAmount);
        expectAccountDelegationSummary(ALICE, 20e18, 2 * delegationAmount, 1, 10);
    }

    function test_applyUnhealthyDelegations_fromOtherPolicy_alreadyHasEnoughUndelegated() external {
        // 20 total, 2x5=10e18 delegated, 10e18 undelegated
        // So there's enough undelegated already - not allowed to undelegate anymore.
        uint128 collateralAmount = 10e18;
        uint256 delegationAmount = 5e18;
        _cooler2Setup(collateralAmount, delegationAmount);

        (uint256 totalUndelegated, uint256 undelegatedBalance) = cooler.applyUnhealthyDelegations(
            ALICE,
            10
        );
        assertEq(totalUndelegated, 0);
        assertEq(undelegatedBalance, collateralAmount);
    }

    function test_applyUnhealthyDelegations_fromOtherPolicy_lessThanEnough() external {
        // 20 total, 2x7=14e18 delegated, 6e18 undelegated
        // Only allowed to undelegate 4e18 in total
        uint128 collateralAmount = 10e18;
        uint256 delegationAmount = 7e18;
        MonoCooler cooler2 = _cooler2Setup(collateralAmount, delegationAmount);

        (uint256 totalUndelegated, uint256 undelegatedBalance) = cooler.applyUnhealthyDelegations(
            ALICE,
            10
        );
        assertEq(totalUndelegated, 4e18);
        assertEq(undelegatedBalance, collateralAmount);

        expectOneDelegation(cooler, ALICE, BOB, collateralAmount);
        expectOneDelegation(cooler2, ALICE, BOB, collateralAmount);
        expectAccountDelegationSummary(ALICE, 20e18, collateralAmount, 1, 10);
    }

    function test_applyUnhealthyDelegations_onlyOne() external {
        // 20 total, 2x7=14e18 delegated, 6e18 undelegated
        // Only allowed to undelegate 4e18 in total
        uint128 collateralAmount = 10e18;
        uint256 delegationAmount = 7e18;
        MonoCooler cooler2 = _cooler2Setup(collateralAmount, delegationAmount);

        address CHARLIE = makeAddr("CHARLIE");
        addCollateral(cooler, ALICE, ALICE, 33e18, delegationRequest(CHARLIE, 33e18));
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(cooler, ALICE, ALICE, borrowAmount, ALICE);
        skip(2 * 365 days);

        (uint256 totalUndelegated, uint256 undelegatedBalance) = cooler.applyUnhealthyDelegations(
            ALICE,
            1
        );
        assertEq(totalUndelegated, 33e18);
        assertEq(undelegatedBalance, 33e18 + 6e18);

        expectOneDelegation(cooler, ALICE, BOB, 14e18);
        expectOneDelegation(cooler2, ALICE, BOB, 14e18);
        expectAccountDelegationSummary(ALICE, 33e18 + 20e18, 14e18, 1, 10);
    }

    function test_applyUnhealthyDelegations_withMaxUndelegations() external {
        uint256 delegateAddressCount = 2600;
        uint128 collateralAmount = 10e18;

        // Set the max delegate addresses to the max possible
        vm.prank(OVERSEER);
        cooler.setMaxDelegateAddresses(ALICE, type(uint32).max);

        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        // Apply delegations individually, to mimic what would happen in a real scenario and to avoid the gas limit
        for (uint32 i; i < delegateAddressCount; ++i) {
            address delegateAddress = address(uint160(i + 1)); // i+1 to avoid 0 address
            IDLGTEv1.DelegationRequest[]
                memory delegationRequests = new IDLGTEv1.DelegationRequest[](1);
            delegationRequests[0] = IDLGTEv1.DelegationRequest(delegateAddress, 1);

            vm.prank(ALICE);
            cooler.applyDelegations(delegationRequests, ALICE);
        }

        // Reduce the LLTV to be one less such that it JUST ticks over
        // to be liquidatable
        skip(2 * 363.19 days);
        uint128 expectedCurrentLtv = DEFAULT_OLTV + 29.616639616805159427e18;
        vm.mockCall(
            address(ltvOracle),
            abi.encodeWithSelector(ICoolerLtvOracle.currentLtvs.selector),
            abi.encode(DEFAULT_OLTV, expectedCurrentLtv - 1)
        );

        // Apply unhealthy delegations
        console2.log("Applying unhealthy delegations");
        vm.startSnapshotGas("applyUnhealthyDelegations");
        cooler.applyUnhealthyDelegations(ALICE, delegateAddressCount);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("Gas used", gasUsed);

        // Ensure that the gas used is less than the block limit
        assertLt(gasUsed, 36000000, "Gas used is greater than the block limit");
    }
}

contract MonoCoolerLiquidationsTest is MonoCoolerComputeLiquidityBaseTest {
    event Liquidated(
        address indexed caller,
        address indexed account,
        uint128 collateralSeized,
        uint128 debtWiped,
        uint128 incentives
    );

    function test_batchLiquidate_fail_paused() external {
        vm.prank(OVERSEER);
        cooler.setLiquidationsPaused(true);

        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.Paused.selector));
        cooler.batchLiquidate(oneAddress(ALICE));
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

        checkBatchLiquidate(noAddresses(), 0, 0, 0);

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

        checkBatchLiquidate(oneAddress(ALICE), 0, 0, 0);

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

        checkBatchLiquidate(oneAddress(ALICE), 0, 0, 0);
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
        assertEq(lltv, expectedCurrentLtv - 1);

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
        checkBatchLiquidate(oneAddress(ALICE), collateralAmount, expectedDebt, expectedIncentives);

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

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                0 // min(0, borrowAmount - expectedDebt)
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
    }

    function test_batchLiquidate_cappedIncentive() external {
        vm.prank(OVERSEER);
        cooler.setInterestRateWad(0.1e18); // 10% APR

        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(8 * 365 days);
        uint128 expectedDebt = 65_912.510354604317547106e18;

        vm.startPrank(OTHERS);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, ALICE, collateralAmount, expectedDebt, collateralAmount);
        checkBatchLiquidate(oneAddress(ALICE), collateralAmount, expectedDebt, collateralAmount);
    }

    function test_batchLiquidate_noOhmToBurn() external {
        vm.prank(OVERSEER);
        cooler.setInterestRateWad(0.1e18); // 10% APR

        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        skip(7 * 365 days + 11 days);
        uint128 expectedDebt = 59_820.114099647806356219e18;

        // Mock that unstake gives back zero ohm
        vm.mockCall(
            address(staking),
            abi.encodeWithSelector(MockStakingReal.unstake.selector),
            abi.encode(0)
        );

        vm.startPrank(OTHERS);
        vm.expectEmit(address(cooler));
        emit Liquidated(OTHERS, ALICE, collateralAmount, expectedDebt, 9.998323814584335317e18);
        checkBatchLiquidate(
            oneAddress(ALICE),
            collateralAmount,
            expectedDebt,
            9.998323814584335317e18
        );

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                0 // min(0, borrowAmount - expectedDebt)
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
    }

    function test_batchLiquidate_twoAccounts_oneLiquidate() external {
        // Alice borrows just under, Bob borrow's max
        uint128 collateralAmount = 10e18;
        addCollateral(ALICE, collateralAmount);
        addCollateral(BOB, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount - 10, ALICE);
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
        assertEq(lltv, expectedCurrentLtv - 1);

        uint128 expectedDebt = borrowAmount + 296.166396168051594267e18;
        uint128 expectedIncentives = 1;
        checkLiquidityStatus(
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: collateralAmount,
                currentDebt: expectedDebt - 10,
                currentLtv: expectedCurrentLtv - 1,
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
        checkBatchLiquidate(
            twoAddresses(ALICE, BOB),
            collateralAmount,
            expectedDebt,
            expectedIncentives
        );

        // Alice is still just healthy
        {
            checkLiquidityStatus(
                ALICE,
                IMonoCooler.LiquidationStatus({
                    collateral: collateralAmount,
                    currentDebt: expectedDebt - 10,
                    currentLtv: expectedCurrentLtv - 1,
                    exceededLiquidationLtv: false,
                    exceededMaxOriginationLtv: true,
                    currentIncentive: 0
                })
            );

            checkAccountPosition(
                ALICE,
                IMonoCooler.AccountPosition({
                    collateral: collateralAmount,
                    currentDebt: expectedDebt - 10,
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

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                borrowAmount - 10 + borrowAmount - expectedDebt
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
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
        assertEq(lltv, expectedCurrentLtv - 1);

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
        checkBatchLiquidate(
            twoAddresses(ALICE, BOB),
            collateralAmount * 2,
            expectedDebt * 2,
            expectedIncentives * 2
        );

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
        assertEq(gohm.balanceOf(OTHERS), expectedIncentives * 2);

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                0 // min(0, borrowAmount + borrowAmount - expectedDebt)
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
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
            collateralAmount * 2,
            expectedDebt * 2,
            expectedIncentives * 2
        );

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                0 // min(0, borrowAmount + borrowAmount - expectedDebt - expectedDebt)
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
    }

    function test_batchLiquidate_twoAccounts_withUndelegations() external {
        uint128 collateralAmount = 10e18;

        IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](
            2
        );
        delegationRequests[0] = IDLGTEv1.DelegationRequest(BOB, 3e18);
        delegationRequests[1] = IDLGTEv1.DelegationRequest(OTHERS, 6e18);

        addCollateral(ALICE, ALICE, collateralAmount, delegationRequests);
        addCollateral(BOB, BOB, collateralAmount, delegationRequest(BOB, 10e18));
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

        delegationRequests[0] = IDLGTEv1.DelegationRequest(BOB, -3e18);
        delegationRequests[1] = IDLGTEv1.DelegationRequest(OTHERS, -6e18);

        vm.startPrank(OTHERS);
        checkBatchLiquidate(
            twoAddresses(ALICE, BOB),
            collateralAmount * 2,
            expectedDebt * 2,
            expectedIncentives * 2
        );

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
        assertEq(gohm.balanceOf(OTHERS), expectedIncentives * 2);

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                0 // min(0, borrowAmount + borrowAmount - expectedDebt - expectedDebt)
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
    }

    function test_batchLiquidate_twoCoolers_withUndelegations() external {
        // 20 total, 2x7=14e18 delegated, 6e18 undelegated
        // Only allowed to undelegate 4e18 in total
        uint128 collateralAmount = 10e18;
        uint256 delegationAmount = 7e18;
        MonoCooler cooler2 = _cooler2Setup(collateralAmount, delegationAmount);

        uint256 totalExpectedDebt = 2 * 29_616.4e18;
        uint128 wipedDebt = 29_914.049768431554843335e18;

        vm.startPrank(OTHERS);
        checkBatchLiquidate(
            oneAddress(ALICE),
            collateralAmount,
            wipedDebt,
            0.000496703803644129e18
        );

        // Delegations show the same, even though cooler was liquidated
        expectOneDelegation(cooler, ALICE, BOB, collateralAmount);
        expectOneDelegation(cooler2, ALICE, BOB, collateralAmount);
        expectAccountDelegationSummary(ALICE, 10e18, collateralAmount, 1, 10);

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                totalExpectedDebt - wipedDebt
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
    }

    function test_batchLiquidate_oneAccount_withMaxUndelegations() external {
        uint32 delegateAddressCount = 2600;
        uint128 collateralAmount = 10e18;

        // Set the max delegate addresses to the max possible
        vm.prank(OVERSEER);
        cooler.setMaxDelegateAddresses(ALICE, type(uint32).max);

        addCollateral(ALICE, collateralAmount);
        uint128 borrowAmount = uint128(cooler.debtDeltaForMaxOriginationLtv(ALICE, 0));
        borrow(ALICE, ALICE, borrowAmount, ALICE);

        // Apply delegations individually, to mimic what would happen in a real scenario and to avoid the gas limit
        for (uint32 i; i < delegateAddressCount; ++i) {
            address delegateAddress = address(uint160(i + 1)); // i+1 to avoid 0 address
            IDLGTEv1.DelegationRequest[]
                memory delegationRequests = new IDLGTEv1.DelegationRequest[](1);
            delegationRequests[0] = IDLGTEv1.DelegationRequest(delegateAddress, 1);

            vm.prank(ALICE);
            cooler.applyDelegations(delegationRequests, ALICE);
        }

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

        console2.log("starting liquidation");
        vm.startSnapshotGas("liquidate");
        vm.startPrank(OTHERS);
        checkBatchLiquidate(oneAddress(ALICE), collateralAmount, expectedDebt, expectedIncentives);
        uint256 gasUsed = vm.stopSnapshotGas();
        console2.log("gasUsed", gasUsed);

        // Ensure that the gas used is less than the block limit
        assertLt(gasUsed, 36000000, "Gas used is greater than the block limit");

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
                    maxDelegateAddresses: type(uint32).max
                })
            );
        }

        // Caller gets the total incentives
        assertEq(gohm.balanceOf(OTHERS), expectedIncentives);

        // Treasury Checks
        {
            assertEq(
                TRSRY.reserveDebt(usds, address(treasuryBorrower)),
                0 // min(0, borrowAmount + borrowAmount - expectedDebt - expectedDebt)
            );
            assertEq(TRSRY.withdrawApproval(address(treasuryBorrower), usds), 0);
        }
    }
}
