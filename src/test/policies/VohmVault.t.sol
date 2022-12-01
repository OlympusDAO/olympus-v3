// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";

import {VohmVault} from "src/policies/VohmVault.sol";
import {OlympusVotes} from "src/modules/VOTES/OlympusVotes.sol";

contract VohmVaultTest is Test {
    using ModuleTestFixtureGenerator for OlympusVotes;

    MockERC20 internal gOHM;

    // kernel
    Kernel internal kernel;

    // modules
    OlympusVotes internal VOTES;

    // policies
    VohmVault internal vOHMvault;

    // test user
    address internal user1;

    // godmode
    address internal godmode;

    function setUp() public {
        user1 = new UserFactory().create(1)[0];

        // OHM erc20
        gOHM = new MockERC20("gOHM", "gOHM", 18);

        // Deploy kernel
        kernel = new Kernel();

        // modules
        VOTES = new OlympusVotes(kernel, gOHM);

        // policies
        vOHMvault = new VohmVault(kernel);

        // set up kernel
        kernel.executeAction(Actions.InstallModule, address(VOTES));
        kernel.executeAction(Actions.ActivatePolicy, address(vOHMvault));

        godmode = VOTES.generateGodmodeFixture(type(OlympusVotes).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    function testCorrectness_deposit() public {
        uint256 amt = 100 * 1e18;
        gOHM.mint(user1, amt);

        vm.startPrank(user1);
        gOHM.approve(address(vOHMvault), amt);
        vOHMvault.deposit(amt);
        vm.stopPrank();

        assertEq(gOHM.balanceOf(user1), 0);
        assertEq(VOTES.balanceOf(user1), amt); // minted at 1:1
        assertEq(VOTES.lastActionTimestamp(user1), 0); // since its the first mint timestamp should be zero
        assertEq(VOTES.lastDepositTimestamp(user1), block.timestamp);
    }

    function testCorrectness_withdraw() public {
        uint256 amt = 100 * 1e18;
        gOHM.mint(user1, amt);

        // 1. deposit OHM to receive VOTES
        vm.startPrank(user1);
        gOHM.approve(address(vOHMvault), amt);
        vOHMvault.deposit(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let deposit vest
        vm.warp(block.timestamp + vOHMvault.VESTING_PERIOD());

        // 2. withdraw OHM
        vm.startPrank(user1);
        VOTES.approve(address(vOHMvault), amt);

        // withdraw
        vOHMvault.withdraw(amt);
        vm.stopPrank();

        assertEq(gOHM.balanceOf(user1), amt);
        assertEq(VOTES.balanceOf(user1), 0);
    }

    function testRevert_withdraw_unvested() public {
        uint256 amt = 100 * 1e18;
        gOHM.mint(user1, amt);

        // 1. deposit OHM and receive VOTES
        vm.startPrank(user1);
        gOHM.approve(address(vOHMvault), amt);
        vOHMvault.deposit(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let deposit vest half way
        vm.warp(block.timestamp + vOHMvault.VESTING_PERIOD() / 2);

        // 2. attempt to withdraw OHM
        vm.startPrank(user1);
        VOTES.approve(address(vOHMvault), amt);

        // should revert because not vested
        bytes memory err = abi.encodeWithSignature("VohmVault_NotVested()");
        vm.expectRevert(err);
        vOHMvault.withdraw(amt);
        vm.stopPrank();
    }

    function testCorrectness_mint() public {
        uint256 amt = 100 * 1e18;
        gOHM.mint(user1, amt);

        vm.startPrank(user1);
        gOHM.approve(address(vOHMvault), amt);
        vOHMvault.mint(amt);
        vm.stopPrank();

        assertEq(gOHM.balanceOf(user1), 0);
        assertEq(VOTES.balanceOf(user1), amt); // minted at 1:1
        assertEq(VOTES.lastActionTimestamp(user1), 0); // since its the first mint timestamp should be zero
        assertEq(VOTES.lastDepositTimestamp(user1), block.timestamp);
    }

    function testCorrectness_redeem() public {
        uint256 amt = 100 * 1e18;
        gOHM.mint(user1, amt);

        // 1. mint VOTES
        vm.startPrank(user1);
        gOHM.approve(address(vOHMvault), amt);
        vOHMvault.mint(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let mint vest
        vm.warp(block.timestamp + vOHMvault.VESTING_PERIOD());

        // 2. redeem VOTES for OHM
        vm.startPrank(user1);
        VOTES.approve(address(vOHMvault), amt);
        vOHMvault.redeem(amt);

        // assert VOTES burned and OHM returned
        assertEq(gOHM.balanceOf(user1), amt);
        assertEq(VOTES.balanceOf(user1), 0);

        vm.stopPrank();
    }

    function testRevert_redeem_unvested() public {
        uint256 amt = 100 * 1e18;
        gOHM.mint(user1, amt);

        // 1. mint VOTES
        vm.startPrank(user1);
        gOHM.approve(address(vOHMvault), amt);
        vOHMvault.mint(amt);
        vm.stopPrank();

        // reset users actions so they must vest
        vm.prank(godmode);
        VOTES.resetActionTimestamp(user1);

        // let mint vest halfway
        vm.warp(block.timestamp + vOHMvault.VESTING_PERIOD() / 2);

        // 2. attempt to redeem VOTES for OHM
        vm.startPrank(user1);
        VOTES.approve(address(vOHMvault), amt);

        // should revert because not vested
        bytes memory err = abi.encodeWithSignature("VohmVault_NotVested()");
        vm.expectRevert(err);
        vOHMvault.redeem(amt);

        vm.stopPrank();
    }
}
