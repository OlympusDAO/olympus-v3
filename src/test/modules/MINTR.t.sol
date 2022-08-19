// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {UserFactory} from "test/lib/UserFactory.sol";
import {larping} from "test/lib/larping.sol";
import {Quabi} from "test/lib/quabi/Quabi.sol";

import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import "modules/MINTR.sol";
import "src/Kernel.sol";

contract MINTRTest is Test {
    using ModuleTestFixtureGenerator for OlympusMinter;
    using larping for *;

    Kernel internal kernel;
    OlympusMinter internal MINTR;
    IOlympusAuthority internal auth;
    OlympusERC20Token internal ohm;

    address[] public users;
    address public godmode;
    address public dummy;

    function setUp() public {
        kernel = new Kernel();
        auth = new MockLegacyAuthority(address(0x0));
        ohm = new OlympusERC20Token(address(auth));
        MINTR = new OlympusMinter(kernel, address(ohm));

        // Set vault in authority to MINTR module
        auth.vault.larp(address(MINTR));

        // Create dummy user
        users = (new UserFactory()).create(3);

        kernel.executeAction(Actions.InstallModule, address(MINTR));

        godmode = MINTR.generateGodmodeFixture(type(OlympusMinter).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        dummy = MINTR.generateDummyFixture();
        kernel.executeAction(Actions.ActivatePolicy, dummy);
    }

    function test_KEYCODE() public {
        assertEq("MINTR", fromKeycode(MINTR.KEYCODE()));
    }

    function test_ApprovedAddressMintsOhm(address to_, uint256 amount_) public {
        // Will test mint not working against zero-address separately
        vm.assume(to_ != address(0x0));

        // This contract is approved
        vm.prank(godmode);
        MINTR.mintOhm(to_, amount_);

        assertEq(ohm.balanceOf(to_), amount_);
    }

    function testFail_ApprovedAddressCannotMintToZeroAddress(uint256 amount_) public {
        vm.prank(godmode);
        MINTR.mintOhm(address(0x0), amount_);
    }

    function testRevert_UnapprovedAddressCannotMintOhm(address to_, uint256 amount_) public {
        // Have user try to mint
        bytes memory err = abi.encodeWithSelector(Module_PolicyNotPermitted.selector, users[0]);
        vm.expectRevert(err);
        vm.prank(users[0]);
        MINTR.mintOhm(to_, amount_);
    }

    function testCorrectness_ApprovedAddressBurnsOhm(address from_, uint256 amount_) public {
        vm.assume(from_ != address(0x0));

        // Setup: mint ohm into user0
        vm.prank(godmode);
        MINTR.mintOhm(from_, amount_);
        assertEq(ohm.balanceOf(from_), amount_);

        vm.prank(from_);
        ohm.approve(address(MINTR), amount_);

        vm.prank(godmode);
        MINTR.burnOhm(from_, amount_);

        assertEq(ohm.balanceOf(from_), 0);
    }

    function testFail_ApprovedAddressCannotBurnFromZeroAddress(uint256 amount_) public {
        vm.prank(godmode);
        MINTR.burnOhm(address(0x0), amount_);
    }

    // TODO use vm.expectRevert() instead. Did not work for me.
    function testFail_UnapprovedAddressBurnsOhm(uint256 amount_) public {
        // Setup: mint ohm into user0
        MINTR.mintOhm(users[1], amount_);
        assertEq(ohm.balanceOf(users[1]), amount_);

        vm.prank(users[1]);
        ohm.approve(users[0], amount_);

        vm.prank(users[0]);
        MINTR.burnOhm(users[1], amount_);
    }
}

contract MockLegacyAuthority is IOlympusAuthority {
    address internal kernel;

    constructor(address kernel_) {
        kernel = kernel_;
    }

    function governor() external view returns (address) {
        return kernel;
    }

    function guardian() external view returns (address) {
        return kernel;
    }

    function policy() external view returns (address) {
        return kernel;
    }

    function vault() external view returns (address) {
        return kernel;
    }
}
