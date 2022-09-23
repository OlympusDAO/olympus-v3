// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {Kernel, Module, Instruction, Actions} from "../../Kernel.sol";
import "modules/VOTES.sol";

contract VotesTest is Test {
    Kernel internal kernel;
    using ModuleTestFixtureGenerator for OlympusVotes;

    OlympusVotes internal VOTES;
    address internal writer;
    UserFactory public userCreator;

    event InstructionsStored(uint256);

    function setUp() public {
        /// Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        /// Deploy modules (some mocks)
        VOTES = new OlympusVotes(kernel);

        /// Deploy policies
        Permissions[] memory requests = new Permissions[](3);
        Keycode VOTES_KEYCODE = VOTES.KEYCODE();
        requests[0] = Permissions(VOTES_KEYCODE, VOTES.mintTo.selector);
        requests[1] = Permissions(VOTES_KEYCODE, VOTES.burnFrom.selector);
        requests[2] = Permissions(VOTES_KEYCODE, VOTES.transferFrom.selector);

        writer = VOTES.generateGodmodeFixture(type(OlympusVotes).name);

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(VOTES));

        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, writer);
    }

    function testRevert_TransfersDisabled() public {
        vm.expectRevert(VOTES_TransferDisabled.selector);

        vm.prank(writer);
        VOTES.transfer(address(0), 10);
    }

    function testCorrectness_mintTo() public {
        vm.prank(writer);
        VOTES.mintTo(address(1), 10);
        assertEq(VOTES.balanceOf(address(1)), 10);
    }

    function testCorrectness_burnFrom() public {
        vm.startPrank(writer);
        VOTES.mintTo(address(1), 10);
        VOTES.burnFrom(address(1), 7);
        vm.stopPrank();

        assertEq(VOTES.balanceOf(address(1)), 3);
    }

    function testCorrectness_TransferFrom() public {
        vm.prank(writer);
        VOTES.mintTo(address(1), 10);
        assertEq(VOTES.balanceOf(address(1)), 10);

        vm.prank(writer);
        VOTES.transferFrom(address(1), address(2), 3);
        assertEq(VOTES.balanceOf(address(1)), 7);
        assertEq(VOTES.balanceOf(address(2)), 3);
    }
}
