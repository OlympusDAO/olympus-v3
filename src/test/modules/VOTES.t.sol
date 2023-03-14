// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {GoerliDaoVotes} from "src/modules/VOTES/GoerliDaoVotes.sol";

import "test/lib/ModuleTestFixtureGenerator.sol";

contract VOTESTest is Test {
    using ModuleTestFixtureGenerator for GoerliDaoVotes;

    uint256 internal MAX_SUPPLY = 10_000_000 * 1e18;

    Kernel internal kernel;

    GoerliDaoVotes internal VOTES;
    MockERC20 internal xGDAO;

    address internal user1;
    address internal user2;
    address internal auxUser;

    function setUp() public {
        address[] memory users = new UserFactory().create(1);
        auxUser = users[0];

        // kernel
        kernel = new Kernel();

        // modules
        xGDAO = new MockERC20("xGDAO", "xGDAO", 18);
        VOTES = new GoerliDaoVotes(kernel, xGDAO);

        // generate godmode address
        user1 = VOTES.generateGodmodeFixture(type(GoerliDaoVotes).name);
        user2 = VOTES.generateGodmodeFixture(type(GoerliDaoVotes).name);

        // set up kernel
        kernel.executeAction(Actions.InstallModule, address(VOTES));
        kernel.executeAction(Actions.ActivatePolicy, user1);
        kernel.executeAction(Actions.ActivatePolicy, user2);
    }

    function testCorrectness_deposit_simple(uint256 amt) public {
        vm.assume(amt > 0 && amt < MAX_SUPPLY);

        xGDAO.mint(user1, amt);
        xGDAO.mint(user2, amt);

        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), amt);
        VOTES.deposit(amt, user1);

        // assert xGDAO was deposited
        assertEq(xGDAO.balanceOf(user1), 0);

        // assert VOTES was exchanged 1:1
        assertEq(VOTES.balanceOf(user1), amt);
        assertEq(VOTES.lastDepositTimestamp(user1), block.timestamp);
        vm.stopPrank();

        vm.startPrank(user2);
        xGDAO.approve(address(VOTES), amt);
        VOTES.deposit(amt, user2);

        // assert xGDAO was deposited
        assertEq(xGDAO.balanceOf(user2), 0);

        // assert VOTES was exchanged 1:1
        assertEq(VOTES.balanceOf(user2), amt);
        assertEq(VOTES.lastDepositTimestamp(user2), block.timestamp);
        vm.stopPrank();
    }

    function testCorrectness_deposit_complex() public {
        uint256 user1DepositAmt = 2_000_000 * 1e18;
        uint256 user2DepositAmt = 1_000_000 * 1e18;

        xGDAO.mint(user1, user1DepositAmt);
        xGDAO.mint(user2, user2DepositAmt);

        // 1. user1 deposits and mints shares 1:1
        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), user1DepositAmt);
        VOTES.deposit(user1DepositAmt, user1);

        // assert xGDAO was deposited and VOTES was exchanged 1:1
        assertEq(xGDAO.balanceOf(address(VOTES)), user1DepositAmt);
        assertEq(VOTES.balanceOf(user1), user1DepositAmt);
        assertEq(VOTES.lastDepositTimestamp(user1), block.timestamp);
        vm.stopPrank();

        // 2. yield is deposited into VOTES
        uint256 yieldAmt = 2_000_000 * 1e18;
        xGDAO.mint(auxUser, yieldAmt);
        vm.prank(auxUser);
        xGDAO.transfer(address(VOTES), yieldAmt);

        // assert underlying amt and share amt (sanity check)
        // 2_000_000 + 2_000_000 xGDAO to 2_000_000 VOTES
        // 2 xGDAO : 1 VOTES
        assertEq(xGDAO.balanceOf(address(VOTES)), user1DepositAmt + yieldAmt);
        assertEq(VOTES.totalSupply(), user1DepositAmt);

        // 3. user2 deposits more assets mints shares 1:2
        vm.startPrank(user2);
        xGDAO.approve(address(VOTES), user2DepositAmt);
        VOTES.deposit(user2DepositAmt, user2);

        // assert expected amount of xGDAO is on contract
        assertEq(xGDAO.balanceOf(address(VOTES)), user1DepositAmt + yieldAmt + user2DepositAmt);

        // xGDAO:VOTES at 2:1 ratio
        assertEq(VOTES.balanceOf(user2), user2DepositAmt / 2);

        assertEq(VOTES.lastDepositTimestamp(user2), block.timestamp);

        vm.stopPrank();
    }

    function testCorrectness_mint(uint256 amt) public {
        vm.assume(amt > 2 && amt % 2 == 0 && amt <= MAX_SUPPLY / 3);

        xGDAO.mint(user1, amt);
        xGDAO.mint(user2, amt * 2);

        // mint VOTES from xGDAO at 1:1
        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), amt);
        uint256 user1DepositTimestamp = block.timestamp;
        VOTES.mint(amt, user1);

        // force block.timestamp to change to test lastDepositTimestamp
        vm.warp(block.timestamp + 1);

        // assert VOTES was minted at 1:1
        assertEq(VOTES.balanceOf(user1), amt);
        assertEq(xGDAO.balanceOf(user1), 0);
        assertEq(VOTES.lastDepositTimestamp(user1), user1DepositTimestamp);
        vm.stopPrank();

        // double the amount of assets
        xGDAO.mint(address(VOTES), amt);

        vm.startPrank(user2);
        xGDAO.approve(address(VOTES), amt * 2);
        uint256 user2DepositTimestamp = block.timestamp;
        VOTES.mint(amt, user2);

        // force block.timestamp to change to test lastDepositTimestamp
        vm.warp(block.timestamp + 1);

        // assert that VOTES was minted at 1:2
        assertEq(VOTES.balanceOf(user2), amt);
        assertEq(xGDAO.balanceOf(user2), 0);
        assertEq(VOTES.lastDepositTimestamp(user2), user2DepositTimestamp);
        vm.stopPrank();
    }

    function testCorrectness_withdraw(uint256 amt) public {
        vm.assume(amt > 0 && amt <= MAX_SUPPLY);

        xGDAO.mint(user1, amt);

        // exchange all xGDAO for VOTES at 1:1
        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), amt);
        VOTES.deposit(amt, user1);
        vm.stopPrank();

        // double the amount of assets backing each share
        xGDAO.mint(address(VOTES), amt);

        // withdraw double the assets that user1 deposited with
        vm.startPrank(user1);
        uint256 beforeBalance = xGDAO.balanceOf(user1);
        VOTES.withdraw(amt * 2, user1, user1);

        // assert that user exchanged all VOTES for xGDAO at 1:2
        assertEq(VOTES.balanceOf(user1), 0);
        assertEq(xGDAO.balanceOf(user1), beforeBalance + (amt * 2));
        vm.stopPrank();
    }

    function testCorrectness_redeem(uint256 amt) public {
        vm.assume(amt > 0 && amt <= MAX_SUPPLY / 2 && amt % 2 == 0);

        xGDAO.mint(user1, amt);

        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), amt);
        VOTES.deposit(amt, user1);
        vm.stopPrank();

        xGDAO.mint(address(VOTES), amt);

        vm.startPrank(user1);
        VOTES.redeem(amt, user1, user1);

        // assert that redeemed VOTES at 2:1
        assertEq(VOTES.balanceOf(user1), 0);
        assertEq(xGDAO.balanceOf(user1), amt * 2);
        vm.stopPrank();
    }

    function testRevert_transfer(
        address sender,
        address receiver,
        uint256 balance
    ) public {
        if (sender == user1 || sender == user2) return; // privileged accounts are allowed to transfer

        vm.assume(sender != address(0) && receiver != address(0) && balance != 0);

        // mint fuzzed amount to address
        xGDAO.mint(user1, balance);

        // exchange xGDAO for VOTES and mint to sender
        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), balance);
        VOTES.mint(balance, sender);
        vm.stopPrank();

        // approve receiver as sender
        vm.prank(sender);
        VOTES.approve(receiver, balance);

        bytes memory err = abi.encodeWithSignature("Module_PolicyNotPermitted(address)", [sender]);
        vm.expectRevert(err);
        vm.prank(sender);
        VOTES.transfer(receiver, balance);
    }

    function testCorrectness_transferFrom() public {
        uint256 balance = 100 * 1e18;
        xGDAO.mint(user1, balance);

        // mint VOTES to aux user
        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), balance);
        VOTES.mint(balance, auxUser);
        vm.stopPrank();

        // approve user1 to move balance
        vm.prank(auxUser);
        VOTES.approve(user1, balance);

        // transfer from aux user to user2
        vm.prank(user1);
        VOTES.transferFrom(auxUser, user2, balance);

        // assert user2 received from aux user
        assertEq(VOTES.balanceOf(user2), balance);
        assertEq(VOTES.balanceOf(auxUser), 0);
        assertEq(VOTES.lastDepositTimestamp(user2), block.timestamp);
    }

    function testRevert_transferFrom() public {
        uint256 balance = 100 * 1e18;
        xGDAO.mint(user1, balance);

        // mint VOTES to user1 and approve aux user to take VOTES from user1
        vm.startPrank(user1);
        xGDAO.approve(address(VOTES), balance);
        VOTES.mint(balance, user1);

        // approve aux user to take VOTES
        VOTES.approve(auxUser, balance);
        vm.stopPrank();

        // attempt to transfer from user1 to aux while impersonating aux user
        vm.prank(auxUser);
        bytes memory err = abi.encodeWithSignature("Module_PolicyNotPermitted(address)", [auxUser]);
        vm.expectRevert(err); // should revert because aux user is not authed
        VOTES.transferFrom(user1, auxUser, balance);
    }
}
