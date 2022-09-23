// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import "src/Kernel.sol";

import {OlympusVotes} from "modules/VOTES.sol";

import {VoterRegistration} from "policies/VoterRegistration.sol";

contract VoterRegistrationTest is Test {
    UserFactory public userCreator;
    address internal randomWallet;
    address internal govMultisig;

    Kernel internal kernel;

    OlympusVotes internal votes;
    VoterRegistration internal voterRegistration;

    function setUp() public {
        userCreator = new UserFactory();

        /// Create Voters
        address[] memory users = userCreator.create(2);
        randomWallet = users[0];
        govMultisig = users[1];

        /// Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        /// Deploy modules
        votes = new OlympusVotes(kernel);

        /// Deploy policies
        voterRegistration = new VoterRegistration(kernel);

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(votes));

        /// Approve policies`
        kernel.executeAction(Actions.ActivatePolicy, address(voterRegistration));

        /// Configure access control
        kernel.grantRole(toRole("voter_admin"), govMultisig);
    }

    ////////////////////////////////
    //   ISSUING/REVOKING VOTES   //
    ////////////////////////////////

    function testRevert_WhenCalledByRandomWallet() public {
        bytes memory err = abi.encodeWithSelector(Policy_OnlyRole.selector, toRole("voter_admin"));
        vm.expectRevert(err);
        vm.prank(randomWallet);
        voterRegistration.issueVotesTo(randomWallet, 1000);
    }

    function testCorrectness_WhenCalledByProperAuthority() public {
        vm.prank(govMultisig);
        voterRegistration.issueVotesTo(randomWallet, 110);
        assertEq(votes.balanceOf(randomWallet), 110);

        vm.prank(govMultisig);
        voterRegistration.revokeVotesFrom(randomWallet, 110);
        assertEq(votes.balanceOf(randomWallet), 0);
    }
}
