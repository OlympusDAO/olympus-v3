// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";

import {VgdaoVault} from "src/policies/VgdaoVault.sol";
import {GoerliDaoVotes} from "src/modules/VOTES/GoerliDaoVotes.sol";

contract VgdaoVaultTest is Test {
    using ModuleTestFixtureGenerator for GoerliDaoVotes;

    MockERC20 internal xGDAO;

    // kernel
    Kernel internal kernel;

    // modules
    GoerliDaoVotes internal VOTES;

    // policies
    VgdaoVault internal vGDAOvault;

    // test user
    address internal user1;

    // godmode
    address internal godmode;

    function setUp() public {
        user1 = new UserFactory().create(1)[0];

        // GDAO erc20
        xGDAO = new MockERC20("xGDAO", "xGDAO", 18);

        // Deploy kernel
        kernel = new Kernel();

        // modules
        VOTES = new GoerliDaoVotes(kernel, xGDAO);

        // policies
        vGDAOvault = new VgdaoVault(kernel);

        // set up kernel
        kernel.executeAction(Actions.InstallModule, address(VOTES));
        kernel.executeAction(Actions.ActivatePolicy, address(vGDAOvault));

        godmode = VOTES.generateGodmodeFixture(type(GoerliDaoVotes).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    function testCorrectness_deposit() public {
        uint256 amt = 100 * 1e18;
        xGDAO.mint(user1, amt);

        vm.startPrank(user1);
        xGDAO.approve(address(vGDAOvault), amt);
        vGDAOvault.deposit(amt);
        vm.stopPrank();

        assertEq(xGDAO.balanceOf(user1), 0);
        assertEq(VOTES.balanceOf(user1), amt); // minted at 1:1
        assertEq(VOTES.lastActionTimestamp(user1), 0); // since its the first mint timestamp should be zero
        assertEq(VOTES.lastDepositTimestamp(user1), block.timestamp);
    }

    function testCorrectness_withdraw() public {
        uint256 amt = 100 * 1e18;
        xGDAO.mint(user1, amt);

        // 1. deposit GDAO to receive VOTES
        vm.startPrank(user1);
        xGDAO.approve(address(vGDAOvault), amt);
        vGDAOvault.deposit(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let deposit vest
        vm.warp(block.timestamp + vGDAOvault.VESTING_PERIOD());

        // 2. withdraw GDAO
        vm.startPrank(user1);
        VOTES.approve(address(vGDAOvault), amt);

        // withdraw
        vGDAOvault.withdraw(amt);
        vm.stopPrank();

        assertEq(xGDAO.balanceOf(user1), amt);
        assertEq(VOTES.balanceOf(user1), 0);
    }

    function testRevert_withdraw_unvested() public {
        uint256 amt = 100 * 1e18;
        xGDAO.mint(user1, amt);

        // 1. deposit GDAO and receive VOTES
        vm.startPrank(user1);
        xGDAO.approve(address(vGDAOvault), amt);
        vGDAOvault.deposit(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let deposit vest half way
        vm.warp(block.timestamp + vGDAOvault.VESTING_PERIOD() / 2);

        // 2. attempt to withdraw GDAO
        vm.startPrank(user1);
        VOTES.approve(address(vGDAOvault), amt);

        // should revert because not vested
        bytes memory err = abi.encodeWithSignature("VgdaoVault_NotVested()");
        vm.expectRevert(err);
        vGDAOvault.withdraw(amt);
        vm.stopPrank();
    }

    function testCorrectness_mint() public {
        uint256 amt = 100 * 1e18;
        xGDAO.mint(user1, amt);

        vm.startPrank(user1);
        xGDAO.approve(address(vGDAOvault), amt);
        vGDAOvault.mint(amt);
        vm.stopPrank();

        assertEq(xGDAO.balanceOf(user1), 0);
        assertEq(VOTES.balanceOf(user1), amt); // minted at 1:1
        assertEq(VOTES.lastActionTimestamp(user1), 0); // since its the first mint timestamp should be zero
        assertEq(VOTES.lastDepositTimestamp(user1), block.timestamp);
    }

    function testCorrectness_redeem() public {
        uint256 amt = 100 * 1e18;
        xGDAO.mint(user1, amt);

        // 1. mint VOTES
        vm.startPrank(user1);
        xGDAO.approve(address(vGDAOvault), amt);
        vGDAOvault.mint(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let mint vest
        vm.warp(block.timestamp + vGDAOvault.VESTING_PERIOD());

        // 2. redeem VOTES for GDAO
        vm.startPrank(user1);
        VOTES.approve(address(vGDAOvault), amt);
        vGDAOvault.redeem(amt);

        // assert VOTES burned and GDAO returned
        assertEq(xGDAO.balanceOf(user1), amt);
        assertEq(VOTES.balanceOf(user1), 0);

        vm.stopPrank();
    }

    function testRevert_redeem_unvested() public {
        uint256 amt = 100 * 1e18;
        xGDAO.mint(user1, amt);

        // 1. mint VOTES
        vm.startPrank(user1);
        xGDAO.approve(address(vGDAOvault), amt);
        vGDAOvault.mint(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let mint vest halfway
        vm.warp(block.timestamp + vGDAOvault.VESTING_PERIOD() / 2);

        // 2. attempt to redeem VOTES for GDAO
        vm.startPrank(user1);
        VOTES.approve(address(vGDAOvault), amt);

        // should revert because not vested
        bytes memory err = abi.encodeWithSignature("VgdaoVault_NotVested()");
        vm.expectRevert(err);
        vGDAOvault.redeem(amt);

        vm.stopPrank();
    }
}
