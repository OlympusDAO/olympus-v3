// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test-utils/UserFactory.sol";

import {Kernel, Module, Instruction, Actions} from "../../Kernel.sol";
import "modules/VOTES.sol";
import {MockModuleWriter} from "../mocks/MockModuleWriter.sol";

contract VotesTest is Test {
    Kernel internal kernel;

    OlympusVotes internal VOTES;
    MockModuleWriter internal votes;
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

        votes = new MockModuleWriter(kernel, VOTES, requests);

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(VOTES));

        /// Approve policies
        kernel.executeAction(Actions.ApprovePolicy, address(votes));
    }

    function testRevert_TransfersDisabled() public {
        vm.expectRevert(VOTES_TransferDisabled.selector);

        OlympusVotes(address(votes)).transfer(address(0), 10);
    }

    function testCorrectness_mintTo() public {
        OlympusVotes(address(votes)).mintTo(address(1), 10);
        assertEq(VOTES.balanceOf(address(1)), 10);
    }

    function testCorrectness_burnFrom() public {
        OlympusVotes(address(votes)).mintTo(address(1), 10);
        OlympusVotes(address(votes)).burnFrom(address(1), 7);

        assertEq(VOTES.balanceOf(address(1)), 3);
    }

    function testCorrectness_TransferFrom() public {
        OlympusVotes(address(votes)).mintTo(address(1), 10);
        assertEq(VOTES.balanceOf(address(1)), 10);

        OlympusVotes(address(votes)).transferFrom(address(1), address(2), 3);
        assertEq(VOTES.balanceOf(address(1)), 7);
        assertEq(VOTES.balanceOf(address(2)), 3);
    }
}
