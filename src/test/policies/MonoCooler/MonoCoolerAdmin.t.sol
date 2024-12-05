// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {Permissions, Keycode, fromKeycode, toKeycode} from "policies/RolesAdmin.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";
import {MonoCooler} from "policies/MonoCooler.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {Module, Policy} from "src/Kernel.sol";

contract MonoCoolerAdminTest is MonoCoolerBaseTest {
    event LiquidationLtvSet(uint256 ltv);
    event MaxOriginationLtvSet(uint256 ltv);
    event LiquidationsPausedSet(bool isPaused);
    event BorrowPausedSet(bool isPaused);
    event InterestRateSet(uint16 interestRateBps);

    event MaxDelegateAddressesSet(address indexed account, uint256 maxDelegateAddresses);

    function test_construction_failDecimalsCollateral() public {
        gohm = new MockGohm("gOHM", "gOHM", 6);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler = new MonoCooler(
            address(ohm),
            address(gohm),
            address(staking),
            address(sdai),
            address(kernel),
            DEFAULT_LLTV,
            DEFAULT_OLTV,
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );
    }

    function test_construction_failDecimalsDebt() public {
        dai = new MockERC20("dai", "DAI", 6);
        sdai = new MockERC4626(dai, "sDai", "sDAI");
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler = new MonoCooler(
            address(ohm),
            address(gohm),
            address(staking),
            address(sdai),
            address(kernel),
            DEFAULT_LLTV,
            DEFAULT_OLTV,
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );
    }

    function test_construction_success() public {
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
        assertEq(cooler.interestAccumulatorUpdatedAt(), uint32(vm.getBlockTimestamp()));
        assertEq(cooler.interestAccumulatorRay(), 1e27);

        (uint128 totalDebt, uint256 interestAccumulatorRay) = cooler.globalState();
        assertEq(totalDebt, 0);
        assertEq(interestAccumulatorRay, 1e27);

        checkAccountState(
            ALICE,
            IMonoCooler.AccountState({collateral: 0, debtCheckpoint: 0, interestAccumulatorRay: 0})
        );

        checkAccountPosition(
            ALICE,
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
            ALICE,
            IMonoCooler.LiquidationStatus({
                collateral: 0,
                currentDebt: 0,
                currentLtv: type(uint256).max,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false
            })
        );
    }

    function test_configureDependencies_success() public {
        Keycode[] memory expectedDeps = new Keycode[](5);
        expectedDeps[0] = toKeycode("CHREG");
        expectedDeps[1] = toKeycode("MINTR");
        expectedDeps[2] = toKeycode("ROLES");
        expectedDeps[3] = toKeycode("TRSRY");
        expectedDeps[4] = toKeycode("DLGTE");

        Keycode[] memory deps = cooler.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
        assertEq(fromKeycode(deps[3]), fromKeycode(expectedDeps[3]));
        assertEq(fromKeycode(deps[4]), fromKeycode(expectedDeps[4]));
    }

    function test_configureDependencies_fail() public {
        vm.mockCall(
            address(CHREG),
            abi.encodeWithSelector(Module.VERSION.selector),
            abi.encode(uint8(2), uint8(1))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([1, 1, 1, 1, 1])
            )
        );
        cooler.configureDependencies();
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](10);
        Keycode CHREG_KEYCODE = toKeycode("CHREG");
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        Keycode DLGTE_KEYCODE = toKeycode("DLGTE");
        expectedPerms[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        expectedPerms[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPerms[3] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        expectedPerms[4] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        expectedPerms[5] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        expectedPerms[6] = Permissions(DLGTE_KEYCODE, DLGTE.depositUndelegatedGohm.selector);
        expectedPerms[7] = Permissions(DLGTE_KEYCODE, DLGTE.withdrawUndelegatedGohm.selector);
        expectedPerms[8] = Permissions(DLGTE_KEYCODE, DLGTE.applyDelegations.selector);
        expectedPerms[9] = Permissions(DLGTE_KEYCODE, DLGTE.setMaxDelegateAddresses.selector);

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
        cooler.setLoanToValue(newLiquidationLtv, newMaxOriginationLtv + 1);
    }

    function test_setLoanToValue_setOLTV() public {
        vm.startPrank(OVERSEER);

        uint96 newLiquidationLtv = DEFAULT_LLTV;
        uint96 newMaxOriginationLtv = DEFAULT_LLTV - 1;
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

        vm.warp(START_TIMESTAMP + 30 days);
        assertEq(cooler.interestAccumulatorRay(), 1e27); // not checkpoint yet
        checkGlobalState(0, 1.00041104335690626e27); // 1 month of accrual

        assertEq(cooler.interestRateBps(), 50);
        vm.expectEmit(address(cooler));
        emit InterestRateSet(100);
        cooler.setInterestRateBps(100);
        assertEq(cooler.interestRateBps(), 100);

        // Now has a checkpoint
        assertEq(cooler.interestAccumulatorRay(), 1.00041104335690626e27);
        assertEq(cooler.interestAccumulatorUpdatedAt(), uint32(vm.getBlockTimestamp()));
        checkGlobalState(0, 1.00041104335690626e27); // 1 month of accrual
    }

    function test_setMaxDelegateAddresses() public {
        uint128 collateralAmount = 10e18;

        // Add collateral with a delegation (50% of collateral)
        addCollateral(ALICE, collateralAmount, delegationRequest(BOB, collateralAmount / 2));

        expectOneDelegation(ALICE, BOB, collateralAmount / 2);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 9.3e18,
                liquidationDebtAmount: 9.4e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: collateralAmount / 2,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 10
            })
        );

        vm.startPrank(OVERSEER);
        vm.expectEmit(address(DLGTE));
        emit MaxDelegateAddressesSet(ALICE, 50);
        cooler.setMaxDelegateAddresses(ALICE, 50);

        // The maxDelegateAddresses has increased
        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 9.3e18,
                liquidationDebtAmount: 9.4e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: collateralAmount / 2,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 50
            })
        );
    }
}
