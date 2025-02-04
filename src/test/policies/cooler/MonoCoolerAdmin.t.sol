// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";
import {Permissions, Keycode, fromKeycode, toKeycode} from "policies/RolesAdmin.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";
import {MonoCooler} from "policies/cooler/MonoCooler.sol";
import {Module, Policy, Actions} from "src/Kernel.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusGovDelegation} from "modules/DLGTE/OlympusGovDelegation.sol";
import {CoolerTreasuryBorrower} from "policies/cooler/CoolerTreasuryBorrower.sol";
import {ICoolerTreasuryBorrower} from "policies/interfaces/cooler/ICoolerTreasuryBorrower.sol";

contract MockLtvOracle {
    uint96 private immutable originationLtv;
    uint96 private immutable liquidationLtv;

    constructor(uint96 originationLtv_, uint96 liquidationLtv_) {
        originationLtv = originationLtv_;
        liquidationLtv = liquidationLtv_;
    }

    function currentLtvs() external view returns (uint96, uint96) {
        return (
            originationLtv,
            liquidationLtv
        );
    }
}

contract MonoCoolerAdminTest is MonoCoolerBaseTest {
    event BorrowPausedSet(bool isPaused);
    event LiquidationsPausedSet(bool isPaused);
    event InterestRateSet(uint16 interestRateBps);
    event LtvOracleSet(address indexed oracle);
    event TreasuryBorrowerSet(address indexed newTreasuryBorrower);

    event MaxDelegateAddressesSet(address indexed account, uint256 maxDelegateAddresses);

    function test_construction_failDecimalsCollateral() public {
        gohm = new MockGohm("gOHM", "gOHM", 6);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler = new MonoCooler(
            address(ohm),
            address(gohm),
            address(staking),
            address(kernel),
            address(ltvOracle),
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );
    }

    function test_construction_failLtv() public {
        address badOracle = address(new MockLtvOracle(123e18, 123e18-1));
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler = new MonoCooler(
            address(ohm),
            address(gohm),
            address(staking),
            address(kernel),
            badOracle,
            DEFAULT_INTEREST_RATE_BPS,
            DEFAULT_MIN_DEBT_REQUIRED
        );
    }

    // @todo new test for bad treasury borrower

    function test_construction_success() public view {
        assertEq(address(cooler.collateralToken()), address(gohm));
        assertEq(address(cooler.debtToken()), address(usds));
        assertEq(address(cooler.ohm()), address(ohm));
        assertEq(address(cooler.staking()), address(staking));
        assertEq(cooler.minDebtRequired(), DEFAULT_MIN_DEBT_REQUIRED);
        assertEq(address(cooler.MINTR()), address(MINTR));
        assertEq(address(cooler.DLGTE()), address(DLGTE));

        assertEq(cooler.totalCollateral(), 0);
        assertEq(cooler.totalDebt(), 0);
        assertEq(cooler.liquidationsPaused(), false);
        assertEq(cooler.borrowsPaused(), false);
        assertEq(cooler.interestRateBps(), DEFAULT_INTEREST_RATE_BPS);
        assertEq(address(cooler.treasuryBorrower()), address(treasuryBorrower));
        assertEq(address(cooler.ltvOracle()), address(ltvOracle));
        (uint96 maxOriginationLtv, uint96 liquidationLtv) = cooler.loanToValues();
        assertEq(maxOriginationLtv, DEFAULT_OLTV);
        assertEq(liquidationLtv, DEFAULT_LLTV);
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
                currentLtv: type(uint128).max,
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
                currentLtv: type(uint128).max,
                exceededLiquidationLtv: false,
                exceededMaxOriginationLtv: false,
                currentIncentive: 0
            })
        );

        assertEq(
            cooler.DOMAIN_SEPARATOR(), 
            keccak256(abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"), 
                block.chainid, 
                address(cooler)
            ))
        );
    }

    function test_configureDependencies_success() public {
        Keycode[] memory expectedDeps = new Keycode[](3);
        expectedDeps[0] = toKeycode("DLGTE");
        expectedDeps[1] = toKeycode("MINTR");
        expectedDeps[2] = toKeycode("ROLES");

        Keycode[] memory deps = cooler.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));

        assertEq(ohm.allowance(address(cooler), address(MINTR)), type(uint256).max);
        assertEq(gohm.allowance(address(cooler), address(DLGTE)), type(uint256).max);
    }

    function test_configureDependencies_failVersions() public {
        vm.mockCall(
            address(MINTR),
            abi.encodeWithSelector(Module.VERSION.selector),
            abi.encode(uint8(2), uint8(1))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([1, 1, 1])
            )
        );
        cooler.configureDependencies();
    }

    function test_changingDependencies() public {
        assertEq(ohm.allowance(address(cooler), address(MINTR)), type(uint256).max);
        assertEq(gohm.allowance(address(cooler), address(DLGTE)), type(uint256).max);

        vm.startPrank(EXECUTOR);
        OlympusMinter newMINTR = new OlympusMinter(kernel, address(ohm));
        OlympusGovDelegation newDLGTE = new OlympusGovDelegation(kernel, address(gohm), escrowFactory);
        kernel.executeAction(Actions.UpgradeModule, address(newMINTR));
        kernel.executeAction(Actions.UpgradeModule, address(newDLGTE));
        
        assertEq(ohm.allowance(address(cooler), address(MINTR)), 0);
        assertEq(gohm.allowance(address(cooler), address(DLGTE)), 0);
        assertEq(ohm.allowance(address(cooler), address(newMINTR)), type(uint256).max);
        assertEq(gohm.allowance(address(cooler), address(newDLGTE)), type(uint256).max);
    }

    function test_requestPermissions() public view {
        Permissions[] memory expectedPerms = new Permissions[](5);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode DLGTE_KEYCODE = toKeycode("DLGTE");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPerms[1] = Permissions(DLGTE_KEYCODE, DLGTE.depositUndelegatedGohm.selector);
        expectedPerms[2] = Permissions(DLGTE_KEYCODE, DLGTE.withdrawUndelegatedGohm.selector);
        expectedPerms[3] = Permissions(DLGTE_KEYCODE, DLGTE.applyDelegations.selector);
        expectedPerms[4] = Permissions(DLGTE_KEYCODE, DLGTE.setMaxDelegateAddresses.selector);

        Permissions[] memory perms = cooler.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    function test_setLtvOracle_fail_newOLTV_gt_newLLTV() public {
        address badOracle = address(new MockLtvOracle(123e18, 123e18-1));
        vm.startPrank(OVERSEER);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.setLtvOracle(address(badOracle));
    }

    function test_setLtvOracle_fail_newOLTV_lt_oldOLTV() public {
        address badOracle = address(new MockLtvOracle(
            ltvOracle.currentOriginationLtv()-1,
            ltvOracle.currentLiquidationLtv ()
        ));
        vm.startPrank(OVERSEER);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.setLtvOracle(address(badOracle));
    }

    function test_setLtvOracle_fail_newLLTV_lt_oldLLTV() public {
        address badOracle = address(new MockLtvOracle(
            ltvOracle.currentOriginationLtv(),
            ltvOracle.currentLiquidationLtv()-1 
        ));
        vm.startPrank(OVERSEER);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.setLtvOracle(address(badOracle));
    }

    function test_setLtvOracle_success() public {
        address newOracle = address(new MockLtvOracle(
            ltvOracle.currentOriginationLtv()+5,
            ltvOracle.currentLiquidationLtv()+5 
        ));
        vm.startPrank(OVERSEER);
        vm.expectEmit(address(cooler));
        emit LtvOracleSet(address(newOracle));
        cooler.setLtvOracle(address(newOracle));
        assertEq(address(cooler.ltvOracle()), newOracle);
        (uint96 oltv, uint96 lltv) = cooler.loanToValues();
        assertEq(oltv, DEFAULT_OLTV+5);
        assertEq(lltv, DEFAULT_LLTV+5);
    }

    function test_setTreasuryBorrower_failDecimals() public {
        treasuryBorrower = new CoolerTreasuryBorrower(address(kernel), address(susds));
        vm.mockCall(
            address(treasuryBorrower),
            abi.encodeWithSelector(ICoolerTreasuryBorrower.DECIMALS.selector),
            abi.encode(6)
        );

        vm.startPrank(OVERSEER);
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidParam.selector));
        cooler.setTreasuryBorrower(address(treasuryBorrower));
    }

    function test_setTreasuryBorrower_success() public {
        CoolerTreasuryBorrower newTreasuryBorrower = new CoolerTreasuryBorrower(address(kernel), address(susds));
        vm.startPrank(OVERSEER);

        vm.expectEmit(address(cooler));
        emit TreasuryBorrowerSet(address(newTreasuryBorrower));
        cooler.setTreasuryBorrower(address(newTreasuryBorrower));
        assertEq(address(cooler.treasuryBorrower()), address(newTreasuryBorrower));
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
        checkGlobalState(0, 1.000411043359288828e27); // 1 month of accrual

        assertEq(cooler.interestRateBps(), 50);
        vm.expectEmit(address(cooler));
        emit InterestRateSet(100);
        cooler.setInterestRateBps(100);
        assertEq(cooler.interestRateBps(), 100);

        // Now has a checkpoint
        assertEq(cooler.interestAccumulatorRay(), 1.000411043359288828e27);
        assertEq(cooler.interestAccumulatorUpdatedAt(), uint32(vm.getBlockTimestamp()));
        checkGlobalState(0, 1.000411043359288828e27); // 1 month of accrual
    }

    function test_setMaxDelegateAddresses() public {
        uint128 collateralAmount = 10e18;

        // Add collateral with a delegation (50% of collateral)
        addCollateral(ALICE, ALICE, collateralAmount, delegationRequest(BOB, collateralAmount / 2));

        expectOneDelegation(ALICE, BOB, collateralAmount / 2);

        checkAccountPosition(
            ALICE,
            IMonoCooler.AccountPosition({
                collateral: collateralAmount,
                currentDebt: 0,
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
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
                maxOriginationDebtAmount: 29_616.4e18,
                liquidationDebtAmount: 29_912.564e18,
                healthFactor: type(uint256).max,
                currentLtv: 0,
                totalDelegated: collateralAmount / 2,
                numDelegateAddresses: 1,
                maxDelegateAddresses: 50
            })
        );
    }
}
