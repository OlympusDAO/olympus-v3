// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/sorting.sol";

import {OlympusMinter} from "modules/MINTR.sol";
import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import "src/Kernel.sol";
import {MockModuleWriter} from "test/mocks/MockModuleWriter.sol";

contract MockLegacyAuthority is IOlympusAuthority {
    address kernel;

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

contract MINTRTest is Test {
    using larping for *;
    using sorting for uint256[];
    using console2 for uint256;

    Kernel internal kernel;
    OlympusMinter internal MINTR;
    IOlympusAuthority internal auth;
    OlympusERC20Token internal ohm;
    UserFactory userCreator;
    address[] usrs;
    MockModuleWriter writer;
    OlympusMinter MINTRWriter;

    uint256 internal constant INITIAL_INDEX = 10 * RATE_UNITS;
    uint256 internal constant RATE_UNITS = 1e6;

    function setUp() public {
        kernel = new Kernel();
        auth = new MockLegacyAuthority(address(0x0));
        ohm = new OlympusERC20Token(address(auth));
        MINTR = new OlympusMinter(kernel, address(ohm));

        // Set vault in authority to MINTR module
        auth.vault.larp(address(MINTR));

        // Create dummy user
        userCreator = new UserFactory();
        usrs = userCreator.create(3);

        kernel.executeAction(Actions.InstallModule, address(MINTR));
        Permissions[] memory requests = requestPermissions();
        writer = new MockModuleWriter(kernel, MINTR, requests);
        kernel.executeAction(Actions.ApprovePolicy, address(writer));

        MINTRWriter = OlympusMinter(address(writer));
    }

    function requestPermissions() public view returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = MINTR.KEYCODE();

        requests = new Permissions[](2);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
    }

    function test_KEYCODE() public {
        assertEq("MINTR", Keycode.unwrap(MINTR.KEYCODE()));
    }

    function test_ApprovedAddressMintsOhm(address to_, uint256 amount_) public {
        // Will test mint not working against zero-address separately
        vm.assume(to_ != address(0x0));

        // This contract is approved
        MINTRWriter.mintOhm(to_, amount_);

        assertEq(ohm.balanceOf(to_), amount_);
    }

    function testFail_ApprovedAddressCannotMintToZeroAddress(uint256 amount_) public {
        MINTRWriter.mintOhm(address(0x0), amount_);
    }

    function testCorrectness_UnapprovedAddressCannotMintOhm(address to_, uint256 amount_) public {
        // Have user try to mint
        bytes memory err = abi.encodeWithSelector(Module_PolicyNotAuthorized.selector, usrs[0]);
        vm.expectRevert(err);
        vm.prank(usrs[0]);
        MINTR.mintOhm(to_, amount_);
    }

    function test_ApprovedAddressBurnsOhm(address from_, uint256 amount_) public {
        // Will test burn not working against zero-address separately
        vm.assume(from_ != address(0x0));

        // Setup: mint ohm into user0
        MINTRWriter.mintOhm(from_, amount_);
        assertEq(ohm.balanceOf(from_), amount_);

        vm.startPrank(from_);
        ohm.approve(address(MINTR), amount_);
        MINTRWriter.burnOhm(from_, amount_);
        assertEq(ohm.balanceOf(from_), 0);
        vm.stopPrank();
    }

    function testFail_ApprovedAddressCannotBurnFromZeroAddress(uint256 amount_) public {
        MINTRWriter.burnOhm(address(0x0), amount_);
    }

    // TODO use vm.expectRevert() instead. Did not work for me.
    function testFail_UnapprovedAddressBurnsOhm(uint256 amount_) public {
        // Setup: mint ohm into user0
        MINTR.mintOhm(usrs[1], amount_);
        assertEq(ohm.balanceOf(usrs[1]), amount_);

        vm.prank(usrs[1]);
        ohm.approve(usrs[0], amount_);
        vm.prank(usrs[0]);
        MINTR.burnOhm(usrs[1], amount_);
    }
}
