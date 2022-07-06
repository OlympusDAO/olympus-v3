// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/sorting.sol";

import {OlympusMinter} from "modules/MINTR.sol";
import {OlympusERC20Token, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import "src/Kernel.sol";

//import "src/Kernel.sol";

//import {OlympusAuthority} from "../../external/OlympusAuthority.sol";

contract MockLegacyAuthority is IOlympusAuthority {
    address authr;

    constructor(address authr_) {
        authr = authr_;
    }

    function governor() external view returns (address) {
        return authr;
    }

    function guardian() external view returns (address) {
        return authr;
    }

    function policy() external view returns (address) {
        return authr;
    }

    function vault() external view returns (address) {
        return authr;
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
        kernel.executeAction(Actions.ApprovePolicy, address(this));
    }

    function configureReads() external pure {}

    function requestRoles()
        external
        view
        returns (Kernel.Role[] memory requests)
    {
        requests = MINTR.ROLES();
    }

    function test_KEYCODE() public {
        assertEq("MINTR", Kernel.Keycode.unwrap(MINTR.KEYCODE()));
    }

    function test_ROLES() public {
        assertEq("MINTR_Minter", Kernel.Role.unwrap(MINTR.ROLES()[0]));
        assertEq("MINTR_Burner", Kernel.Role.unwrap(MINTR.ROLES()[1]));
    }

    function test_ApprovedAddressMintsOhm(address to_, uint256 amount_) public {
        // Will test mint not working against zero-address separately
        vm.assume(to_ != address(0x0));

        // This contract is approved
        MINTR.mintOhm(to_, amount_);

        assertEq(ohm.balanceOf(to_), amount_);
    }

    function testFail_ApprovedAddressCannotMintToZeroAddress(uint256 amount_)
        public
    {
        // This contract is approved
        MINTR.mintOhm(address(0x0), amount_);
    }

    // TODO use vm.expectRevert() instead. Did not work for me.
    function testFail_UnapprovedAddressMintsOhm(address to_, uint256 amount_)
        public
    {
        // Have user try to mint
        vm.prank(usrs[0]);
        MINTR.mintOhm(to_, amount_);
    }

    function test_ApprovedAddressBurnsOhm(address from_, uint256 amount_)
        public
    {
        // Will test burn not working against zero-address separately
        vm.assume(from_ != address(0x0));

        // Setup: mint ohm into user0
        MINTR.mintOhm(from_, amount_);
        assertEq(ohm.balanceOf(from_), amount_);

        vm.prank(from_);
        ohm.approve(address(MINTR), amount_);
        MINTR.burnOhm(from_, amount_);
        assertEq(ohm.balanceOf(from_), 0);
    }

    function testFail_ApprovedAddressCannotBurnFromZeroAddress(uint256 amount_)
        public
    {
        // This contract is approved
        MINTR.burnOhm(address(0x0), amount_);
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
