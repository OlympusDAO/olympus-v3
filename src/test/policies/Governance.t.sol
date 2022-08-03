// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test-utils/UserFactory.sol";

import "src/Kernel.sol";

import {OlympusInstructions} from "modules/INSTR.sol";
import {OlympusVotes} from "modules/VOTES.sol";

import "policies/Governance.sol";
import {VoterRegistration} from "policies/VoterRegistration.sol";

contract GovernanceTest is Test {
    UserFactory public userCreator;
    address internal voter0;
    address internal voter1;
    address internal voter2;
    address internal voter3;
    address internal voter4;
    address internal voter5;

    address internal govMultisig;
    address internal newProposedPolicy;

    Kernel internal kernel;

    OlympusInstructions internal instructions;
    OlympusVotes internal votes;

    OlympusGovernance internal governance;
    VoterRegistration internal voterRegistration;

    event InstructionsStored(uint256);
    event ProposalSubmitted(uint256 instructionsId);
    event ProposalEndorsed(uint256 instructionsId, address voter, uint256 amount);
    event ProposalActivated(uint256 instructionsId, uint256 timestamp);
    event WalletVoted(uint256 instructionsId, address voter, bool for_, uint256 userVotes);
    event ProposalExecuted(uint256 instructionsId);
    event Transfer(address indexed, address indexed, uint256);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();

        /// Create Voters
        address[] memory users = userCreator.create(7);
        voter0 = users[0];
        voter1 = users[1];
        voter2 = users[2];
        voter3 = users[3];
        voter4 = users[4];
        voter5 = users[5];
        govMultisig = users[6];

        /// Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        /// Deploy modules
        instructions = new OlympusInstructions(kernel);
        votes = new OlympusVotes(kernel);

        /// Deploy policies
        governance = new OlympusGovernance(kernel);
        voterRegistration = new VoterRegistration(kernel);
        newProposedPolicy = address(new OlympusGovernance(kernel));

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(instructions));
        kernel.executeAction(Actions.InstallModule, address(votes));

        /// Approve policies`
        kernel.executeAction(Actions.ActivatePolicy, address(governance));
        kernel.executeAction(Actions.ActivatePolicy, address(voterRegistration));

        // Change executor
        kernel.executeAction(Actions.ChangeExecutor, address(governance));

        /// Configure access control
        kernel.grantRole(toRole("voter_admin"), govMultisig);

        // Mint tokens to users and treasury for testing
        vm.startPrank(govMultisig);
        voterRegistration.issueVotesTo(voter1, 1);
        voterRegistration.issueVotesTo(voter2, 2);
        voterRegistration.issueVotesTo(voter3, 3);
        voterRegistration.issueVotesTo(voter4, 4);
        voterRegistration.issueVotesTo(voter5, 5);
        vm.stopPrank();

        vm.prank(voter1);
        votes.approve(address(governance), type(uint256).max);
        vm.prank(voter2);
        votes.approve(address(governance), type(uint256).max);
        vm.prank(voter3);
        votes.approve(address(governance), type(uint256).max);
        vm.prank(voter4);
        votes.approve(address(governance), type(uint256).max);
        vm.prank(voter5);
        votes.approve(address(governance), type(uint256).max);
    }

    ////////////////////////////////
    //    SUBMITTING PROPOSALS    //
    ////////////////////////////////

    function _submitProposal() internal {
        // create valid instructions
        Instruction[] memory instructions_ = new Instruction[](1);
        instructions_[0] = Instruction(Actions.ActivatePolicy, address(newProposedPolicy));

        // submit proposal as voter1 (1/15 votes)
        vm.prank(voter1);
        governance.submitProposal(instructions_, "proposalName");
    }

    function testRevert_NotEnoughVotesToPropose() public {
        Instruction[] memory instructions_ = new Instruction[](1);
        instructions_[0] = Instruction(Actions.ActivatePolicy, address(governance));

        vm.expectRevert(NotEnoughVotesToPropose.selector);

        // submit proposal as invalid voter (0/15 votes)
        vm.prank(voter0);
        governance.submitProposal(instructions_, "proposalName");
    }

    function testEvent_ProposalSubmitted() public {
        Instruction[] memory instructions_ = new Instruction[](1);
        instructions_[0] = Instruction(Actions.ActivatePolicy, address(governance));

        vm.expectEmit(true, true, true, true);
        emit ProposalSubmitted(1);

        vm.prank(voter1);
        governance.submitProposal(instructions_, "proposalName");
    }

    function testCorrectness_SuccessfullySubmitProposal() public {
        Instruction[] memory instructions_ = new Instruction[](1);
        instructions_[0] = Instruction(Actions.ActivatePolicy, address(governance));

        vm.expectEmit(true, true, true, true);
        emit InstructionsStored(1);

        vm.prank(voter1);
        governance.submitProposal(instructions_, "proposalName");

        // get the proposal metadata
        ProposalMetadata memory pls = governance.getMetadata(1);
        assertEq(pls.submissionTimestamp, 51 * 365 * 24 * 60 * 60);
        assertEq(pls.proposalName, "proposalName");
        assertEq(pls.proposer, voter1);
    }

    ////////////////////////////////
    //     ENDORSING PROPOSALS    //
    ////////////////////////////////

    function testRevert_CannotEndorseNullProposal() public {
        vm.expectRevert(CannotEndorseNullProposal.selector);

        vm.prank(voter1);
        governance.endorseProposal(0);
    }

    function testRevert_CannotEndorseInvalidProposal() public {
        vm.expectRevert(CannotEndorseInvalidProposal.selector);

        // endorse a proposal that doesn't exist
        vm.prank(voter1);
        governance.endorseProposal(1);
    }

    function testEvent_ProposalEndorsed() public {
        _submitProposal();

        vm.expectEmit(true, true, true, true);
        emit ProposalEndorsed(1, voter1, 1);

        vm.prank(voter1);
        governance.endorseProposal(1);
    }

    function testCorrectness_UserEndorsesProposal() public {
        _submitProposal();

        // endorse 1 vote as voter1
        vm.prank(voter1);
        governance.endorseProposal(1);

        // check that the contract state is updated correctly
        assertEq(governance.userEndorsementsForProposal(1, voter1), 1);
        assertEq(governance.totalEndorsementsForProposal(1), 1);

        // endorse 2 votes as voter2
        vm.prank(voter2);
        governance.endorseProposal(1);

        // check that the contract state is updated conrrectly
        assertEq(governance.totalEndorsementsForProposal(1), 3);

        // issue 5 more votes to voter1
        vm.prank(govMultisig);
        voterRegistration.issueVotesTo(voter1, 5);

        // reendorse proposal as voter1 with 6 total votes
        vm.prank(voter1);
        governance.endorseProposal(1);

        // check that the contract state is updated conrrectly
        assertEq(governance.userEndorsementsForProposal(1, voter1), 6);
        assertEq(governance.totalEndorsementsForProposal(1), 8);
    }

    ////////////////////////////////
    //    ACTIVATING PROPOSALS    //
    ////////////////////////////////

    function _createEndorsedProposal() public {
        _submitProposal();

        // give 3/15 endorsements to the submitted proposal (20%)
        vm.prank(voter1);
        governance.endorseProposal(1);

        vm.prank(voter2);
        governance.endorseProposal(1);
    }

    function testRevert_NotAuthorizedToActivateProposal() public {
        _createEndorsedProposal();

        vm.expectRevert(NotAuthorizedToActivateProposal.selector);

        // call function from not the proposer's wallet
        vm.prank(voter2);
        governance.activateProposal(1);
    }

    function testRevert_SubmittedProposalHasExpired() public {
        _submitProposal();

        // fast forward 2 weeks and 1 second
        vm.warp(block.timestamp + 2 weeks + 1);

        vm.expectRevert(SubmittedProposalHasExpired.selector);

        vm.prank(voter1);
        governance.activateProposal(1);
    }

    function testRevert_NotEnoughEndorsementsToActivateProposal() public {
        _submitProposal();

        // give the proposal 2/3 necessary endorsements
        vm.prank(voter2);
        governance.endorseProposal(1);

        vm.expectRevert(NotEnoughEndorsementsToActivateProposal.selector);

        vm.prank(voter1);
        governance.activateProposal(1);
    }

    function testRevert_ProposalAlreadyActivated() public {
        _createEndorsedProposal();

        vm.prank(voter1);
        governance.activateProposal(1);

        vm.expectRevert(ProposalAlreadyActivated.selector);

        // activate the proposal again
        vm.prank(voter1);
        governance.activateProposal(1);
    }

    function testRevert_ActiveProposalNotExpired() public {
        _createEndorsedProposal();
        vm.prank(voter1);
        governance.activateProposal(1);

        // submit & endorse a second proposal
        _submitProposal();
        vm.prank(voter1);
        governance.endorseProposal(2);
        vm.prank(voter2);
        governance.endorseProposal(2);

        vm.expectRevert(ActiveProposalNotExpired.selector);

        // try to activate the second proposal
        vm.prank(voter1);
        governance.activateProposal(2);
    }

    function testEvent_ProposalActivated() public {
        _createEndorsedProposal();

        vm.expectEmit(true, true, true, true);
        emit ProposalActivated(1, block.timestamp);

        vm.prank(voter1);
        governance.activateProposal(1);
    }

    function testCorrectness_ProposerActivatesSubmittedProposal() public {
        _createEndorsedProposal();
        vm.prank(voter1);
        governance.activateProposal(1);

        // check that the active proposal data is correct
        ActivatedProposal memory activeProposal = governance.getActiveProposal();

        assertEq(activeProposal.instructionsId, 1);
        assertEq(activeProposal.activationTimestamp, block.timestamp);
        assertTrue(governance.proposalHasBeenActivated(1));

        // submit another valid proposal and endorse it to 20% (3/15 total votes)
        _submitProposal();
        vm.prank(voter1);
        governance.endorseProposal(2);
        vm.prank(voter2);
        governance.endorseProposal(2);

        // expire the first proposal by moving forward 1 week + 1 second
        vm.warp(block.timestamp + 1 weeks + 1);

        // activate the second proposal
        vm.prank(voter1);
        governance.activateProposal(2);

        // check that the new proposal has been activated
        activeProposal = governance.getActiveProposal();

        assertEq(activeProposal.instructionsId, 2);
        assertTrue(governance.proposalHasBeenActivated(2));
    }

    ////////////////////////////////
    //    VOTING ON EXECTUTION    //
    ////////////////////////////////

    function _createActiveProposal() public {
        _createEndorsedProposal();
        vm.prank(voter1);
        governance.activateProposal(1);
    }

    function testRevert_NoActiveProposalDetected() public {
        vm.expectRevert(NoActiveProposalDetected.selector);

        vm.prank(voter1);
        governance.vote(true);
    }

    function testRevert_UserAlreadyVoted() public {
        _createActiveProposal();

        vm.prank(voter1);
        governance.vote(true);

        vm.expectRevert(UserAlreadyVoted.selector);

        // try to vote again
        vm.prank(voter1);
        governance.vote(true);
    }

    function testEvent_WalletVoted() public {
        _createActiveProposal();

        vm.expectEmit(true, true, true, true);
        emit WalletVoted(1, voter1, false, 1);

        vm.prank(voter1);
        governance.vote(false);
    }

    function testCorrectness_UserVotesForProposal() public {
        _createActiveProposal();

        vm.expectEmit(true, true, true, true);
        emit Transfer(voter1, address(governance), 1);

        vm.prank(voter1);
        governance.vote(true);

        // check voting state
        assertEq(governance.userVotesForProposal(1, voter1), 1);
        assertEq(governance.yesVotesForProposal(1), 1);

        // test token transfer
        assertEq(votes.balanceOf(address(voter1)), 0);
        assertEq(votes.balanceOf(address(governance)), 1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(voter2, address(governance), 2);

        vm.prank(voter2);
        governance.vote(false);

        // check voting state
        assertEq(governance.userVotesForProposal(1, voter2), 2);
        assertEq(governance.noVotesForProposal(1), 2);

        // test token transfer
        assertEq(votes.balanceOf(address(voter2)), 0);
        assertEq(votes.balanceOf(address(governance)), 3);
    }

    ////////////////////////////////
    //   EXECUTING INSTRUCTIONS   //
    ////////////////////////////////

    function _createApprovedInstructions() public {
        _createActiveProposal();
        vm.prank(voter5);
        governance.vote(true);
    }

    function testRevert_NotEnoughVotesToExecute() public {
        // submit, endorse, and activate a proposal
        _createActiveProposal();

        // cast 4 net votes for the proposal (5 needed)
        vm.prank(voter4);
        governance.vote(true);

        vm.prank(voter3);
        governance.vote(true);

        vm.prank(voter2);
        governance.vote(false);

        vm.prank(voter1);
        governance.vote(false);

        vm.expectRevert(NotEnoughVotesToExecute.selector);
        governance.executeProposal();
    }

    function testRevert_ExecutionTimelockStillActive() public {
        _createApprovedInstructions();

        vm.expectRevert(ExecutionTimelockStillActive.selector);
        governance.executeProposal();
    }

    function testEvent_ProposalExecuted() public {
        _createApprovedInstructions();

        // move 3 days + 1 second into the future
        vm.warp(block.timestamp + 3 days + 1);

        vm.expectEmit(true, true, true, true);
        emit ProposalExecuted(1);

        governance.executeProposal();
    }

    function testCorrectness_executeInstructions() public {
        _createApprovedInstructions();

        // move 3 days + 1 second into the future
        vm.warp(block.timestamp + 3 days + 1);

        vm.expectEmit(true, true, true, true);
        emit ProposalExecuted(1);

        governance.executeProposal();

        // check that the proposal is no longer active
        ActivatedProposal memory activeProposal = governance.getActiveProposal();

        assertEq(activeProposal.instructionsId, 0);
        assertEq(activeProposal.activationTimestamp, 0);

        // check that the proposed contracts are approved in the kernel
        assertTrue(Policy(newProposedPolicy).isActive());
    }

    ////////////////////////////////
    //   RECLAIMING VOTE TOKENS   //
    ////////////////////////////////

    function _executeProposal() public {
        _createApprovedInstructions();
        vm.warp(block.timestamp + 3 days + 1);
        governance.executeProposal();
        assertEq(votes.balanceOf(voter5), 0);
    }

    function testRevert_CannotReclaimZeroVotes() public {
        _executeProposal();
        vm.expectRevert(CannotReclaimZeroVotes.selector);

        vm.prank(voter4);
        governance.reclaimVotes(1);
    }

    function testRevert_CannotReclaimTokensForActiveVote() public {
        _createApprovedInstructions();

        vm.expectRevert(CannotReclaimTokensForActiveVote.selector);

        vm.prank(voter5);
        governance.reclaimVotes(1);
    }

    function testRevert_VotingTokensAlreadyReclaimed() public {
        _executeProposal();

        vm.prank(voter5);
        governance.reclaimVotes(1);

        vm.expectRevert(VotingTokensAlreadyReclaimed.selector);

        vm.prank(voter5);
        governance.reclaimVotes(1);
    }

    function testCorrectness_SuccessfullyReclaimVotes() public {
        _executeProposal();

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(governance), voter5, 5);

        vm.prank(voter5);
        governance.reclaimVotes(1);

        // check that the claim has been recorded
        assertTrue(governance.tokenClaimsForProposal(1, voter5));

        // check that the voting tokens are successfully returned to the user from the contract
        assertEq(votes.balanceOf(voter5), 5);
        assertEq(votes.balanceOf(address(governance)), 0);
    }
}
