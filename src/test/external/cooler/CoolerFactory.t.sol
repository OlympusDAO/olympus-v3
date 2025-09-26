// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {MockERC20} from "src/test/mocks/OlympusMocks.sol";

import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";

// Tests for CoolerFactory
//
// [X] generateCooler
//     [X] generates a cooler for new user <> collateral <> debt combinations
//     [X] returns address if a cooler already exists
// [X] newEvent
//     [X] only generated coolers can emit events
//     [X] emitted logs match the input variables

contract CoolerFactoryTest is Test {
    MockERC20 internal collateral;
    MockERC20 internal debt;
    MockERC20 internal otherDebt;

    address public alice;
    address public bob;

    CoolerFactory internal coolerFactory;

    // CoolerFactory Expected events
    event RequestLoan(address indexed cooler, address collateral, address debt, uint256 reqID);
    event RescindRequest(address indexed cooler, uint256 reqID);
    event ClearRequest(address indexed cooler, uint256 reqID, uint256 loanID);
    event RepayLoan(address indexed cooler, uint256 loanID, uint256 amount);
    event ExtendLoan(address indexed cooler, uint256 loanID, uint8 times);
    event DefaultLoan(address indexed cooler, uint256 loanID, uint256 amount);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Create accounts
        UserFactory userFactory = new UserFactory();
        address[] memory users = userFactory.create(2);
        alice = users[0];
        bob = users[1];

        // Deploy mocks
        collateral = new MockERC20("Collateral", "COLLAT", 18);
        debt = new MockERC20("Debt", "DEBT", 18);
        otherDebt = new MockERC20("Other Debt", "OTHER", 18);

        // Deploy system contracts
        coolerFactory = new CoolerFactory();
    }

    // -- CoolerFactory Functions -------------------------------------------------

    function test_generateCooler() public {
        vm.startPrank(alice);
        // First time (alice <> collateral <> debt) the cooler is generated
        address coolerAlice = coolerFactory.generateCooler(collateral, debt);
        assertEq(true, coolerFactory.created(coolerAlice));
        assertEq(coolerAlice, coolerFactory.coolersFor(collateral, debt, 0));
        // Second time (alice <> collateral <> debt) the cooler is just read
        address readCoolerAlice = coolerFactory.generateCooler(collateral, debt);
        assertEq(true, coolerFactory.created(readCoolerAlice));
        assertEq(readCoolerAlice, coolerFactory.coolersFor(collateral, debt, 0));
        vm.stopPrank();

        vm.prank(bob);
        // First time (bob <> collateral <> debt) the cooler is generated
        address coolerBob = coolerFactory.generateCooler(collateral, debt);
        assertEq(true, coolerFactory.created(coolerBob));
        assertEq(coolerBob, coolerFactory.coolersFor(collateral, debt, 1));
        // First time (bob <> collateral <> other debt) the cooler is generated
        address otherCoolerBob = coolerFactory.generateCooler(collateral, otherDebt);
        assertEq(true, coolerFactory.created(otherCoolerBob));
        assertEq(otherCoolerBob, coolerFactory.coolersFor(collateral, otherDebt, 0));
    }

    function testRevert_generateCooler_wrongDecimals() public {
        // Create the wrong tokens
        MockERC20 wrongCollateral = new MockERC20("Collateral", "COL", 6);
        MockERC20 wrongDebt = new MockERC20("Debt", "DEBT", 6);

        // Only tokens with 18 decimals are allowed
        vm.startPrank(alice);

        // Collateral with 6 decimals
        vm.expectRevert(CoolerFactory.DecimalsNot18.selector);
        coolerFactory.generateCooler(wrongCollateral, debt);
        // Debt with 6 decimals
        vm.expectRevert(CoolerFactory.DecimalsNot18.selector);
        coolerFactory.generateCooler(collateral, wrongDebt);
        // Both with 6 decimals
        vm.expectRevert(CoolerFactory.DecimalsNot18.selector);
        coolerFactory.generateCooler(wrongCollateral, wrongDebt);
    }

    function test_newEvent() public {
        uint256 id = 0;
        uint256 amount = 1234;
        uint8 times = 1;

        vm.prank(alice);
        address cooler = coolerFactory.generateCooler(collateral, debt);

        vm.startPrank(cooler);
        // Request Event
        vm.expectEmit(address(coolerFactory));
        emit RequestLoan(cooler, address(collateral), address(debt), id);
        coolerFactory.logRequestLoan(id);
        // Rescind Event
        vm.expectEmit(address(coolerFactory));
        emit RescindRequest(cooler, id);
        coolerFactory.logRescindRequest(id);
        // Clear Event
        vm.expectEmit(address(coolerFactory));
        emit ClearRequest(cooler, id, id);
        coolerFactory.logClearRequest(id, id);
        // Repay Event
        vm.expectEmit(address(coolerFactory));
        emit RepayLoan(cooler, id, amount);
        coolerFactory.logRepayLoan(id, amount);
        // Extend Event
        vm.expectEmit(address(coolerFactory));
        emit ExtendLoan(cooler, id, times);
        coolerFactory.logExtendLoan(id, times);
        // Default Event
        vm.expectEmit(address(coolerFactory));
        emit DefaultLoan(cooler, id, amount);
        coolerFactory.logDefaultLoan(id, amount);
    }

    function testRevert_newEvent_notFromFactory() public {
        uint256 id = 0;

        // Only coolers can emit events
        vm.prank(alice);
        vm.expectRevert(CoolerFactory.NotFromFactory.selector);
        coolerFactory.logRequestLoan(id);
    }

    function test_getCoolerFor() public {
        // Unexistent loans return address(0).
        assertEq(address(0), coolerFactory.getCoolerFor(alice, address(collateral), address(debt)));

        vm.startPrank(alice);
        address coolerAlice = coolerFactory.generateCooler(collateral, debt);
        assertEq(
            coolerAlice,
            coolerFactory.getCoolerFor(alice, address(collateral), address(debt))
        );
    }
}
