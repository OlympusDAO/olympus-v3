// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/users.sol";
import "test-utils/mocking.sol";
import "test-utils/sorting.sol";

import {OlympusMinter} from "src/modules/MINTR.sol";
import {LarpKernel} from "./LarpKernel.sol";
import {OlympusERC20Token, IOlympusAuthority} from "../../external/OlympusERC20.sol";

//import {OlympusAuthority} from "../../external/OlympusAuthority.sol";

contract MockLegacyAuthority is IOlympusAuthority {
    address authz;

    constructor(address authz_) {
        authz = authz_;
    }

    function governor() external view returns (address) {
        return authz;
    }

    function guardian() external view returns (address) {
        return authz;
    }

    function policy() external view returns (address) {
        return authz;
    }

    function vault() external view returns (address) {
        return authz;
    }
}

contract MINTRTest is Test {
    using mocking for *;
    using sorting for uint256[];
    using console2 for uint256;

    LarpKernel internal kernel;
    OlympusMinter internal MINTR;
    IOlympusAuthority auth;
    OlympusERC20Token internal ohm;
    users userCreator;
    address[] usrs;

    uint256 internal constant INITIAL_INDEX = 10 * RATE_UNITS;
    uint256 internal constant RATE_UNITS = 1e6;

    function setUp() public {
        kernel = new LarpKernel();
        //auth = new OlympusAuthority(
        //    address(this),
        //    address(this),
        //    address(this),
        //    address(this)
        //);
        auth = new MockLegacyAuthority(address(0x0));
        ohm = new OlympusERC20Token(address(auth));
        MINTR = new OlympusMinter(kernel, ohm);

        // Set vault in authority to MINTR module
        auth.vault.mock(address(MINTR));

        // Create dummy user
        userCreator = new users();
        usrs = userCreator.create(3);

        kernel.installModule(address(MINTR));
        // Approve this test fixture as policy with write permissions
        kernel.grantWritePermissions(MINTR.KEYCODE(), address(this));
    }

    function test_KEYCODE() public {
        assertEq32("MINTR", MINTR.KEYCODE());
    }

    function test_ApprovedAddressMintsOhm(uint256 amount_) public {
        // This contract is approved
        MINTR.mintOhm(usrs[0], amount_);

        assertEq(ohm.balanceOf(usrs[0]), amount_);
    }

    // TODO use vm.expectRevert() instead. Did not work for me.
    function testFail_UnapprovedAddressMintsOhm(uint256 amount_) public {
        // Have user try to mint
        vm.prank(usrs[0]);
        MINTR.mintOhm(usrs[1], amount_);
    }

    function test_ApprovedAddressBurnsOhm(uint256 amount_) public {
        // Setup: mint ohm into user0
        MINTR.mintOhm(usrs[1], amount_);
        assertEq(ohm.balanceOf(usrs[1]), amount_);

        vm.prank(usrs[1]);
        ohm.approve(address(MINTR), amount_);
        MINTR.burnOhm(usrs[1], amount_);
        assertEq(ohm.balanceOf(usrs[1]), 0);
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
