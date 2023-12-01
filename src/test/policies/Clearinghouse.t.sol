// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockStaking} from "test/mocks/MockStaking.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {RolesAdmin, Kernel, Actions, Permissions, Keycode, fromKeycode, toKeycode} from "olympus-v3/policies/RolesAdmin.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {OlympusMinter, MINTRv1} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury, TRSRYv1} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusClearinghouseRegistry, CHREGv1} from "modules/CHREG/OlympusClearinghouseRegistry.sol";

import {Clearinghouse, Cooler, CoolerFactory, CoolerCallback} from "policies/Clearinghouse.sol";

// Tests for Clearinghouse
//
// Clearinghouse Setup and Permissions.
// [X] configureDependencies
//     [X] dependencies are properly configured.
//     [X] clearinghouse is stored in the CHREG.
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
// [X] extendLoan
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

/// @dev Although there is sDAI in the treasury, the sDAI will be equal to
///      DAI values everytime we convert between them. This is because no external
///      DAI is being added to the sDAI vault, so the exchange rate is 1:1. This
///      does not cause any issues with our testing.
contract ClearinghouseTest is Test {
    MockOhm internal ohm;
    MockERC20 internal gohm;
    MockERC20 internal dai;
    MockERC4626 internal sdai;

    Kernel public kernel;
    OlympusRoles internal ROLES;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;
    OlympusClearinghouseRegistry internal CHREG;
    RolesAdmin internal rolesAdmin;
    Clearinghouse internal clearinghouse;
    CoolerFactory internal factory;
    Cooler internal testCooler;

    address internal user;
    address internal others;
    address internal overseer;
    uint256 internal initialSDai;

    // Clearinghouse Expected events
    event Defund(address token, uint256 amount);
    event Rebalance(bool defund, uint256 daiAmount);
    event Activate();
    event Deactivate();

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
        CHREG = new OlympusClearinghouseRegistry(kernel, address(0), new address[](0));

        clearinghouse = new Clearinghouse(
            address(ohm),
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
        kernel.executeAction(Actions.InstallModule, address(CHREG));

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

        vm.prank(overseer);
        clearinghouse.activate();

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

    // --- SETUP, DEPENDENCIES, AND PERMISSIONS --------------------------

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](4);
        expectedDeps[0] = toKeycode("CHREG");
        expectedDeps[1] = toKeycode("MINTR");
        expectedDeps[2] = toKeycode("ROLES");
        expectedDeps[3] = toKeycode("TRSRY");

        Keycode[] memory deps = clearinghouse.configureDependencies();
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

    function testFuzz_lendToCooler(uint256 loanAmount_) public {
        // Loan amount cannot exceed Clearinghouse funding
        loanAmount_ = bound(loanAmount_, 0, clearinghouse.FUND_AMOUNT());

        // Create the Cooler
        vm.prank(user);
        Cooler cooler = Cooler(factory.generateCooler(gohm, dai));

        // Ensure user has enough collateral
        uint256 gohmNeeded = cooler.collateralFor(loanAmount_, clearinghouse.LOAN_TO_COLLATERAL());
        _fundUser(gohmNeeded);

        vm.prank(user);
        uint256 loanID = clearinghouse.lendToCooler(cooler, loanAmount_);

        // Check: balances
        assertEq(gohm.balanceOf(address(cooler)), gohmNeeded);
        assertEq(dai.balanceOf(address(user)), loanAmount_);
        assertEq(dai.balanceOf(address(cooler)), 0);

        Cooler.Loan memory loan = cooler.getLoan(loanID);

        // Check: clearinghouse storage
        assertEq(
            clearinghouse.principalReceivables(),
            loan.principal,
            "principalReceivables (Loan)"
        );
        assertApproxEqAbs(
            clearinghouse.interestReceivables(),
            clearinghouse.interestForLoan(loanAmount_, clearinghouse.DURATION()),
            1e4,
            "interestReceivables (CH)"
        );
        assertApproxEqAbs(
            clearinghouse.interestReceivables(),
            loan.interestDue,
            1e4,
            "interestReceivables (Loan)"
        );
        assertApproxEqAbs(
            clearinghouse.getTotalReceivables(),
            loan.principal + loan.interestDue,
            1e4,
            "getTotalReceivables"
        );
    }

    // --- EXTEND LOAN -----------------------------------------------------

    function testFuzz_extendLoan(uint256 loanAmount_, uint256 elapsed_, uint8 times_) public {
        // Loan amount cannot exceed Clearinghouse funding
        loanAmount_ = bound(loanAmount_, 1e10, clearinghouse.FUND_AMOUNT());
        elapsed_ = bound(elapsed_, 0, clearinghouse.DURATION());
        times_ = uint8(bound(times_, 1, 255));

        (Cooler cooler, , uint256 loanID) = _createLoanForUser(loanAmount_);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward without defaulting
        _skip(elapsed_);
        // Rebalance to ensure the extension funds will stay in the CH
        for (uint256 i = 0; i <= elapsed_ / clearinghouse.FUND_CADENCE(); i++) {
            clearinghouse.rebalance();
        }

        vm.startPrank(user);
        // Cache DAI balance and interest to be paid in the future
        uint256 initDaiUser = dai.balanceOf(user);
        uint256 initDaiCH = dai.balanceOf(address(clearinghouse));
        uint256 initSdaiCH = sdai.balanceOf(address(clearinghouse));
        uint256 initInterest = clearinghouse.interestReceivables();
        uint256 initPrincipal = clearinghouse.principalReceivables();
        // Approve the interest of the extensions
        uint256 interestOwed = clearinghouse.interestForLoan(
            initLoan.principal,
            initLoan.request.duration
        ) * times_;
        uint256 interestOwedInSdai = sdai.previewDeposit(interestOwed);
        dai.approve(address(clearinghouse), interestOwed);
        // Extend loan
        clearinghouse.extendLoan(cooler, loanID, times_);
        vm.stopPrank();

        Cooler.Loan memory extendedLoan = cooler.getLoan(loanID);

        // Check: balances
        assertEq(dai.balanceOf(user), initDaiUser - interestOwed, "DAI user");
        assertEq(dai.balanceOf(address(clearinghouse)), initDaiCH, "DAI CH");
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            initSdaiCH + interestOwedInSdai,
            "sDAI CH"
        );
        // Check: cooler storage
        assertEq(extendedLoan.principal, initLoan.principal, "principal");
        assertEq(extendedLoan.interestDue, initLoan.interestDue, "interest");
        assertEq(extendedLoan.collateral, initLoan.collateral, "collateral");
        assertEq(
            extendedLoan.expiry,
            initLoan.expiry + initLoan.request.duration * times_,
            "expiry"
        );
        // Check: clearinghouse storage
        assertEq(clearinghouse.interestReceivables(), initInterest);
        assertEq(clearinghouse.principalReceivables(), initPrincipal);
    }

    function testFuzz_extendLoan_withPriorRepayment(
        uint256 loanAmount_,
        uint256 repay_,
        uint256 elapsed_,
        uint8 times_
    ) public {
        // Loan amount cannot exceed Clearinghouse funding
        loanAmount_ = bound(loanAmount_, 1e10, clearinghouse.FUND_AMOUNT());
        elapsed_ = bound(elapsed_, 0, clearinghouse.DURATION());
        times_ = uint8(bound(times_, 1, 255));

        (Cooler cooler, , uint256 loanID) = _createLoanForUser(loanAmount_);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward without defaulting
        _skip(elapsed_);
        // Rebalance to ensure the extension funds will stay in the CH
        for (uint256 i = 0; i <= elapsed_ / clearinghouse.FUND_CADENCE(); i++) {
            clearinghouse.rebalance();
        }

        // Bound repayment
        repay_ = bound(elapsed_, 1, initLoan.interestDue);

        // Repay interest of the first extension manually
        vm.startPrank(user);
        dai.approve(address(cooler), repay_);
        cooler.repayLoan(loanID, repay_);

        // Cache DAI balance and interest after repayment
        Cooler.Loan memory repaidLoan = cooler.getLoan(loanID);
        uint256 initDaiUser = dai.balanceOf(user);
        uint256 initDaiCH = dai.balanceOf(address(clearinghouse));
        uint256 initSdaiCH = sdai.balanceOf(address(clearinghouse));
        uint256 initInterest = clearinghouse.interestReceivables();
        uint256 initPrincipal = clearinghouse.principalReceivables();
        // Approve the interest of the followup extensions
        uint256 interestOwed = clearinghouse.interestForLoan(
            initLoan.principal,
            initLoan.request.duration
        ) * times_;
        uint256 interestOwedInSdai = sdai.previewDeposit(interestOwed);
        dai.approve(address(clearinghouse), interestOwed);

        // Extend loan
        clearinghouse.extendLoan(cooler, loanID, times_);
        vm.stopPrank();

        Cooler.Loan memory extendedLoan = cooler.getLoan(loanID);

        // Check: balances
        assertEq(dai.balanceOf(user), initDaiUser - interestOwed, "DAI user");
        assertEq(dai.balanceOf(address(clearinghouse)), initDaiCH, "DAI CH");
        assertEq(
            sdai.balanceOf(address(clearinghouse)),
            initSdaiCH + interestOwedInSdai,
            "sDAI CH"
        );
        // Check: cooler storage
        assertEq(extendedLoan.principal, repaidLoan.principal, "principal");
        assertEq(extendedLoan.interestDue, repaidLoan.interestDue, "interest");
        assertEq(extendedLoan.collateral, repaidLoan.collateral, "collateral");
        assertEq(
            extendedLoan.expiry,
            repaidLoan.expiry + repaidLoan.request.duration * times_,
            "expiry"
        );
        // Check: clearinghouse storage
        assertEq(clearinghouse.interestReceivables(), initInterest);
        assertEq(clearinghouse.principalReceivables(), initPrincipal);
    }

    function testRevert_extendLoan_NotFromFactory() public {
        CoolerFactory maliciousFactory = new CoolerFactory();
        Cooler maliciousCooler = Cooler(maliciousFactory.generateCooler(gohm, dai));

        vm.startPrank(others);
        uint256 reqID = maliciousCooler.requestLoan(0, 0, 1, 1);
        uint256 loanID = maliciousCooler.clearRequest(reqID, others, false);

        // Only extendable for loans that come from the trusted Cooler Factory
        vm.expectRevert(CoolerCallback.OnlyFromFactory.selector);
        clearinghouse.extendLoan(maliciousCooler, loanID, 1);
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

        // Ensure that the event is emitted
        vm.expectEmit(address(clearinghouse));
        emit Rebalance(false, oneMillion);
        // Rebalance
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

        // Ensure that the event is emitted
        vm.expectEmit(address(clearinghouse));
        emit Rebalance(true, oneMillion);
        // Rebalance
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

        // Ensure that the event is emitted
        vm.expectEmit(address(clearinghouse));
        emit Defund(address(sdai), sdai.previewRedeem(1e24));
        // Defund
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

        // Check: clearinghouse is deactivated in the CHREG
        assertEq(CHREG.activeCount(), 1);
        assertEq(CHREG.registryCount(), 1);
        assertEq(CHREG.active(0), address(clearinghouse));
        assertEq(CHREG.registry(0), address(clearinghouse));

        // Ensure that the event is emitted
        vm.expectEmit(address(clearinghouse));
        emit Deactivate();
        // Deactivate
        vm.prank(overseer);
        clearinghouse.emergencyShutdown();
        assertEq(clearinghouse.active(), false);
        assertEq(sdai.balanceOf(address(TRSRY)), sdaiTrsryBal + sdaiCHBal);

        // Check: clearinghouse is deactivated in the CHREG
        assertEq(CHREG.activeCount(), 0);
        assertEq(CHREG.registryCount(), 1);
        assertEq(CHREG.registry(0), address(clearinghouse));
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

        // Ensure that the event is emitted
        vm.expectEmit(address(clearinghouse));
        emit Activate();
        // Reactivate
        clearinghouse.activate();
        assertEq(clearinghouse.active(), true);
        vm.stopPrank();

        // Check: clearinghouse is stored in the CHREG
        assertEq(CHREG.activeCount(), 1);
        assertEq(CHREG.registryCount(), 1);
        assertEq(CHREG.active(0), address(clearinghouse));
        assertEq(CHREG.registry(0), address(clearinghouse));
    }

    function testRevert_restartAfterShutdown_onlyRole() public {
        vm.prank(others);
        vm.expectRevert();
        clearinghouse.activate();
    }

    // --- CALLBACKS: ON LOAN REPAYMENT ----------------------------------

    function testFuzz_onRepay(uint256 loanAmount_, uint256 repayAmount_) public {
        // Loan amount cannot exceed Clearinghouse funding
        repayAmount_ = bound(repayAmount_, 1e10, clearinghouse.FUND_AMOUNT());
        loanAmount_ = bound(loanAmount_, repayAmount_, clearinghouse.FUND_AMOUNT());

        (Cooler cooler, , uint256 loanID) = _createLoanForUser(loanAmount_);
        Cooler.Loan memory initLoan = cooler.getLoan(loanID);

        // Move forward to half duration of the loan
        _skip(clearinghouse.DURATION() / 2);

        vm.startPrank(user);
        // Cache clearinghouse receivables
        uint256 initInterest = clearinghouse.interestReceivables();
        uint256 initPrincipal = clearinghouse.principalReceivables();
        dai.approve(address(cooler), repayAmount_);
        cooler.repayLoan(loanID, repayAmount_);

        // Check: clearinghouse storage
        uint256 repaidInterest = repayAmount_ > initLoan.interestDue
            ? initLoan.interestDue
            : repayAmount_;
        uint256 repaidPrincipal = repayAmount_ - repaidInterest;
        assertEq(
            clearinghouse.interestReceivables(),
            initInterest > repaidInterest ? initInterest - repaidInterest : 0
        );
        assertEq(
            clearinghouse.principalReceivables(),
            initPrincipal > repaidPrincipal ? initPrincipal - repaidPrincipal : 0
        );
    }

    function testRevert_onRepay_notFromFactory() public {
        CoolerFactory maliciousFactory = new CoolerFactory();
        Cooler maliciousCooler = Cooler(maliciousFactory.generateCooler(gohm, dai));
        // Coolers not created by the CoolerFactory could be malicious.
        vm.prank(address(maliciousCooler));
        vm.expectRevert(CoolerCallback.OnlyFromFactory.selector);
        clearinghouse.onRepay(0, 0, 0);
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
            uint256 initInterest = clearinghouse.interestReceivables();
            uint256 initPrincipal = clearinghouse.principalReceivables();
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
                uint256 principalDue = initLoan1.principal + initLoan2.principal;
                uint256 interestDue = initLoan1.interestDue + initLoan2.interestDue;
                uint256 sdaiDebt = sdai.previewDeposit(principalDue);
                // Check: clearinghouse storage
                assertEq(
                    clearinghouse.interestReceivables(),
                    initInterest > interestDue ? initInterest - interestDue : 0
                );
                assertEq(
                    clearinghouse.principalReceivables(),
                    initPrincipal > principalDue ? initPrincipal - principalDue : 0
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

    function testRevert_claimDefaulted_NotFromClearinghouse() public {
        // Create legit loan from Clearinghouse
        (Cooler cooler, , uint256 loanID) = _createLoanForUser(100 * 1e18);

        // Move forward after the loans have ended
        _skip(clearinghouse.DURATION() + 1);

        // Attacker creates a fake loan for himself that defaults immediately
        // to try to steal the defaulted collateral from legit loans.
        vm.startPrank(others);
        Cooler maliciousCooler = Cooler(factory.generateCooler(gohm, dai));

        uint256 amountNeeded = maliciousCooler.collateralFor(1e14, 1);
        gohm.mint(others, amountNeeded);
        gohm.approve(address(maliciousCooler), amountNeeded);
        dai.mint(others, amountNeeded);
        dai.approve(address(maliciousCooler), amountNeeded);

        uint256 reqID = maliciousCooler.requestLoan(1e14, 0, 1, 0);
        uint256 maliciousLoanID = maliciousCooler.clearRequest(reqID, others, false);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        address[] memory coolers = new address[](2);
        ids[0] = loanID;
        coolers[0] = address(cooler);
        ids[1] = maliciousLoanID;
        coolers[1] = address(maliciousCooler);

        // Loans not created by the Clearinghouse could be malicious.
        vm.prank(others);
        vm.expectRevert(Clearinghouse.NotLender.selector);
        clearinghouse.claimDefaulted(coolers, ids);
    }

    function testFuzz_equivalentAuxiliarFunctions_fromPrincipal(uint256 principal_) public {
        principal_ = bound(principal_, 0, type(uint256).max / 1e18);

        uint256 collateral = clearinghouse.getCollateralForLoan(principal_);
        (uint256 principal, ) = clearinghouse.getLoanForCollateral(collateral);

        assertApproxEqAbs(principal_, principal, 1e4, "small principal");
    }

    function testFuzz_equivalentAuxiliarFunctions_fromCollateral(uint256 collateral_) public {
        collateral_ = bound(collateral_, 0, type(uint256).max / clearinghouse.LOAN_TO_COLLATERAL());

        (uint256 principal, ) = clearinghouse.getLoanForCollateral(collateral_);
        uint256 collateral = clearinghouse.getCollateralForLoan(principal);

        assertApproxEqAbs(collateral_, collateral, 3e3, "small collateral");
    }
}
