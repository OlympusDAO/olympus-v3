// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {Permissions, Keycode, fromKeycode, toKeycode} from "policies/RolesAdmin.sol";

contract MonoCoolerAdminTest is MonoCoolerBaseTest {
    event LiquidationLtvSet(uint256 ltv);
    event MaxOriginationLtvSet(uint256 ltv);
    event LiquidationsPausedSet(bool isPaused);
    event BorrowPausedSet(bool isPaused);
    event InterestRateSet(uint16 interestRateBps);
    event MaxDelegateAddressesSet(address indexed account, uint256 maxDelegateAddresses);

    function test_construction() public {
        assertEq(address(cooler.collateralToken()), address(gohm));
        assertEq(address(cooler.debtToken()), address(dai));
        assertEq(address(cooler.ohm()), address(ohm));
        assertEq(address(cooler.staking()), address(staking));
        assertEq(address(cooler.debtSavingsVault()), address(sdai));
        assertEq(cooler.minDebtRequired(), DEFAULT_MIN_DEBT_REQUIRED);
        assertEq(address(cooler.CHREG()), address(CHREG));
        assertEq(address(cooler.MINTR()), address(MINTR));
        assertEq(address(cooler.TRSRY()), address(TRSRY));

        assertEq(cooler.totalCollateral(), 0);
        assertEq(cooler.totalDebt(), 0);
        assertEq(cooler.liquidationsPaused(), false);
        assertEq(cooler.borrowsPaused(), false);
        assertEq(cooler.interestRateBps(), DEFAULT_INTEREST_RATE_BPS);
        assertEq(cooler.liquidationLtv(), DEFAULT_LLTV);
        assertEq(cooler.maxOriginationLtv(), DEFAULT_OLTV);
        assertEq(cooler.interestAccumulatorUpdatedAt(), uint32(block.timestamp));
        assertEq(cooler.interestAccumulatorRay(), 1e27);
        assertEq(cooler.DEFAULT_MAX_DELEGATE_ADDRESSES(), 10);

        (uint128 totalDebt, uint256 interestAccumulatorRay) = cooler.globalState();
        assertEq(totalDebt, 0);
        assertEq(interestAccumulatorRay, 1e27);

        IMonoCooler.AccountState memory aState = cooler.accountState(ALICE);
        assertEq(aState.collateral, 0);
        assertEq(aState.debtCheckpoint, 0);
        assertEq(aState.interestAccumulatorRay, 0);

        address[] memory accounts = new address[](1);
        accounts[0] = ALICE;
        IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
        assertEq(status.length, 1);
        assertEq(status[0].collateral, 0);
        assertEq(status[0].currentDebt, 0);
        assertEq(status[0].currentLtv, 0);
        assertEq(status[0].exceededLiquidationLtv, false);
        assertEq(status[0].exceededMaxOriginationLtv, false);
       
        IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
        assertEq(position.collateral, 0);
        assertEq(position.currentDebt, 0);
        assertEq(position.maxDebt, 0);
        assertEq(position.healthFactor, type(uint256).max);
        assertEq(position.currentLtv, 0);
    }

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](4);
        expectedDeps[0] = toKeycode("CHREG");
        expectedDeps[1] = toKeycode("MINTR");
        expectedDeps[2] = toKeycode("ROLES");
        expectedDeps[3] = toKeycode("TRSRY");

        Keycode[] memory deps = cooler.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
        assertEq(fromKeycode(deps[3]), fromKeycode(expectedDeps[3]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](6);
        Keycode CHREG_KEYCODE = toKeycode("CHREG");
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        expectedPerms[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        expectedPerms[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPerms[3] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        expectedPerms[4] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        expectedPerms[5] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);

        Permissions[] memory perms = cooler.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    function test_setLoanToValue_failDecreaseLLTV() public {
        vm.startPrank(OVERSEER);

        uint96 newLiquidationLtv = DEFAULT_LLTV - 1;
        uint96 newMaxOriginationLtv = DEFAULT_OLTV;
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.setLoanToValue(newLiquidationLtv, newMaxOriginationLtv);
    }

    function test_setLoanToValue_increaseLLTV() public {
        vm.startPrank(OVERSEER);

        uint96 newLiquidationLtv = DEFAULT_LLTV + 1;
        uint96 newMaxOriginationLtv = DEFAULT_OLTV;

        vm.expectEmit(address(cooler));
        emit LiquidationLtvSet(newLiquidationLtv);
        cooler.setLoanToValue(newLiquidationLtv, newMaxOriginationLtv);
        assertEq(cooler.liquidationLtv(), newLiquidationLtv);
        assertEq(cooler.maxOriginationLtv(), newMaxOriginationLtv);
    }

    function test_setLoanToValue_noChange() public {
        vm.startPrank(OVERSEER);

        uint96 newLiquidationLtv = DEFAULT_LLTV;
        uint96 newMaxOriginationLtv = DEFAULT_OLTV;
        cooler.setLoanToValue(newLiquidationLtv, newMaxOriginationLtv);
        assertEq(cooler.liquidationLtv(), newLiquidationLtv);
        assertEq(cooler.maxOriginationLtv(), newMaxOriginationLtv);
    }

    function test_setLoanToValue_failHighOLTV() public {
        vm.startPrank(OVERSEER);

        uint96 newLiquidationLtv = DEFAULT_LLTV;
        uint96 newMaxOriginationLtv = DEFAULT_LLTV;
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.setLoanToValue(newLiquidationLtv, newMaxOriginationLtv);

        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.setLoanToValue(newLiquidationLtv, newMaxOriginationLtv+1);
    }

    function test_setLoanToValue_setOLTV() public {
        vm.startPrank(OVERSEER);

        uint96 newLiquidationLtv = DEFAULT_LLTV;
        uint96 newMaxOriginationLtv = DEFAULT_LLTV-1;
        vm.expectEmit(address(cooler));
        emit MaxOriginationLtvSet(newMaxOriginationLtv);
        cooler.setLoanToValue(newLiquidationLtv, newMaxOriginationLtv);
        assertEq(cooler.liquidationLtv(), newLiquidationLtv);
        assertEq(cooler.maxOriginationLtv(), newMaxOriginationLtv);
    }

    function test_setLiquidationsPaused() public {
        vm.startPrank(OVERSEER);

        assertEq(cooler.liquidationsPaused(), false);
        vm.expectEmit(address(cooler));
        emit LiquidationsPausedSet(true);
        cooler.setLiquidationsPaused(true);
        assertEq(cooler.liquidationsPaused(), true);

        vm.expectEmit(address(cooler));
        emit LiquidationsPausedSet(false);
        cooler.setLiquidationsPaused(false);
        assertEq(cooler.liquidationsPaused(), false);
    }

    function test_setBorrowPaused() public {
        vm.startPrank(OVERSEER);

        assertEq(cooler.borrowsPaused(), false);
        vm.expectEmit(address(cooler));
        emit BorrowPausedSet(true);
        cooler.setBorrowPaused(true);
        assertEq(cooler.borrowsPaused(), true);

        vm.expectEmit(address(cooler));
        emit BorrowPausedSet(false);
        cooler.setBorrowPaused(false);
        assertEq(cooler.borrowsPaused(), false);
    }

    function test_setInterestRateBps() public {
        vm.startPrank(OVERSEER);

        skip(30 days);
        assertEq(cooler.interestAccumulatorRay(), 1e27); // not checkpoint yet
        checkGlobalState(0, 1.00041104335690626e27); // 1 month of accrual

        assertEq(cooler.interestRateBps(), 50);
        vm.expectEmit(address(cooler));
        emit InterestRateSet(100);
        cooler.setInterestRateBps(100);
        assertEq(cooler.interestRateBps(), 100);

        // Now has a checkpoint
        assertEq(cooler.interestAccumulatorRay(), 1.00041104335690626e27);
        assertEq(cooler.interestAccumulatorUpdatedAt(), uint32(block.timestamp));
        checkGlobalState(0, 1.00041104335690626e27); // 1 month of accrual
    }

    function test_setMaxDelegateAddresses() public {
        uint128 collateralAmount = 10e18;
        
        // Add collateral with a delegation (50% of collateral)
        {
            IMonoCooler.DelegationRequest[] memory delegationRequests = new IMonoCooler.DelegationRequest[](1);
            delegationRequests[0] = IMonoCooler.DelegationRequest({
                fromDelegate: address(0),
                toDelegate: BOB,
                collateralAmount: collateralAmount/2
            });
            addCollateral(ALICE, collateralAmount, delegationRequests);
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
            assertEq(position.maxDebt, 9.3e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, collateralAmount/2);
            assertEq(position.numDelegateAddresses, 1);
            assertEq(position.maxDelegateAddresses, 10);
        }

        vm.startPrank(OVERSEER);
        vm.expectEmit(address(cooler));
        emit MaxDelegateAddressesSet(ALICE, 50);
        cooler.setMaxDelegateAddresses(ALICE, 50);

        // The maxDelegateAddresses has increased
        {
            IMonoCooler.AccountPosition memory position = cooler.accountPosition(ALICE);
            assertEq(position.collateral, collateralAmount);
            assertEq(position.currentDebt, 0);
            assertEq(position.maxDebt, 9.3e18);
            assertEq(position.healthFactor, type(uint256).max);
            assertEq(position.currentLtv, 0);
            assertEq(position.totalDelegated, collateralAmount/2);
            assertEq(position.numDelegateAddresses, 1);
            assertEq(position.maxDelegateAddresses, 50);
        }
    }
}