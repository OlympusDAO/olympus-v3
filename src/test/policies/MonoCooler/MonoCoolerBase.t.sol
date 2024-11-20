// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {MonoCooler} from "policies/MonoCooler.sol";
import {IMonoCooler} from "policies/interfaces/IMonoCooler.sol";

import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockStaking} from "test/mocks/MockStaking.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {RolesAdmin, Kernel, Actions} from "policies/RolesAdmin.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusClearinghouseRegistry} from "modules/CHREG/OlympusClearinghouseRegistry.sol";
import {OlympusGovDelegation, DLGTEv1} from "modules/DLGTE/OlympusGovDelegation.sol";

abstract contract MonoCoolerBaseTest is Test {
    MockOhm internal ohm;
    MockGohm internal gohm;
    MockERC20 internal dai;
    MockERC4626 internal sdai;

    Kernel public kernel;
    MockStaking internal staking;
    OlympusRoles internal ROLES;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;
    OlympusClearinghouseRegistry internal CHREG;
    OlympusGovDelegation internal DLGTE;
    RolesAdmin internal rolesAdmin;

    MonoCooler public cooler;

    address internal immutable OVERSEER = makeAddr("overseer");
    address internal immutable ALICE = makeAddr("alice");
    address internal immutable BOB = makeAddr("bob");
    address internal immutable OTHERS = makeAddr("others");

    uint96 internal constant DEFAULT_LLTV = 0.94e18;
    uint96 internal constant DEFAULT_OLTV = 0.93e18;
    uint16 internal constant DEFAULT_INTEREST_RATE_BPS = 50; // 0.5%
    uint256 internal constant DEFAULT_MIN_DEBT_REQUIRED = 1_000e18;

    function setUp() public {
        vm.warp(1_000_000);

        staking = new MockStaking();

        ohm = new MockOhm("OHM", "OHM", 9);
        gohm = new MockGohm("gOHM", "gOHM", 18);
        dai = new MockERC20("dai", "DAI", 18);
        sdai = new MockERC4626(dai, "sDai", "sDAI");

        kernel = new Kernel(); // this contract will be the executor

        TRSRY = new OlympusTreasury(kernel);
        MINTR = new OlympusMinter(kernel, address(ohm));
        ROLES = new OlympusRoles(kernel);
        CHREG = new OlympusClearinghouseRegistry(kernel, address(0), new address[](0));
        DLGTE = new OlympusGovDelegation(kernel, address(gohm));

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

        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(CHREG));
        kernel.executeAction(Actions.InstallModule, address(DLGTE));

        kernel.executeAction(Actions.ActivatePolicy, address(cooler));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        /// Configure access control
        rolesAdmin.grantRole("cooler_overseer", OVERSEER);

        // Setup Treasury
        uint256 mintAmount = 200_000_000e18; // Init treasury with 200 million
        dai.mint(address(TRSRY), mintAmount);
        // Deposit all reserves into the DSR
        vm.startPrank(address(TRSRY));
        dai.approve(address(sdai), mintAmount);
        sdai.deposit(mintAmount, address(TRSRY));
        vm.stopPrank();

        // Fund others so that TRSRY is not the only account with sDAI shares
        dai.mint(OTHERS, mintAmount * 33);
        vm.startPrank(OTHERS);
        dai.approve(address(sdai), mintAmount * 33);
        sdai.deposit(mintAmount * 33, OTHERS);
        vm.stopPrank();
    }

    function checkGlobalState(
        uint128 expectedTotalDebt, 
        uint256 expectedInterestAccumulator
    ) internal {
        (uint128 totalDebt, uint256 interestAccumulatorRay) = cooler.globalState();
        assertEq(totalDebt, expectedTotalDebt, "globalState::totalDebt");
        assertEq(interestAccumulatorRay, expectedInterestAccumulator, "globalState::interestAccumulatorRay");
    }

    function addCollateral(
        address account, 
        uint128 collateralAmount
    ) internal {
        addCollateral(account, collateralAmount, new DLGTEv1.DelegationRequest[](0));
    }

    function addCollateral(
        address account, 
        uint128 collateralAmount, 
        DLGTEv1.DelegationRequest[] memory delegationRequests
    ) internal {
        gohm.mint(account, collateralAmount);
        vm.startPrank(account);
        gohm.approve(address(cooler), collateralAmount);
        cooler.addCollateral(collateralAmount, account, delegationRequests);
        vm.stopPrank();
    }

    function expectNoDelegations(address account) internal {
        DLGTEv1.AccountDelegation[] memory delegations = cooler.accountDelegationsList(account, 0, 100);
        assertEq(delegations.length, 0, "AccountDelegation::length::0");
    }

    function expectOneDelegation(
        address account,
        address expectedDelegate,
        uint256 expectedDelegationAmount
    ) internal {
        DLGTEv1.AccountDelegation[] memory delegations = cooler.accountDelegationsList(account, 0, 100);
        assertEq(delegations.length, 1, "AccountDelegation::length::1");
        assertEq(delegations[0].delegate, expectedDelegate, "AccountDelegation::delegate");
        assertEq(delegations[0].totalAmount, expectedDelegationAmount, "AccountDelegation::totalAmount");
        assertEq(gohm.balanceOf(delegations[0].escrow), expectedDelegationAmount, "AccountDelegation::escrow::gOHM::balanceOf");
    }

    function expectTwoDelegations(
        address account,
        address expectedDelegate1,
        uint256 expectedDelegationAmount1,
        address expectedDelegate2,
        uint256 expectedDelegationAmount2
    ) internal {
        DLGTEv1.AccountDelegation[] memory delegations = cooler.accountDelegationsList(account, 0, 100);
        assertEq(delegations.length, 2, "AccountDelegation::length::2");
        assertEq(delegations[0].delegate, expectedDelegate1, "AccountDelegation::delegate1");
        assertEq(delegations[0].totalAmount, expectedDelegationAmount1, "AccountDelegation::totalAmount1");
        assertEq(gohm.balanceOf(delegations[0].escrow), expectedDelegationAmount1, "AccountDelegation::escrow1::gOHM::balanceOf");
        assertEq(delegations[1].delegate, expectedDelegate2, "AccountDelegation::delegate2");
        assertEq(delegations[1].totalAmount, expectedDelegationAmount2, "AccountDelegation::totalAmount2");
        assertEq(gohm.balanceOf(delegations[1].escrow), expectedDelegationAmount2, "AccountDelegation::escrow2::gOHM::balanceOf");
    }

    function checkAccountState(
        address account,
        IMonoCooler.AccountState memory expectedAccountState
    ) internal {
        IMonoCooler.AccountState memory aState = cooler.accountState(account);
        assertEq(aState.collateral, expectedAccountState.collateral, "AccountState::collateral");
        assertEq(aState.debtCheckpoint, expectedAccountState.debtCheckpoint, "AccountState::debtCheckpoint");
        assertEq(aState.interestAccumulatorRay, expectedAccountState.interestAccumulatorRay, "AccountState::interestAccumulatorRay");
    }

    function checkAccountPosition(
        address account,
        IMonoCooler.AccountPosition memory expectedPosition
    ) internal {
        IMonoCooler.AccountPosition memory position = cooler.accountPosition(account);
        assertEq(position.collateral, expectedPosition.collateral, "AccountPosition::collateral");
        assertEq(position.currentDebt, expectedPosition.currentDebt, "AccountPosition::currentDebt");
        assertEq(position.maxDebt, expectedPosition.maxDebt, "AccountPosition::maxDebt");
        assertEq(position.healthFactor, expectedPosition.healthFactor, "AccountPosition::healthFactor");
        assertEq(position.currentLtv, expectedPosition.currentLtv, "AccountPosition::currentLtv");
        assertEq(position.totalDelegated, expectedPosition.totalDelegated, "AccountPosition::totalDelegated");
        assertEq(position.numDelegateAddresses, expectedPosition.numDelegateAddresses, "AccountPosition::numDelegateAddresses");
        assertEq(position.maxDelegateAddresses, expectedPosition.maxDelegateAddresses, "AccountPosition::maxDelegateAddresses");
    }

    function checkLiquidityStatus(
        address account,
        IMonoCooler.LiquidationStatus memory expectedLiquidationStatus
    ) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        IMonoCooler.LiquidationStatus[] memory status = cooler.computeLiquidity(accounts);
        assertEq(status.length, 1, "LiquidationStatus::length::1");
        assertEq(status[0].collateral, expectedLiquidationStatus.collateral, "LiquidationStatus::collateral");
        assertEq(status[0].currentDebt, expectedLiquidationStatus.currentDebt, "LiquidationStatus::currentDebt");
        assertEq(status[0].currentLtv, expectedLiquidationStatus.currentLtv, "LiquidationStatus::currentLtv");
        assertEq(status[0].exceededLiquidationLtv, expectedLiquidationStatus.exceededLiquidationLtv, "LiquidationStatus::exceededLiquidationLtv");
        assertEq(status[0].exceededMaxOriginationLtv, expectedLiquidationStatus.exceededMaxOriginationLtv, "LiquidationStatus::exceededMaxOriginationLtv");
    }
}