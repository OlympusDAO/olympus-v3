// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockStaking} from "test/mocks/MockStaking.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

//import {} from "olympus-v3/Kernel.sol";
import {RolesAdmin, Kernel, Actions, Permissions, Keycode, fromKeycode, toKeycode} from "olympus-v3/policies/RolesAdmin.sol";
import {OlympusRoles, ROLESv1} from "olympus-v3/modules/ROLES/OlympusRoles.sol";
import {OlympusMinter, MINTRv1} from "olympus-v3/modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury, TRSRYv1} from "olympus-v3/modules/TRSRY/OlympusTreasury.sol";

import {Clearinghouse, Cooler, CoolerFactory, CoolerCallback} from "policies/Clearinghouse.sol";

// Tests for Clearinghouse
/// @dev Although there is sDAI in the treasury, the sDAI will be equal to
///      DAI values everytime we convert between them. This is because no external
///      DAI is being added to the sDAI vault, so the exchange rate is 1:1. This
///      does not cause any issues with our testing.
//
// Clearinghouse Setup and Permissions.
// [X] configureDependencies
// [X] requestPermissions
//
// Clearinghouse Functions
// [X] rebalance
//     [X] can't if the contract is deactivated.
//     [X] can't rebalance faster than the funding cadence.
//     [X] Treasury approvals for the clearing house are correct.
//     [X] if necessary, sends excess DSR funds back to the Treasury.
//     [X] if a rebalances are missed, can execute several rebalances if FUND_CADENCE allows it.
// [X] sweepIntoDSR
//     [X] excess DAI is deposited into DSR.
// [X] defund
//     [X] only "cooler_overseer" can call.
//     [X] cannot defund gOHM.
//     [X] sends input ERC20 token back to the Treasury.
// [X] emergencyShutdown
//     [X] only "emergency_shutdown" can call.
//     [X] deactivates and defunds.
// [X] restartAfterShutdown
//     [X] only "cooler_overseer" can call.
//     [X] reactivates.
// [X] lendToCooler
//     [X] only lend to coolers issued by coolerFactory.
//     [X] only collateral = gOHM + only debt = DAI.
//     [x] user and cooler new gOHM balances are correct.
//     [x] user and cooler new DAI balances are correct.
// [X] rollLoan
//     [X] only roll coolers issued by coolerFactory.
//     [X] roll by adding more collateral.
//     [X] roll by paying the interest.
//     [X] user and cooler new gOHM balances are correct.
// [X] onRepay
//     [X] only coolers issued by coolerFactory can call.
//     [X] receivables are updated.
// [X] claimDefaulted
//     [X] only coolers issued by coolerFactory can call.
//     [X] receivables are updated.
//     [X] OHM supply is properly burnt.

contract BaseTest is Test {
    MockOhm internal ohm;
    MockERC20 internal gohm;
    MockERC20 internal dai;
    MockERC4626 internal sdai;

    Kernel public kernel;
    OlympusRoles internal ROLES;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;
    RolesAdmin internal rolesAdmin;
    Clearinghouse internal clearinghouse;
    CoolerFactory internal factory;
    Cooler internal testCooler;

    address internal user;
    address internal others;
    address internal overseer;
    uint256 internal initialSDai;

    function setUp() public {
        address[] memory users = (new UserFactory()).create(3);
        user = users[0];
        others = users[1];
        overseer = users[2];

        MockStaking staking = new MockStaking();
        factory = new CoolerFactory();

        ohm = new MockOhm("olympus", "OHM", 9);
        gohm = new MockERC20("olympus", "gOHM", 18);
        dai = new MockERC20("dai", "DAI", 18);
        sdai = new MockERC4626(dai, "sDai", "sDAI");

        kernel = new Kernel(); // this contract will be the executor

        TRSRY = new OlympusTreasury(kernel);
        MINTR = new OlympusMinter(kernel, address(ohm));
        ROLES = new OlympusRoles(kernel);

        clearinghouse = new Clearinghouse(
            address(gohm),
            address(staking),
            address(sdai),
            address(factory),
            address(kernel)
        );
        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        kernel.executeAction(Actions.ActivatePolicy, address(clearinghouse));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        /// Configure access control
        rolesAdmin.grantRole("cooler_overseer", overseer);
        rolesAdmin.grantRole("emergency_shutdown", overseer);

        // Setup clearinghouse initial conditions
        uint mintAmount = 200_000_000e18; // Init treasury with 200 million
        dai.mint(address(TRSRY), mintAmount);
        // Deposit all reserves into the DSR
        vm.startPrank(address(TRSRY));
        dai.approve(address(sdai), mintAmount);
        sdai.deposit(mintAmount, address(TRSRY));
        vm.stopPrank();

        // Initial rebalance to fund the clearinghouse
        clearinghouse.rebalance();

        testCooler = Cooler(factory.generateCooler(gohm, dai));

        // Skip 1 week ahead to allow rebalances
        skip(1 weeks);

        // Initial funding of clearinghouse is equal to FUND_AMOUNT
        assertEq(sdai.maxWithdraw(address(clearinghouse)), clearinghouse.FUND_AMOUNT());

        // Fund others so that TRSRY is not the only with sDAI shares
        dai.mint(others, mintAmount * 33);
        vm.startPrank(others);
        dai.approve(address(sdai), mintAmount * 33);
        sdai.deposit(mintAmount * 33, others);
        vm.stopPrank();
    }

    // --- HELPER FUNCTIONS ----------------------------------------------

    function _fundUser(uint256 gohmAmount_) internal {
        // Mint gOHM
        gohm.mint(user, gohmAmount_);
        // Approve clearinghouse
        vm.prank(user);
        gohm.approve(address(clearinghouse), gohmAmount_);
    }

    function _createLoanForUser(
        uint256 loanAmount_
    ) internal returns (Cooler cooler, uint256 gohmNeeded, uint256 loanID) {
        // Create the Cooler
        vm.prank(user);
        cooler = Cooler(factory.generateCooler(gohm, dai));

        // Ensure user has enough collateral
        gohmNeeded = cooler.collateralFor(loanAmount_, clearinghouse.LOAN_TO_COLLATERAL());
        _fundUser(gohmNeeded);

        vm.prank(user);
        loanID = clearinghouse.lendToCooler(cooler, loanAmount_);
    }

    function _skip(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
        if (block.timestamp >= clearinghouse.fundTime()) {
            clearinghouse.rebalance();
        }
    }
}

// -----------------------------------------------------------------------
// --- UNIT TESTS --------------------------------------------------------
// -----------------------------------------------------------------------

contract ClearinghouseTest is BaseTest {
    // --- SETUP, DEPENDENCIES, AND PERMISSIONS --------------------------

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](3);
        expectedDeps[0] = toKeycode("TRSRY");
        expectedDeps[1] = toKeycode("MINTR");
        expectedDeps[2] = toKeycode("ROLES");

        Keycode[] memory deps = clearinghouse.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](4);
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        expectedPerms[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        expectedPerms[2] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        expectedPerms[3] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);

        Permissions[] memory perms = clearinghouse.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // --- LEND TO COOLER ------------------------------------------------

    function testRevert_lendToCooler_NotFromFactory() public {
        CoolerFactory maliciousFactory = new CoolerFactory();
        Cooler maliciousCooler = Cooler(maliciousFactory.generateCooler(gohm, dai));
        // Coolers not created by the CoolerFactory could be malicious.
        vm.prank(address(maliciousCooler));
        vm.expectRevert(CoolerCallback.OnlyFromFactory.selector);
        clearinghouse.lendToCooler(maliciousCooler, 1e18);
    }

    function testRevert_lendToCooler_NotGohmDai() public {
        MockERC20 wagmi = new MockERC20("wagmi", "WAGMI", 18);
        MockERC20 ngmi = new MockERC20("ngmi", "NGMI", 18);

        // Clearinghouse only accepts gOHM-DAI
        Cooler badCooler1 = Cooler(factory.generateCooler(wagmi, ngmi));
        vm.expectRevert(Clearinghouse.BadEscrow.selector);
        clearinghouse.lendToCooler(badCooler1, 1e18);
        // Clearinghouse only accepts gOHM-DAI
        Cooler badCooler2 = Cooler(factory.generateCooler(gohm, ngmi));
        vm.expectRevert(Clearinghouse.BadEscrow.selector);
        clearinghouse.lendToCooler(badCooler2, 1e18);
        // Clearinghouse only accepts gOHM-DAI
        Cooler badCooler3 = Cooler(factory.generateCooler(wagmi, dai));
        vm.expectRevert(Clearinghouse.BadEscrow.selector);
        clearinghouse.lendToCooler(badCooler3, 1e18);
    }

    function test_lendToCooler() public {
        // Setup: Assume 1M DAI loan.
        uint256 loanAmount = 1e24;

        (Cooler cooler, uint256 gohmNeeded, uint256 loanID) = _createLoanForUser(loanAmount);

        // Check: balances
        assertEq(gohm.balanceOf(address(cooler)), gohmNeeded);
        assertEq(dai.balanceOf(address(user)), loanAmount);
        assertEq(dai.balanceOf(address(cooler)), 0);
        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), clearinghouse.debtForCollateral(gohmNeeded));
        assertApproxEqAbs(clearinghouse.receivables(), cooler.getLoan(loanID).amount, 1e4);
    }

    // --- ROLL LOAN -----------------------------------------------------

    function test_rollLoan_pledgingExtraCollateral() public {
        // Setup: Assume 1M DAI loan.
        uint256 loanAmount = 1e24;

        (Cooler cooler, uint256 gohmNeeded, uint256 loanID) = _createLoanForUser(loanAmount);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward to half duration of the loan
        _skip(clearinghouse.DURATION() / 2);

        // Cache DAI balance and extra interest to be paid
        uint256 initDaiUser = dai.balanceOf(user);
        uint256 initReceivables = clearinghouse.receivables();
        uint256 interestExtra = cooler.interestFor(
            initLoan.amount,
            clearinghouse.INTEREST_RATE(),
            clearinghouse.DURATION()
        );
        // Ensure user has enough collateral to roll the loan
        uint256 gohmExtra = cooler.newCollateralFor(loanID);
        _fundUser(gohmExtra);
        // Roll loan
        vm.prank(user);
        clearinghouse.rollLoan(cooler, loanID);

        Cooler.Loan memory newLoan = cooler.getLoan(loanID);

        // Check: balances
        assertEq(gohm.balanceOf(address(cooler)), gohmNeeded + gohmExtra);
        assertEq(dai.balanceOf(user), initDaiUser);
        // Check: cooler storage
        assertEq(newLoan.amount, initLoan.amount + interestExtra);
        assertEq(newLoan.unclaimed, initLoan.unclaimed);
        assertEq(newLoan.collateral, initLoan.collateral + gohmExtra);
        assertEq(newLoan.expiry, initLoan.expiry + initLoan.request.duration);
        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), initReceivables + interestExtra);
    }

    function test_rollLoan_repayingInterest() public {
        // Setup: Assume 1M DAI loan.
        uint256 loanAmount = 1e24;

        (Cooler cooler, uint256 gohmNeeded, uint256 loanID) = _createLoanForUser(loanAmount);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward to half duration of the loan
        _skip(clearinghouse.DURATION() / 2);

        vm.startPrank(user);
        // Cache DAI balance and extra interest to be paid in the future
        uint256 initDaiUser = dai.balanceOf(user);
        uint256 initReceivables = clearinghouse.receivables();
        // Repay the interest of the loan (interest = owed debt - borrowed amount)
        uint256 repay = initLoan.amount - initLoan.request.amount;
        dai.approve(address(cooler), repay);
        uint256 decollateralized = cooler.repayLoan(loanID, repay);
        // Roll loan
        gohm.approve(address(clearinghouse), decollateralized);
        clearinghouse.rollLoan(cooler, loanID);
        vm.stopPrank();

        Cooler.Loan memory newLoan = cooler.getLoan(loanID);

        // Check: balances
        assertEq(gohm.balanceOf(address(cooler)), gohmNeeded);
        assertEq(dai.balanceOf(user), initDaiUser - repay);
        // Check: cooler storage
        assertEq(newLoan.amount, initLoan.amount);
        assertEq(newLoan.unclaimed, initLoan.unclaimed);
        assertEq(newLoan.collateral, initLoan.collateral);
        assertEq(newLoan.expiry, initLoan.expiry + initLoan.request.duration);
        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), initReceivables);
    }

    function testRevert_rollLoan_NotFromFactory() public {
        CoolerFactory maliciousFactory = new CoolerFactory();
        Cooler maliciousCooler = Cooler(maliciousFactory.generateCooler(gohm, dai));

        // Coolers not created by the CoolerFactory could be malicious.
        vm.prank(others);
        vm.expectRevert(CoolerCallback.OnlyFromFactory.selector);
        clearinghouse.rollLoan(maliciousCooler, 0);
    }

    // --- REBALANCE TREASURY --------------------------------------------

    function test_rebalance_pullFunds() public {
        uint256 oneMillion = 1e24;
        uint256 sdaiOneMillion = sdai.previewWithdraw(1e24);
        uint256 daiInitCH = sdai.maxWithdraw(address(clearinghouse));
        uint256 sdaiInitCH = sdai.balanceOf(address(clearinghouse));

        // Burn 1 mil from clearinghouse to simulate assets being lent
        vm.prank(address(clearinghouse));
        sdai.withdraw(oneMillion, address(0x0), address(clearinghouse));

        assertEq(
            sdai.maxWithdraw(address(clearinghouse)),
            daiInitCH - oneMillion,
            "init DAI balance CH"
        );
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            sdaiInitCH - sdaiOneMillion,
            "init sDAI balance CH"
        );
        assertEq(
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            clearinghouse.FUND_AMOUNT(),
            "init DAI debt CH"
        );
        // Test if clearinghouse pulls in 1 mil DAI from treasury
        uint256 daiInitTRSRY = sdai.maxWithdraw(address(TRSRY));
        uint256 sdaiInitTRSRY = sdai.balanceOf(address(TRSRY));

        clearinghouse.rebalance();

        assertEq(daiInitTRSRY - oneMillion, sdai.maxWithdraw(address(TRSRY)), "DAI balance TRSRY");
        assertEq(
            sdaiInitTRSRY - sdaiOneMillion,
            sdai.balanceOf(address(TRSRY)),
            "sDAI balance TRSRY"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT(),
            sdai.maxWithdraw(address(clearinghouse)),
            "FUND_AMOUNT"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT() + oneMillion,
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            "DAI debt CH"
        );
    }

    function test_rebalance_returnFunds() public {
        uint256 oneMillion = 1e24;
        uint256 sdaiOneMillion = sdai.previewWithdraw(1e24);
        uint256 daiInitCH = sdai.maxWithdraw(address(clearinghouse));
        uint256 sdaiInitCH = sdai.balanceOf(address(clearinghouse));

        // Mint 1 million to clearinghouse and sweep to simulate assets being repaid
        dai.mint(address(clearinghouse), oneMillion);
        clearinghouse.sweepIntoDSR();

        assertEq(
            sdai.maxWithdraw(address(clearinghouse)),
            daiInitCH + oneMillion,
            "init DAI balance CH"
        );
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            sdaiInitCH + sdaiOneMillion,
            "init sDAI balance CH"
        );
        assertEq(
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            clearinghouse.FUND_AMOUNT(),
            "init DAI debt CH"
        );

        uint256 daiInitTRSRY = sdai.maxWithdraw(address(TRSRY));
        uint256 sdaiInitTRSRY = sdai.balanceOf(address(TRSRY));

        clearinghouse.rebalance();

        assertEq(daiInitTRSRY + oneMillion, sdai.maxWithdraw(address(TRSRY)), "DAI balance TRSRY");
        assertEq(
            sdaiInitTRSRY + sdaiOneMillion,
            sdai.balanceOf(address(TRSRY)),
            "sDAI balance TRSRY"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT(),
            sdai.maxWithdraw(address(clearinghouse)),
            "FUND_AMOUNT"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT() - oneMillion,
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            "DAI debt CH"
        );
    }

    function test_rebalance_deactivated_returnFunds() public {
        vm.prank(overseer);
        clearinghouse.emergencyShutdown();

        // Simulate loan repayments
        uint256 oneMillion = 1e24;
        deal(address(sdai), address(clearinghouse), oneMillion);
        uint256 sdaiInitTRSRY = sdai.balanceOf(address(TRSRY));
        // Rebalances only defund when the contract is deactivated.
        clearinghouse.rebalance();
        assertEq(sdai.balanceOf(address(clearinghouse)), 0);
        assertEq(sdai.balanceOf(address(TRSRY)), sdaiInitTRSRY + oneMillion);
    }

    function test_rebalance_pullFunds_withSmallTRSRY() public {
        uint256 oneMillion = 1e24;
        uint256 sdaiOneMillion = sdai.previewWithdraw(1e24);
        uint256 daiInitCH = sdai.maxWithdraw(address(clearinghouse));
        uint256 sdaiInitCH = sdai.balanceOf(address(clearinghouse));

        // Set TRSRY funds to 0.5M sDAI
        deal(address(sdai), address(TRSRY), oneMillion / 2);

        // Burn 1 mil from clearinghouse to simulate assets being lent
        vm.prank(address(clearinghouse));
        sdai.withdraw(oneMillion, address(0x0), address(clearinghouse));

        assertEq(
            sdai.maxWithdraw(address(clearinghouse)),
            daiInitCH - oneMillion,
            "init DAI balance CH"
        );
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            sdaiInitCH - sdaiOneMillion,
            "init sDAI balance CH"
        );
        assertEq(
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            clearinghouse.FUND_AMOUNT(),
            "init DAI debt CH"
        );

        // Test if clearinghouse pulls in remainding treasury funds
        uint256 sdaiInitTRSRY = sdai.balanceOf(address(TRSRY));

        clearinghouse.rebalance();

        assertEq(0, sdai.maxWithdraw(address(TRSRY)), "DAI balance TRSRY");
        assertEq(0, sdai.balanceOf(address(TRSRY)), "sDAI balance TRSRY");
        assertEq(
            daiInitCH - oneMillion + sdai.previewWithdraw(sdaiInitTRSRY),
            sdai.maxWithdraw(address(clearinghouse)),
            "FUND_AMOUNT"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT() + sdai.previewWithdraw(sdaiInitTRSRY),
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            "DAI debt CH"
        );
    }

    function testRevert_rebalance_early() public {
        bool canRebalance;
        // Rebalance to be up-to-date with the FUND_CADENCE.
        canRebalance = clearinghouse.rebalance();
        assertEq(canRebalance, true);
        // Second rebalance is ahead of time, and will not happen.
        canRebalance = clearinghouse.rebalance();
        assertEq(canRebalance, false);
    }

    // Should be able to rebalance multiple times if past due
    function test_rebalance_pastDue() public {
        // Already skipped 1 week ahead in setup. Do once more and call rebalance twice.
        skip(2 weeks);
        for (uint i; i < 3; i++) {
            clearinghouse.rebalance();
        }
    }

    // --- SWEEP INTO DSR ------------------------------------------------

    function test_sweepIntoDSR() public {
        uint256 sdaiBal = sdai.balanceOf(address(clearinghouse));

        // Mint 1 million to clearinghouse and sweep to simulate assets being repaid
        dai.mint(address(clearinghouse), 1e24);
        clearinghouse.sweepIntoDSR();

        assertEq(sdai.balanceOf(address(clearinghouse)), sdaiBal + 1e24);
    }

    // --- DEFUND CLEARINGHOUSE ------------------------------------------

    function test_defund() public {
        uint256 sdaiTrsryBal = sdai.balanceOf(address(TRSRY));
        uint256 initDebtCH = TRSRY.reserveDebt(dai, address(clearinghouse));

        vm.prank(overseer);
        clearinghouse.defund(sdai, 1e24);
        assertEq(sdai.balanceOf(address(TRSRY)), sdaiTrsryBal + 1e24);
        assertEq(
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            initDebtCH - sdai.previewRedeem(1e24)
        );
    }

    function testRevert_defund_gohm() public {
        vm.prank(overseer);
        vm.expectRevert(Clearinghouse.OnlyBurnable.selector);
        clearinghouse.defund(gohm, 1e24);
    }

    function testRevert_defund_onlyRole() public {
        vm.prank(others);
        vm.expectRevert();
        clearinghouse.defund(gohm, 1e24);
    }

    // --- EMERGENCY SHUTDOWN CLEARINGHOUSE ------------------------------

    function test_emergencyShutdown() public {
        uint256 sdaiTrsryBal = sdai.balanceOf(address(TRSRY));
        uint256 sdaiCHBal = sdai.balanceOf(address(clearinghouse));

        vm.prank(overseer);
        clearinghouse.emergencyShutdown();
        assertEq(clearinghouse.active(), false);
        assertEq(sdai.balanceOf(address(TRSRY)), sdaiTrsryBal + sdaiCHBal);
    }

    function testRevert_emergencyShutdown_onlyRole() public {
        vm.prank(others);
        vm.expectRevert();
        clearinghouse.emergencyShutdown();
    }

    function test_reactivate() public {
        vm.startPrank(overseer);
        clearinghouse.emergencyShutdown();
        assertEq(clearinghouse.active(), false);
        clearinghouse.reactivate();
        assertEq(clearinghouse.active(), true);
        vm.stopPrank();
    }

    function testRevert_restartAfterShutdown_onlyRole() public {
        vm.prank(others);
        vm.expectRevert();
        clearinghouse.reactivate();
    }

    // --- CALLBACKS: ON LOAN REPAYMENT ----------------------------------

    function test_onRepay() public {
        // Setup: Assume 1M DAI loan.
        uint256 loanAmount = 1e24;

        (Cooler cooler, , uint256 loanID) = _createLoanForUser(loanAmount);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward to half duration of the loan
        _skip(clearinghouse.DURATION() / 2);

        vm.startPrank(user);
        // Cache clearinghouse receivables
        uint256 initReceivables = clearinghouse.receivables();
        // Repay the interest of the loan (interest = owed debt - borrowed amount)
        uint256 repay = initLoan.amount - initLoan.request.amount;
        dai.approve(address(cooler), repay);
        cooler.repayLoan(loanID, repay);

        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), initReceivables - repay);
        assertApproxEqAbs(clearinghouse.receivables(), cooler.getLoan(loanID).amount, 1e4);
    }

    function testRevert_onRepay_notFromFactory() public {
        CoolerFactory maliciousFactory = new CoolerFactory();
        Cooler maliciousCooler = Cooler(maliciousFactory.generateCooler(gohm, dai));
        // Coolers not created by the CoolerFactory could be malicious.
        vm.prank(address(maliciousCooler));
        vm.expectRevert(CoolerCallback.OnlyFromFactory.selector);
        clearinghouse.onRepay(0, 1e18);
    }

    // --- CLAIM DEFAULTED ----------------------------------

    function test_claimDefaulted() public {
        // Setup: Assume 1M and 3M DAI loans.
        uint256 loanAmount1 = 1e24;
        uint256 loanAmount2 = 3e24;
        uint256 elapsedTime = 1 days;

        (Cooler cooler1, uint256 gohmNeeded1, uint256 loanID1) = _createLoanForUser(loanAmount1);
        (Cooler cooler2, uint256 gohmNeeded2, uint256 loanID2) = _createLoanForUser(loanAmount2);
        Cooler.Loan memory initLoan1 = cooler1.getLoan(loanID1);
        Cooler.Loan memory initLoan2 = cooler2.getLoan(loanID2);

        // Move forward after both loans have ended
        _skip(clearinghouse.DURATION() + elapsedTime);

        {
            // Cache clearinghouse receivables and TRSRY debt
            uint256 initReceivables = clearinghouse.receivables();
            uint256 initDebt = TRSRY.reserveDebt(sdai, address(clearinghouse));

            // Simulate unstaking outcome after defaults
            ohm.mint(address(clearinghouse), gohmNeeded1 + gohmNeeded2);
            {
                uint256[] memory ids = new uint256[](2);
                address[] memory coolers = new address[](2);
                ids[0] = loanID1;
                ids[1] = loanID2;
                coolers[0] = address(cooler1);
                coolers[1] = address(cooler2);

                deal(address(gohm), others, 0);
                // Claim defaulted loans
                vm.prank(others);
                clearinghouse.claimDefaulted(coolers, ids);
            }
            {
                uint256 daiReceivables = initLoan1.amount + initLoan2.amount;
                uint256 sdaiDebt = sdai.previewDeposit(
                    daiReceivables - clearinghouse.interestFromDebt(daiReceivables)
                );
                // Check: clearinghouse storage
                assertEq(
                    clearinghouse.receivables(),
                    initReceivables > daiReceivables ? initReceivables - daiReceivables : 0
                );
                // Check: TRSRY storage
                assertApproxEqAbs(
                    TRSRY.reserveDebt(sdai, address(clearinghouse)),
                    initDebt > sdaiDebt ? initDebt - sdaiDebt : 0,
                    1e4
                );
            }
        }
        {
            uint256 keeperRewards = gohm.balanceOf(others);
            // After defaults the clearing house keeps the collateral (which is supposed to be unstaked and burned)
            assertEq(
                gohm.balanceOf(address(clearinghouse)),
                gohmNeeded1 + gohmNeeded2 - keeperRewards,
                "gOHM balance"
            );
            // Check: OHM supply = keeper rewards (only minted before burning)
            assertEq(ohm.totalSupply(), keeperRewards, "OHM supply");

            {
                uint256 maxAuctionReward1 = (gohmNeeded1 * 5e16) / 1e18;
                uint256 maxAuctionReward2 = (gohmNeeded2 * 5e16) / 1e18;
                uint256 maxRewards = (maxAuctionReward1 < clearinghouse.MAX_REWARD())
                    ? maxAuctionReward1
                    : clearinghouse.MAX_REWARD();
                maxRewards = (maxAuctionReward2 < clearinghouse.MAX_REWARD())
                    ? maxRewards + maxAuctionReward2
                    : maxRewards + clearinghouse.MAX_REWARD();
                // Check: keeper rewards can't exceed 5% of defaulted collateral
                if (elapsedTime >= 7 days) {
                    assertApproxEqAbs(
                        keeperRewards,
                        maxRewards,
                        1e4,
                        "rewards <= 5% collat && MAX_REWARD"
                    );
                } else {
                    assertApproxEqAbs(
                        keeperRewards,
                        (maxRewards * elapsedTime) / 7 days,
                        1e4,
                        "rewards <= auction"
                    );
                }
            }
        }
    }

    function testRevert_claimDefaulted_inputLengthDiscrepancy() public {
        uint256[] memory ids = new uint256[](2);
        address[] memory coolers = new address[](1);
        ids[0] = 12345;
        ids[1] = 67890;
        coolers[0] = others;

        vm.prank(overseer);
        // Both input arrays must have the same length
        vm.expectRevert(Clearinghouse.LengthDiscrepancy.selector);
        clearinghouse.claimDefaulted(coolers, ids);
    }

    function testRevert_claimDefaulted_NotFromFactory() public {
        CoolerFactory maliciousFactory = new CoolerFactory();
        Cooler maliciousCooler = Cooler(maliciousFactory.generateCooler(gohm, dai));

        uint256[] memory ids = new uint256[](1);
        address[] memory coolers = new address[](1);
        ids[0] = 12345;
        coolers[0] = address(maliciousCooler);

        // Coolers not created by the CoolerFactory could be malicious.
        vm.prank(others);
        vm.expectRevert(CoolerCallback.OnlyFromFactory.selector);
        clearinghouse.claimDefaulted(coolers, ids);
    }
}

// -----------------------------------------------------------------------
// --- FUZZ TESTS --------------------------------------------------------
// -----------------------------------------------------------------------

contract ClearinghouseFuzzTest is BaseTest {
    // --- LEND TO COOLER ------------------------------------------------
    function testFuzz_lendToCooler(uint256 loanAmount_) public {
        // Loan amount cannot exceed Clearinghouse funding
        loanAmount_ = bound(loanAmount_, 0, clearinghouse.FUND_AMOUNT());

        (Cooler cooler, uint256 gohmNeeded, uint256 loanID) = _createLoanForUser(loanAmount_);

        // Check: balances
        assertEq(gohm.balanceOf(address(cooler)), gohmNeeded);
        assertEq(dai.balanceOf(address(user)), loanAmount_);
        assertEq(dai.balanceOf(address(cooler)), 0);
        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), clearinghouse.debtForCollateral(gohmNeeded));
        assertApproxEqAbs(clearinghouse.receivables(), cooler.getLoan(loanID).amount, 1e4);
    }

    // --- ROLL LOAN -----------------------------------------------------

    function testFuzz_rollLoan_pledgingExtraCollateral(uint256 loanAmount_) public {
        // Loan amount cannot exceed Clearinghouse funding
        loanAmount_ = bound(loanAmount_, 0, clearinghouse.FUND_AMOUNT());

        (Cooler cooler, uint256 gohmNeeded, uint256 loanID) = _createLoanForUser(loanAmount_);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward to half duration of the loan
        _skip(clearinghouse.DURATION() / 2);

        // Cache DAI balance and extra interest to be paid
        uint256 initDaiUser = dai.balanceOf(user);
        uint256 initReceivables = clearinghouse.receivables();
        uint256 interestExtra = cooler.interestFor(
            initLoan.amount,
            clearinghouse.INTEREST_RATE(),
            clearinghouse.DURATION()
        );
        // Ensure user has enough collateral to roll the loan
        uint256 gohmExtra = cooler.newCollateralFor(loanID);
        _fundUser(gohmExtra);
        // Roll loan
        vm.prank(user);
        clearinghouse.rollLoan(cooler, loanID);

        Cooler.Loan memory newLoan = cooler.getLoan(loanID);

        // Check: balances
        assertEq(gohm.balanceOf(address(cooler)), gohmNeeded + gohmExtra);
        assertEq(dai.balanceOf(user), initDaiUser);
        // Check: cooler storage
        assertEq(newLoan.amount, initLoan.amount + interestExtra);
        assertEq(newLoan.unclaimed, initLoan.unclaimed);
        assertEq(newLoan.collateral, initLoan.collateral + gohmExtra);
        assertEq(newLoan.expiry, initLoan.expiry + initLoan.request.duration);
        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), initReceivables + interestExtra);
    }

    function testFuzz_rollLoan_repayingInterest(uint256 loanAmount_) public {
        // Loan amount cannot exceed Clearinghouse funding
        // Loan amount must exceed 0.0001 gOHM, so that repaying the interest decollaterizes de loan.
        loanAmount_ = bound(loanAmount_, 1e14, clearinghouse.FUND_AMOUNT());

        (Cooler cooler, uint256 gohmNeeded, uint256 loanID) = _createLoanForUser(loanAmount_);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward to half duration of the loan
        _skip(clearinghouse.DURATION() / 2);

        vm.startPrank(user);
        // Cache DAI balance and extra interest to be paid in the future
        uint256 initDaiUser = dai.balanceOf(user);
        uint256 initReceivables = clearinghouse.receivables();
        // Repay the interest of the loan (interest = owed debt - borrowed amount)
        uint256 repay = initLoan.amount - initLoan.request.amount;
        dai.approve(address(cooler), repay);
        uint256 decollateralized = cooler.repayLoan(loanID, repay);
        // Roll loan
        gohm.approve(address(clearinghouse), decollateralized);
        clearinghouse.rollLoan(cooler, loanID);
        vm.stopPrank();

        Cooler.Loan memory newLoan = cooler.getLoan(loanID);

        // Check: balances
        assertEq(gohm.balanceOf(address(cooler)), gohmNeeded);
        assertEq(dai.balanceOf(user), initDaiUser - repay);
        // Check: cooler storage
        assertEq(newLoan.amount, initLoan.amount);
        assertEq(newLoan.unclaimed, initLoan.unclaimed);
        assertEq(newLoan.collateral, initLoan.collateral);
        assertEq(newLoan.expiry, initLoan.expiry + initLoan.request.duration);
        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), initReceivables);
    }

    // --- REBALANCE TREASURY --------------------------------------------

    function testFuzz_rebalance_pullFunds(uint256 daiLent_) public {
        // Newly lent assets cannot exceed Clearinghouse funding
        daiLent_ = bound(daiLent_, 0, clearinghouse.FUND_AMOUNT());
        uint256 sdaiLentEquivalent = sdai.previewWithdraw(daiLent_);
        uint256 daiInitCH = sdai.maxWithdraw(address(clearinghouse));
        uint256 sdaiInitCH = sdai.balanceOf(address(clearinghouse));

        // Burn from clearinghouse to simulate assets being lent
        vm.prank(address(clearinghouse));
        sdai.withdraw(daiLent_, address(0x0), address(clearinghouse));

        assertEq(
            sdai.maxWithdraw(address(clearinghouse)),
            daiInitCH - daiLent_,
            "init DAI balance CH"
        );
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            sdaiInitCH - sdaiLentEquivalent,
            "init sDAI balance CH"
        );
        assertEq(
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            clearinghouse.FUND_AMOUNT(),
            "init DAI debt CH"
        );
        // Test if clearinghouse pulls in DAI from treasury
        uint256 daiInitTRSRY = sdai.maxWithdraw(address(TRSRY));
        uint256 sdaiInitTRSRY = sdai.balanceOf(address(TRSRY));

        clearinghouse.rebalance();

        assertEq(daiInitTRSRY - daiLent_, sdai.maxWithdraw(address(TRSRY)), "DAI balance TRSRY");
        assertEq(
            sdaiInitTRSRY - sdaiLentEquivalent,
            sdai.balanceOf(address(TRSRY)),
            "sDAI balance TRSRY"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT(),
            sdai.maxWithdraw(address(clearinghouse)),
            "FUND_AMOUNT"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT() + daiLent_,
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            "DAI debt CH"
        );
    }

    function testFuzz_rebalance_returnFunds(uint256 daiLent_) public {
        // Newly lent assets cannot exceed Clearinghouse funding
        // Lent must be greater than zero to simulate repayments
        daiLent_ = bound(daiLent_, 1e14, clearinghouse.FUND_AMOUNT());
        uint256 sdaiLentEquivalent = sdai.previewWithdraw(daiLent_);
        uint256 daiInitCH = sdai.maxWithdraw(address(clearinghouse));
        uint256 sdaiInitCH = sdai.balanceOf(address(clearinghouse));

        // Mint DAI to clearinghouse and sweep to simulate assets being repaid
        dai.mint(address(clearinghouse), daiLent_);
        clearinghouse.sweepIntoDSR();

        assertEq(
            sdai.maxWithdraw(address(clearinghouse)),
            daiInitCH + daiLent_,
            "init DAI balance CH"
        );
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            sdaiInitCH + sdaiLentEquivalent,
            "init sDAI balance CH"
        );
        assertEq(
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            clearinghouse.FUND_AMOUNT(),
            "init DAI debt CH"
        );

        uint256 daiInitTRSRY = sdai.maxWithdraw(address(TRSRY));
        uint256 sdaiInitTRSRY = sdai.balanceOf(address(TRSRY));

        clearinghouse.rebalance();

        assertEq(daiInitTRSRY + daiLent_, sdai.maxWithdraw(address(TRSRY)), "DAI balance TRSRY");
        assertEq(
            sdaiInitTRSRY + sdaiLentEquivalent,
            sdai.balanceOf(address(TRSRY)),
            "sDAI balance TRSRY"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT(),
            sdai.maxWithdraw(address(clearinghouse)),
            "FUND_AMOUNT"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT() - daiLent_,
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            "DAI debt CH"
        );
    }

    function testFuzz_rebalance_pullFunds_withSmallTRSRY(
        uint256 daiLent_,
        uint256 sdaiTRSRY_
    ) public {
        // Newly lent assets cannot exceed Clearinghouse funding
        daiLent_ = bound(daiLent_, 0, clearinghouse.FUND_AMOUNT());
        // sDAI in TRSRY must be lower than the lent assets
        sdaiTRSRY_ = bound(sdaiTRSRY_, 0, daiLent_);
        uint256 sdaiLentEquivalent = sdai.previewWithdraw(daiLent_);
        uint256 daiInitCH = sdai.maxWithdraw(address(clearinghouse));
        uint256 sdaiInitCH = sdai.balanceOf(address(clearinghouse));

        // Set TRSRY funds to 0.5M sDAI
        deal(address(sdai), address(TRSRY), sdaiTRSRY_);

        // Burn sDAI from clearinghouse to simulate assets being lent
        vm.prank(address(clearinghouse));
        sdai.withdraw(daiLent_, address(0x0), address(clearinghouse));

        assertEq(
            sdai.maxWithdraw(address(clearinghouse)),
            daiInitCH - daiLent_,
            "init DAI balance CH"
        );
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            sdaiInitCH - sdaiLentEquivalent,
            "init sDAI balance CH"
        );
        assertEq(
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            clearinghouse.FUND_AMOUNT(),
            "init DAI debt CH"
        );

        // Test if clearinghouse pulls in remainding treasury funds
        clearinghouse.rebalance();

        assertEq(0, sdai.maxWithdraw(address(TRSRY)), "DAI balance TRSRY");
        assertEq(0, sdai.balanceOf(address(TRSRY)), "sDAI balance TRSRY");
        assertEq(
            daiInitCH - daiLent_ + sdai.previewWithdraw(sdaiTRSRY_),
            sdai.maxWithdraw(address(clearinghouse)),
            "FUND_AMOUNT"
        );
        assertEq(
            clearinghouse.FUND_AMOUNT() + sdai.previewWithdraw(sdaiTRSRY_),
            TRSRY.reserveDebt(dai, address(clearinghouse)),
            "DAI debt CH"
        );
    }

    // --- CALLBACKS: ON LOAN REPAYMENT ----------------------------------

    function testFuzz_onRepay(uint256 loanAmount_) public {
        // Loan amount cannot exceed Clearinghouse funding
        // Loan amount must exceed 0.0001 gOHM, so that repaying the interest decollaterizes de loan.
        loanAmount_ = bound(loanAmount_, 1e14, clearinghouse.FUND_AMOUNT());

        (Cooler cooler, , uint256 loanID) = _createLoanForUser(loanAmount_);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward to half duration of the loan
        _skip(clearinghouse.DURATION() / 2);

        vm.startPrank(user);
        // Cache clearinghouse receivables
        uint256 initReceivables = clearinghouse.receivables();
        // Repay the interest of the loan (interest = owed debt - borrowed amount)
        uint256 repay = initLoan.amount - initLoan.request.amount;
        dai.approve(address(cooler), repay);
        cooler.repayLoan(loanID, repay);

        // Check: clearinghouse storage
        assertEq(clearinghouse.receivables(), initReceivables - repay);
        assertApproxEqAbs(clearinghouse.receivables(), cooler.getLoan(loanID).amount, 1e4);
    }

    // --- CLAIM DEFAULTED ----------------------------------

    function testFuzz_claimDefaulted(uint256 loanAmount_, uint256 elapsedTime_) public {
        // Loan amount cannot exceed Clearinghouse funding
        // Loan amount must exceed 0.0001 gOHM, so that repaying the interest decollaterizes de loan.
        loanAmount_ = bound(loanAmount_, 1e14, clearinghouse.FUND_AMOUNT() / 3);
        elapsedTime_ = bound(elapsedTime_, 1, 2 ** 32);

        (Cooler cooler1, uint256 gohmNeeded1, uint256 loanID1) = _createLoanForUser(loanAmount_);
        (Cooler cooler2, uint256 gohmNeeded2, uint256 loanID2) = _createLoanForUser(
            loanAmount_ * 2
        );
        Cooler.Loan memory initLoan1 = cooler1.getLoan(loanID1);
        Cooler.Loan memory initLoan2 = cooler2.getLoan(loanID2);

        // Move forward after both loans have ended
        _skip(clearinghouse.DURATION() + elapsedTime_);

        {
            // Cache clearinghouse receivables and TRSRY debt
            uint256 initReceivables = clearinghouse.receivables();
            uint256 initDebt = TRSRY.reserveDebt(sdai, address(clearinghouse));

            // Simulate unstaking outcome after defaults
            ohm.mint(address(clearinghouse), gohmNeeded1 + gohmNeeded2);
            {
                uint256[] memory ids = new uint256[](2);
                address[] memory coolers = new address[](2);
                ids[0] = loanID1;
                ids[1] = loanID2;
                coolers[0] = address(cooler1);
                coolers[1] = address(cooler2);

                deal(address(gohm), others, 0);
                // Claim defaulted loans
                vm.prank(others);
                clearinghouse.claimDefaulted(coolers, ids);
            }
            {
                uint256 daiReceivables = initLoan1.amount + initLoan2.amount;
                uint256 sdaiDebt = sdai.previewDeposit(
                    daiReceivables - clearinghouse.interestFromDebt(daiReceivables)
                );
                // Check: clearinghouse storage
                assertEq(
                    clearinghouse.receivables(),
                    initReceivables > daiReceivables ? initReceivables - daiReceivables : 0
                );
                // Check: TRSRY storage
                assertApproxEqAbs(
                    TRSRY.reserveDebt(sdai, address(clearinghouse)),
                    initDebt > sdaiDebt ? initDebt - sdaiDebt : 0,
                    1e4
                );
            }
        }
        {
            uint256 keeperRewards = gohm.balanceOf(others);
            // After defaults the clearing house keeps the collateral (which is supposed to be unstaked and burned)
            assertEq(
                gohm.balanceOf(address(clearinghouse)),
                gohmNeeded1 + gohmNeeded2 - keeperRewards,
                "gOHM balance"
            );
            // Check: OHM supply = keeper rewards (only minted before burning)
            assertEq(ohm.totalSupply(), keeperRewards, "OHM supply");

            {
                uint256 maxAuctionReward1 = (gohmNeeded1 * 5e16) / 1e18;
                uint256 maxAuctionReward2 = (gohmNeeded2 * 5e16) / 1e18;
                uint256 maxRewards = (maxAuctionReward1 < clearinghouse.MAX_REWARD())
                    ? maxAuctionReward1
                    : clearinghouse.MAX_REWARD();
                maxRewards = (maxAuctionReward2 < clearinghouse.MAX_REWARD())
                    ? maxRewards + maxAuctionReward2
                    : maxRewards + clearinghouse.MAX_REWARD();
                // Check: keeper rewards can't exceed 5% of defaulted collateral
                if (elapsedTime_ >= 7 days) {
                    assertApproxEqAbs(
                        keeperRewards,
                        maxRewards,
                        1e4,
                        "rewards <= 5% collat && MAX_REWARD"
                    );
                } else {
                    assertApproxEqAbs(
                        keeperRewards,
                        (maxRewards * elapsedTime_) / 7 days,
                        1e4,
                        "rewards <= auction"
                    );
                }
            }
        }
    }
}
