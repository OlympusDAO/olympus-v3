// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "modules/LENDR/OlympusLender.sol";
import "src/Kernel.sol";

contract LENDRTest is Test {
    using ModuleTestFixtureGenerator for OlympusLender;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address public godmode;
    address public dummy;

    Kernel internal kernel;
    OlympusLender internal LENDR;

    function setUp() public {
        userCreator = new UserFactory();

        // Initialize  users
        {
            address[] memory users = userCreator.create(2);
            alice = users[0];
            bob = users[1];
        }

        // Deploy Kernel and LENDR
        {
            kernel = new Kernel();
            LENDR = new OlympusLender(kernel);
        }

        // Generate fixtures
        {
            godmode = LENDR.generateGodmodeFixture(type(OlympusLender).name);
            dummy = LENDR.generateDummyFixture();
        }

        // Install modules and policies on Kernel
        {
            kernel.executeAction(Actions.InstallModule, address(LENDR));
            kernel.executeAction(Actions.ActivatePolicy, godmode);
            kernel.executeAction(Actions.ActivatePolicy, dummy);
        }
    }

    /// [X]  Module Data
    ///     [X]  KEYCODE returns correctly
    ///     [X]  VERSION returns correctly

    function test_KEYCODE() public {
        assertEq("LENDR", fromKeycode(LENDR.KEYCODE()));
    }

    function test_VERSION() public {
        (uint8 major, uint8 minor) = LENDR.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    /// [X]  borrow()
    ///     [X]  Unapproved market cannot borrow
    ///     [X]  Approved market cannot borrow in excess of its limit
    ///     [X]  Approved market cannot push global debt beyond limit
    ///     [X]  Approved market can borrow up to its limit
    ///     [X]  Borrowing increases market debt and global debt

    function _setupBorrow() internal {
        vm.startPrank(godmode);
        LENDR.setGlobalLimit(150_000_000_000_000);
        LENDR.setMarketLimit(godmode, 100_000_000_000_000);
        vm.stopPrank();
    }

    function testCorrectness_unapprovedMarketCannotBorrow(address user_, uint256 amount_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to borrow as an unapproved market
        vm.prank(user_);
        LENDR.borrow(amount_);
    }

    function testCorrectness_approvedMarketCannotBorrowBeyondLimit(uint256 amount_) public {
        vm.assume(amount_ > 100_000_000_000_000);

        _setupBorrow();
        vm.startPrank(godmode);
        LENDR.setGlobalLimit(amount_);

        // Expected error
        bytes memory err = abi.encodeWithSelector(LENDRv1.LENDR_MarketLimitViolation.selector);
        vm.expectRevert(err);

        // Try to borrow beyond godmode's limit
        LENDR.borrow(amount_);
        vm.stopPrank();
    }

    function testCorrectness_approvedMarketCannotPushDebtBeyondGlobalLimit(uint256 amount_) public {
        vm.assume(amount_ > 0);
        vm.assume(amount_ < 100_000_000_000_000);

        _setupBorrow();
        vm.startPrank(godmode);
        LENDR.setMarketLimit(godmode, 150_000_000_000_000);
        LENDR.borrow(150_000_000_000_000);

        // Expected error
        bytes memory err = abi.encodeWithSelector(LENDRv1.LENDR_GlobalLimitViolation.selector);
        vm.expectRevert(err);

        // Try to borrow beyond global limit
        LENDR.borrow(amount_);
        vm.stopPrank();
    }

    function testCorrectness_approvedMarketCanBorrowUpToItsLimit(uint256 amount_) public {
        vm.assume(amount_ < 100_000_000_000_000);

        _setupBorrow();

        // Try to borrow up to godmode's limit
        vm.prank(godmode);
        LENDR.borrow(amount_);
    }

    function testCorrectness_borrowingIncreasesMarketDebtAndGlobalDebt(uint256 amount_) public {
        vm.assume(amount_ < 100_000_000_000_000);

        _setupBorrow();

        // Verify initial state
        assertEq(LENDR.globalDebtOutstanding(), 0);
        assertEq(LENDR.marketDebtOutstanding(godmode), 0);

        // Try to borrow up to godmode's limit
        vm.prank(godmode);
        LENDR.borrow(amount_);

        // Verify end state
        assertEq(LENDR.globalDebtOutstanding(), amount_);
        assertEq(LENDR.marketDebtOutstanding(godmode), amount_);
    }

    /// [X]  repay()
    ///     [X]  Unapproved market cannot repay
    ///     [X]  Approved market can repay
    ///     [X]  Repay reduces market and global debt
    ///     [X]  Repay above market debt max repays

    function _setupRepay() internal {
        vm.startPrank(godmode);
        LENDR.setGlobalLimit(150_000_000_000_000);
        LENDR.setMarketLimit(godmode, 100_000_000_000_000);
        LENDR.borrow(100_000_000_000_000);
        vm.stopPrank();
    }

    function testCorrectness_unapprovedMarketCannotRepay(address user_, uint256 amount_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to repay as an unapproved market
        vm.prank(user_);
        LENDR.repay(amount_);
    }

    function testCorrectness_approvedMarketCanRepay() public {
        _setupBorrow();

        // Try to repay godmode's full debt
        vm.prank(godmode);
        LENDR.repay(100_000_000_000_000);
    }

    function testCorrectness_repayReducesDebtValues(uint256 amount_) public {
        vm.assume(amount_ <= 100_000_000_000_000);

        _setupRepay();

        // Verify initial state
        assertEq(LENDR.globalDebtOutstanding(), 100_000_000_000_000);
        assertEq(LENDR.marketDebtOutstanding(godmode), 100_000_000_000_000);

        // Try to repay some of godmode's debt
        vm.prank(godmode);
        LENDR.repay(amount_);

        // Verify end state
        assertEq(LENDR.globalDebtOutstanding(), 100_000_000_000_000 - amount_);
        assertEq(LENDR.marketDebtOutstanding(godmode), 100_000_000_000_000 - amount_);
    }

    function testCorrectness_repayAboveDebtMaxRepays(uint256 amount_) public {
        vm.assume(amount_ > 100_000_000_000_000);

        _setupRepay();

        // Verify initial state
        assertEq(LENDR.globalDebtOutstanding(), 100_000_000_000_000);
        assertEq(LENDR.marketDebtOutstanding(godmode), 100_000_000_000_000);

        // Try to max repay godmode's debt
        vm.prank(godmode);
        LENDR.repay(amount_);

        // Verify end state
        assertEq(LENDR.globalDebtOutstanding(), 0);
        assertEq(LENDR.marketDebtOutstanding(godmode), 0);
    }

    /// [X]  setGlobalLimit()
    ///     [X]  Unapproved policy cannot change global limit
    ///     [X]  Approved policy cannot set limit below current global debt
    ///     [X]  Correctly sets new limit

    function testCorrectness_unapprovedPolicyCannotChangeGlobalLimit(address user_, uint256 amount_)
        public
    {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to set global debt limit as an unapproved policy
        vm.prank(user_);
        LENDR.setGlobalLimit(amount_);
    }

    function testCorrectness_approvedPolicyCantSetGlobalLimitBelowCurrentDebt(uint256 amount_)
        public
    {
        vm.assume(amount_ < 100_000_000_000_000);

        vm.startPrank(godmode);

        // Set up initial state
        LENDR.setGlobalLimit(100_000_000_000_000);
        LENDR.setMarketLimit(godmode, 100_000_000_000_000);
        LENDR.borrow(100_000_000_000_000);

        // Expected error
        bytes memory err = abi.encodeWithSelector(LENDRv1.LENDR_InvalidParams.selector);
        vm.expectRevert(err);

        // Try to set global limit below current debt outstanding
        LENDR.setGlobalLimit(amount_);
        vm.stopPrank();
    }

    function testCorrectness_correctlySetsGlobalLimit(uint256 amount_) public {
        // Verify initial state
        assertEq(LENDR.globalDebtLimit(), 0);

        // Set new global limit
        vm.prank(godmode);
        LENDR.setGlobalLimit(amount_);

        // Verify end state
        assertEq(LENDR.globalDebtLimit(), amount_);
    }

    /// [X]  setMarketLimit()
    ///     [X]  Unapproved policy cannot change market limit
    ///     [X]  Approved policy cannot set limit below current market debt
    ///     [X]  Correctly sets new limit

    function testCorrectness_unapprovedPolicyCannotChangeMarketLimit(address user_, uint256 amount_)
        public
    {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to set market debt limit
        vm.prank(user_);
        LENDR.setMarketLimit(godmode, amount_);
    }

    function testCorrectness_approvedPolicyCantSetMarketLimitBelowCurrentDebt(uint256 amount_)
        public
    {
        vm.assume(amount_ < 100_000_000_000_000);

        vm.startPrank(godmode);

        // Set up initial state
        LENDR.setGlobalLimit(100_000_000_000_000);
        LENDR.setMarketLimit(godmode, 100_000_000_000_000);
        LENDR.borrow(100_000_000_000_000);

        // Expected error
        bytes memory err = abi.encodeWithSelector(LENDRv1.LENDR_InvalidParams.selector);
        vm.expectRevert(err);

        // Try to set market limit below current debt outstanding
        LENDR.setMarketLimit(godmode, amount_);
        vm.stopPrank();
    }

    function testCorrectness_correctlySetsMarketLimit(uint256 amount_) public {
        // Verify initial state
        assertEq(LENDR.marketDebtLimit(godmode), 0);

        // Set new market debt limit
        vm.prank(godmode);
        LENDR.setMarketLimit(godmode, amount_);

        // Verify end state
        assertEq(LENDR.marketDebtLimit(godmode), amount_);
    }

    /// [X]  setMarketTargetRate()
    ///     [X]  Unapproved policy cannot change market target rate
    ///     [X]  Approved policy can correctly set new target rate

    function testCorrectness_unapprovedPolicyCantChangeTargetRate(address user_, uint32 newRate_)
        public
    {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to set market target rate
        vm.prank(user_);
        LENDR.setMarketTargetRate(godmode, newRate_);
    }

    function testCorrectness_correctlySetsMarketTargetRate(uint32 newRate_) public {
        // Verify initial state
        assertEq(LENDR.marketTargetRate(godmode), 0);

        // Set godmode's target rate
        vm.prank(godmode);
        LENDR.setMarketTargetRate(godmode, newRate_);

        // Verify end state
        assertEq(LENDR.marketTargetRate(godmode), newRate_);
    }

    /// [X]  setUnwind()
    ///     [X]  Unapproved policy cannot change market's unwind status
    ///     [X]  Approved policy correctly changes market's unwind status

    function testCorrectness_unapprovedPolicyCantChangeUnwindStatus(address user_, bool unwind_)
        public
    {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to set market's unwind status
        vm.prank(user_);
        LENDR.setUnwind(godmode, unwind_);
    }

    function testCorrectness_correctlySetsUnwindStatus(bool unwind_) public {
        // Verify initial state
        assertFalse(LENDR.shouldUnwind(godmode));

        // Set godmode's unwind status
        vm.prank(godmode);
        LENDR.setUnwind(godmode, unwind_);

        // Verify end state
        assertEq(LENDR.shouldUnwind(godmode), unwind_);
    }

    /// [X]  approveMarket()
    ///     [X]  Unapproved policy cannot approve a market
    ///     [X]  Cannot approve a market that is already approved
    ///     [X]  Market is approved correctly

    function testCorrectness_unapprovedPolicyCannotApproveMarket(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to approve market
        vm.prank(user_);
        LENDR.approveMarket(godmode);
    }

    function testCorrectness_cannotApproveAlreadyApprovedMarket() public {
        // Setup
        vm.prank(godmode);
        LENDR.approveMarket(godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(LENDRv1.LENDR_MarketAlreadyApproved.selector);
        vm.expectRevert(err);

        // Try to approve market
        vm.prank(godmode);
        LENDR.approveMarket(godmode);
    }

    function testCorrectness_approvesMarketCorrectly() public {
        // Verify initial state
        assertEq(LENDR.approvedMarketsCount(), 0);
        assertFalse(LENDR.isMarketApproved(godmode));

        // Approve market
        vm.prank(godmode);
        LENDR.approveMarket(godmode);

        // Verify end state
        assertEq(LENDR.approvedMarketsCount(), 1);
        assertEq(LENDR.approvedMarkets(0), godmode);
        assertTrue(LENDR.isMarketApproved(godmode));
    }

    /// [X]  removeMarket()
    ///     [X]  Unapproved policy cannot remove a market
    ///     [X]  Cannot remove a market that is not approved
    ///     [X]  Cannot remove market if index doesn't match
    ///     [X]  Market is removed correctly

    function testCorrectness_unapprovedPolicyCannotRemoveMarket(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to remove market
        vm.prank(user_);
        LENDR.removeMarket(0, godmode);
    }

    function testCorrectness_cannotRemoveUnapprovedMarket() public {
        // Expected error
        bytes memory err = abi.encodeWithSelector(LENDRv1.LENDR_InvalidMarketRemoval.selector);
        vm.expectRevert(err);

        // Try to remove market
        vm.prank(godmode);
        LENDR.removeMarket(0, godmode);
    }

    function testCorrectness_cannotRemoveMarketIfIndexDoesntMatch() public {
        // Setup
        vm.prank(godmode);
        LENDR.approveMarket(godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(LENDRv1.LENDR_InvalidMarketRemoval.selector);
        vm.expectRevert(err);

        // Try to remove market
        vm.prank(godmode);
        LENDR.removeMarket(0, address(0));
    }

    function testCorrectness_removesMarketCorrectly() public {
        // Setup
        vm.prank(godmode);
        LENDR.approveMarket(godmode);

        // Verify initial state
        assertEq(LENDR.approvedMarketsCount(), 1);
        assertEq(LENDR.approvedMarkets(0), godmode);
        assertTrue(LENDR.isMarketApproved(godmode));

        // Remove market
        vm.prank(godmode);
        LENDR.removeMarket(0, godmode);

        // Verify end state
        assertEq(LENDR.approvedMarketsCount(), 0);
        assertFalse(LENDR.isMarketApproved(godmode));
    }
}
