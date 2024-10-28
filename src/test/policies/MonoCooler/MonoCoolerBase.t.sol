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
        addCollateral(account, collateralAmount, new IMonoCooler.DelegationRequest[](0));
    }

    function addCollateral(
        address account, 
        uint128 collateralAmount, 
        IMonoCooler.DelegationRequest[] memory delegationRequests
    ) internal {
        gohm.mint(account, collateralAmount);
        vm.startPrank(account);
        gohm.approve(address(cooler), collateralAmount);
        cooler.addCollateral(collateralAmount, account, delegationRequests);
        vm.stopPrank();
    }
}