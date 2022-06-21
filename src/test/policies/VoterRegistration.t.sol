// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test-utils/UserFactory.sol";

import {Kernel, Actions} from "../../Kernel.sol";

import {OlympusVotes} from "../../modules/VOTES.sol";
import {OlympusAuthority} from "../../modules/AUTHR.sol";

import {MockAuthGiver} from "../mocks/MockAuthGiver.sol";
import {VoterRegistration} from "../../policies/VoterRegistration.sol";

contract VoterRegistrationTest is Test {
    UserFactory public userCreator;
    address internal randomWallet;
    address internal govMultisig;

    Kernel internal kernel;

    OlympusVotes internal votes;
    OlympusAuthority internal authr;
    MockAuthGiver internal authGiver;
    VoterRegistration internal voterRegistration;

    function setUp() public {
        userCreator = new UserFactory();

        /// Create Voters
        address[] memory users = userCreator.create(2);
        randomWallet = users[0];
        govMultisig = users[1];

        /// Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        /// Deploy modules (some mocks)
        votes = new OlympusVotes(kernel);
        authr = new OlympusAuthority(kernel);

        /// Deploy policies
        authGiver = new MockAuthGiver(kernel);
        voterRegistration = new VoterRegistration(kernel);

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(votes));
        kernel.executeAction(Actions.InstallModule, address(authr));

        /// Approve policies`
        kernel.executeAction(Actions.ApprovePolicy, address(voterRegistration));
        kernel.executeAction(Actions.ApprovePolicy, address(authGiver));

        /// Role 0 = Issuer
        authGiver.setRoleCapability(
            uint8(0),
            address(voterRegistration),
            voterRegistration.issueVotesTo.selector
        );

        authGiver.setRoleCapability(
            uint8(0),
            address(voterRegistration),
            voterRegistration.revokeVotesFrom.selector
        );

        /// Give issuer role to govMultisig
        authGiver.setUserRole(govMultisig, uint8(0));
    }

    ////////////////////////////////
    //   ISSUING/REVOKING VOTES   //
    ////////////////////////////////

    function testRevert_WhenCalledByRandomWallet() public {
        vm.expectRevert("UNAUTHORIZED");
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
