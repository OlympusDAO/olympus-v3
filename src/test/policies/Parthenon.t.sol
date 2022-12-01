// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {OlympusInstructions} from "src/modules/INSTR/OlympusInstructions.sol";
import {OlympusVotes} from "src/modules/VOTES/OlympusVotes.sol";
import {Parthenon} from "src/policies/Parthenon.sol";
import "src/Kernel.sol";

contract ParthenonTest is Test {
    using ModuleTestFixtureGenerator for OlympusVotes;

    event Transfer(address, address, uint256);

    Kernel internal kernel;

    OlympusInstructions internal INSTR;
    OlympusVotes internal VOTES;
    MockERC20 internal gOHM;

    Parthenon internal governance;
    Parthenon internal newProposedPolicy;

    address internal voter0;
    address internal voter1;
    address internal voter2;
    address internal voter3;
    address internal voter4;
    address internal voter5;

    address internal godmode;

    string internal defaultProposalName = "proposalName";
    string internal defaultProposalURI = "This is the proposal URI";

    function setUp() public {
        // Deploy BB token
        gOHM = new MockERC20("gOHM", "gOHM", 18);

        // Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        // Deploy modules
        INSTR = new OlympusInstructions(kernel);
        VOTES = new OlympusVotes(kernel, gOHM);

        // Deploy policies
        governance = new Parthenon(kernel);
        newProposedPolicy = new Parthenon(kernel);

        // Install modules
        kernel.executeAction(Actions.InstallModule, address(INSTR));
        kernel.executeAction(Actions.InstallModule, address(VOTES));

        // Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(governance));

        // Generate test fixture policy addresses with different authorizations
        voter1 = VOTES.generateGodmodeFixture(type(OlympusVotes).name);
        kernel.executeAction(Actions.ActivatePolicy, voter1);

        voter2 = VOTES.generateGodmodeFixture(type(OlympusVotes).name);
        kernel.executeAction(Actions.ActivatePolicy, voter2);

        voter3 = VOTES.generateGodmodeFixture(type(OlympusVotes).name);
        kernel.executeAction(Actions.ActivatePolicy, voter3);

        voter4 = VOTES.generateGodmodeFixture(type(OlympusVotes).name);
        kernel.executeAction(Actions.ActivatePolicy, voter4);

        voter5 = VOTES.generateGodmodeFixture(type(OlympusVotes).name);
        kernel.executeAction(Actions.ActivatePolicy, voter5);

        // Change executor
        kernel.executeAction(Actions.ChangeExecutor, address(governance));

        // mint gOHM to voters
        gOHM.mint(voter1, 1_000_000 * 1e18);
        gOHM.mint(voter2, 1_000_000 * 1e18);
        gOHM.mint(voter3, 1_000_000 * 1e18);
        gOHM.mint(voter4, 1_000_000 * 1e18);
        gOHM.mint(voter5, 1_000_000 * 1e18);

        // mint VOTES to voters
        vm.startPrank(voter1);
        gOHM.approve(address(VOTES), type(uint256).max);
        VOTES.mint(100_000 * 1e18, voter1);
        vm.stopPrank();

        vm.startPrank(voter2);
        gOHM.approve(address(VOTES), type(uint256).max);
        VOTES.mint(200_000 * 1e18, voter2);
        vm.stopPrank();

        vm.startPrank(voter3);
        gOHM.approve(address(VOTES), type(uint256).max);
        VOTES.mint(300_000 * 1e18, voter3);
        vm.stopPrank();

        vm.startPrank(voter4);
        gOHM.approve(address(VOTES), type(uint256).max);
        VOTES.mint(400_000 * 1e18, voter4);
        vm.stopPrank();

        vm.startPrank(voter5);
        gOHM.approve(address(VOTES), type(uint256).max);
        VOTES.mint(500_000 * 1e18, voter5);
        vm.stopPrank();

        // move past warmup period so users can propose and vote
        vm.warp(block.timestamp + governance.WARMUP_PERIOD() + 1);
    }

    function testCorrectness_submitProposal() public {
        uint256 submissionTimestamp = block.timestamp;

        // since voter1 always submits grab voter1s balance before submitting
        uint256 voter1Balance = VOTES.balanceOf(voter1);

        uint256 collateral = _calculateCollateral();

        uint256 proposalId = _submitUnactivatedProposal();

        // assert collateral was taken from voter1
        assertEq(VOTES.balanceOf(voter1), voter1Balance - collateral);

        (
            address submitter,
            uint256 submissionTimestamp_,
            uint256 collateralAmt,
            uint256 activationTimestamp,
            uint256 totalRegisteredVotes,
            uint256 yesVotes,
            uint256 noVotes,
            bool isExecuted,
            bool isCollateralReturned
        ) = governance.getProposalMetadata(proposalId);

        // first proposal is id 1
        assertEq(proposalId, 1);

        // assert proposal data is accurate
        assertEq(submitter, voter1);
        assertEq(submissionTimestamp_, submissionTimestamp);
        assertEq(collateralAmt, collateral);
        assertEq(activationTimestamp, 0);
        assertEq(totalRegisteredVotes, 0);
        assertEq(yesVotes, 0);
        assertEq(noVotes, 0);
        assertEq(isExecuted, false);
        assertEq(isCollateralReturned, false);

        // assert vesting reset
        assertEq(VOTES.lastActionTimestamp(voter1), block.timestamp);
    }

    function testRevert_submitProposal_WarmupNotCompleted() public {
        vm.warp(block.timestamp - governance.WARMUP_PERIOD() - 1);

        // create valid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.ActivatePolicy, address(newProposedPolicy));

        // attempt to submit proposal as voter1 (1/15 votes)
        vm.prank(voter1);
        bytes memory err = abi.encodeWithSignature("WarmupNotCompleted()");
        vm.expectRevert(err);
        governance.submitProposal(instructions, defaultProposalName, defaultProposalURI);
    }

    function testCorrectness_activateProposal() public {
        uint256 submissionTimestamp = block.timestamp;
        uint256 collateralAmt = _calculateCollateral();
        uint256 proposalId = _submitUnactivatedProposal();

        // fast forward past activation lock
        vm.warp(block.timestamp + governance.ACTIVATION_TIMELOCK() + 1);
        uint256 activationTimestamp = block.timestamp;
        vm.prank(voter1);
        governance.activateProposal(proposalId);

        (
            address submitter,
            uint256 submissionTimestamp_,
            uint256 collateralAmt_,
            uint256 activationTimestamp_,
            uint256 totalRegisteredVotes,
            uint256 yesVotes,
            uint256 noVotes,
            bool isExecuted,
            bool isCollateralReturned
        ) = governance.getProposalMetadata(proposalId);

        assertEq(submitter, voter1);
        assertEq(submissionTimestamp_, submissionTimestamp);
        assertEq(collateralAmt_, collateralAmt);
        assertEq(activationTimestamp_, activationTimestamp);
        assertEq(totalRegisteredVotes, VOTES.totalSupply());
        assertEq(yesVotes, 0);
        assertEq(noVotes, 0);
        assertEq(isExecuted, false);
        assertEq(isCollateralReturned, false);

        // assert vesting reset
        assertEq(VOTES.lastActionTimestamp(voter1), block.timestamp);
    }

    function testRevert_activateProposal_UnableToActivate() public {
        uint256 submissionTime = block.timestamp;
        uint256 proposalId = _submitUnactivatedProposal();
        bytes memory err = abi.encodeWithSignature("UnableToActivate()");

        // fast forward to just before activation timelock
        vm.warp(submissionTime + governance.ACTIVATION_TIMELOCK() - 1);
        vm.prank(voter1);
        vm.expectRevert(err);
        governance.activateProposal(proposalId);

        // fast forward to just after the activation deadline
        vm.warp(submissionTime + governance.ACTIVATION_DEADLINE() + 1);
        vm.prank(voter1);
        vm.expectRevert(err);
        governance.activateProposal(proposalId);
    }

    function testRevert_activateProposal_ProposalAlreadyActivated() public {
        uint256 proposalId = _submitProposal();
        bytes memory err = abi.encodeWithSignature("ProposalAlreadyActivated()");

        vm.prank(voter1);
        vm.expectRevert(err);
        governance.activateProposal(proposalId);
    }

    function testRevert_activateProposal_NotAuthorized() public {
        uint256 proposalId = _submitUnactivatedProposal();
        bytes memory err = abi.encodeWithSignature("NotAuthorized()");

        vm.prank(voter2);
        vm.expectRevert(err);
        governance.activateProposal(proposalId);
    }

    function testCorrectness_vote() public {
        uint256 yesVotes;
        uint256 noVotes;
        uint256 proposalId = _submitProposal();

        // cast voter1's vote
        vm.prank(voter1);
        governance.vote(proposalId, true);

        (, , , , , yesVotes, noVotes, , ) = governance.getProposalMetadata(proposalId);

        // assert voter1's vote was counted
        // and 0 no votes
        // and lastActionTimestamp was updated
        assertEq(yesVotes, VOTES.balanceOf(voter1));
        assertEq(noVotes, 0);
        assertEq(VOTES.lastActionTimestamp(voter1), block.timestamp);

        // redeem 1 of voter2's 2 votes
        vm.prank(voter2);
        VOTES.redeem(10_000 * 1e18, voter2, voter2);
        vm.warp(block.timestamp + governance.WARMUP_PERIOD() + 1);

        // cast voter2's vote.
        // voter2 should only receive 1 vote now instead of 2
        vm.prank(voter2);
        governance.vote(proposalId, false);
        (, , , , , yesVotes, noVotes, , ) = governance.getProposalMetadata(proposalId);

        // assert there is 1 yes vote from voter1
        // and 1 no vote from voter2
        // and lastActionTimestamp was updated
        assertEq(yesVotes, VOTES.balanceOf(voter1));
        assertEq(noVotes, VOTES.balanceOf(voter2));
        assertEq(VOTES.lastActionTimestamp(voter2), block.timestamp);

        // cast voter3's vote
        vm.prank(voter3);
        governance.vote(proposalId, false);
        (, , , , , yesVotes, noVotes, , ) = governance.getProposalMetadata(proposalId);

        // assert there is 1 yes votes from voter1
        // and 4 no votes (voter2(1) + voter3(3))
        // and lastActionTimestamp was updated
        assertEq(yesVotes, VOTES.balanceOf(voter1));
        assertEq(noVotes, VOTES.balanceOf(voter2) + VOTES.balanceOf(voter3));
        assertEq(VOTES.lastActionTimestamp(voter3), block.timestamp);

        // cast voter4's vote
        vm.prank(voter4);
        governance.vote(proposalId, true);
        (, , , , , yesVotes, noVotes, , ) = governance.getProposalMetadata(proposalId);

        // assert there is 5 yes votes (voter1(1) + voter4(4))
        // and 4 no votes (voter2(1) + voter3(3))
        // and lastActionTimestamp was updated
        assertEq(yesVotes, VOTES.balanceOf(voter1) + VOTES.balanceOf(voter4));
        assertEq(noVotes, VOTES.balanceOf(voter2) + VOTES.balanceOf(voter3));
        assertEq(VOTES.lastActionTimestamp(voter4), block.timestamp);

        // cast voter5's vote
        vm.prank(voter5);
        governance.vote(proposalId, true);
        (, , , , , yesVotes, noVotes, , ) = governance.getProposalMetadata(proposalId);

        // assert there is 10 yes votes (voter1(1) + voter4(4) + voter5(5))
        // and 4 no votes (voter2(1) + voter3(3))
        // and lastActionTimestamp was updated
        assertEq(
            yesVotes,
            VOTES.balanceOf(voter1) + VOTES.balanceOf(voter4) + VOTES.balanceOf(voter5)
        );
        assertEq(noVotes, VOTES.balanceOf(voter2) + VOTES.balanceOf(voter3));
        assertEq(VOTES.lastActionTimestamp(voter5), block.timestamp);
    }

    function testRevert_vote_WarmupNotCompleted() public {
        uint256 proposalId = _submitProposal();

        vm.warp(
            block.timestamp - governance.WARMUP_PERIOD() - governance.ACTIVATION_TIMELOCK() - 1
        );

        // attempt to cast voter1's vote
        vm.prank(voter1);
        bytes memory err = abi.encodeWithSignature("WarmupNotCompleted()");
        vm.expectRevert(err);
        governance.vote(proposalId, true);
    }

    function testCorrectness_executeProposal() public {
        uint256 proposalId = _submitProposal();

        // vote
        vm.prank(voter1);
        governance.vote(proposalId, true);

        vm.prank(voter2);
        governance.vote(proposalId, true);

        vm.prank(voter3);
        governance.vote(proposalId, true);

        vm.prank(voter4);
        governance.vote(proposalId, true);

        vm.prank(voter5);
        governance.vote(proposalId, true);

        // execute
        vm.warp(block.timestamp + governance.EXECUTION_TIMELOCK());
        vm.prank(voter1);
        governance.executeProposal(proposalId);

        // assert proposal was executed
        (, , , , , , , bool isExecuted, ) = governance.getProposalMetadata(proposalId);
        assertEq(isExecuted, true);

        // assert proposal was activated in kernel
        uint256 index = kernel.getPolicyIndex(newProposedPolicy);
        assertTrue(index != 0);
        assertEq(address(kernel.activePolicies(index)), address(newProposedPolicy));
    }

    function testRevert_executeProposal_ExecutorNotSubmitter() public {
        uint256 proposalId = _submitProposal();

        // vote
        vm.prank(voter5);
        governance.vote(proposalId, true);

        // attempt to execute as non submittor
        bytes memory err = abi.encodeWithSignature("ExecutorNotSubmitter()");
        vm.warp(block.timestamp + governance.EXECUTION_TIMELOCK());
        vm.prank(voter5);
        vm.expectRevert(err);
        governance.executeProposal(proposalId);
    }

    function testRevert_executeProposal_NotEnoughVotesToExecute() public {
        uint256 proposalId = _submitProposal();

        // vote
        // 8 yes votes to 7 no votes
        // proposal doesnt meet minimum threshold of net votes (33%)
        vm.prank(voter1);
        governance.vote(proposalId, false);

        vm.prank(voter2);
        governance.vote(proposalId, false);

        vm.prank(voter3);
        governance.vote(proposalId, true);

        vm.prank(voter4);
        governance.vote(proposalId, false);

        vm.prank(voter5);
        governance.vote(proposalId, true);

        // attempt to execute w/o quorum
        bytes memory err = abi.encodeWithSignature("NotEnoughVotesToExecute()");
        vm.warp(block.timestamp + governance.EXECUTION_TIMELOCK());
        vm.prank(voter1);
        vm.expectRevert(err);
        governance.executeProposal(proposalId);
    }

    function testRevert_executeProposal_ProposalAlreadyExecuted() public {
        uint256 proposalId = _submitProposal();

        // vote
        vm.prank(voter5);
        governance.vote(proposalId, true);

        // execute
        vm.warp(block.timestamp + governance.EXECUTION_TIMELOCK());
        vm.prank(voter1);
        governance.executeProposal(proposalId);

        // attempt to execute twice
        bytes memory err = abi.encodeWithSignature("ProposalAlreadyExecuted()");
        vm.prank(voter1);
        vm.expectRevert(err);
        governance.executeProposal(proposalId);
    }

    function testRevert_executeProposal_ExecutionTimelockStillActive() public {
        uint256 proposalId = _submitProposal();

        // vote
        vm.prank(voter5);
        governance.vote(proposalId, true);

        // attempt to execute early
        bytes memory err = abi.encodeWithSignature("ExecutionTimelockStillActive()");
        vm.prank(voter1);
        vm.expectRevert(err);
        governance.executeProposal(proposalId);
    }

    function testRevert_executeProposal_ExecutionWindowExpired() public {
        uint256 proposalId = _submitProposal();

        // vote
        vm.prank(voter5);
        governance.vote(proposalId, true);

        // attempt to execute after deadline
        bytes memory err = abi.encodeWithSignature("ExecutionWindowExpired()");
        vm.warp(block.timestamp + governance.EXECUTION_DEADLINE() + 1);
        vm.prank(voter1);
        vm.expectRevert(err);
        governance.executeProposal(proposalId);
    }

    function testCorrectness_reclaimCollateral() public {
        uint256 submissionTimestamp = block.timestamp;
        uint256 collateralAmt = _calculateCollateral();
        uint256 proposalId = _submitAndExecuteProposal();

        // reclaim
        uint256 voter1BalanceBefore = VOTES.balanceOf(voter1);
        // vm.warp(submissionTimestamp + governance.COLLATERAL_DURATION());
        vm.prank(voter1);
        governance.reclaimCollateral(proposalId);

        (, , , , , , , , bool isCollateralReturned) = governance.getProposalMetadata(proposalId);

        assertEq(isCollateralReturned, true);

        assertEq(VOTES.balanceOf(voter1), voter1BalanceBefore + collateralAmt);
    }

    function testRevert_reclaimCollateral_UnmetCollateralDuration() public {
        uint256 submissionTimestamp = block.timestamp;
        bytes memory err = abi.encodeWithSignature("UnmetCollateralDuration()");
        uint256 proposalId = _submitProposal();

        vm.warp(submissionTimestamp + governance.COLLATERAL_DURATION() - 1);
        vm.prank(voter1);
        vm.expectRevert(err);
        governance.reclaimCollateral(proposalId);
    }

    function testRevert_reclaimCollateral_CollateralAlreadyReturned() public {
        uint256 submissionTimestamp = block.timestamp;
        bytes memory err = abi.encodeWithSignature("CollateralAlreadyReturned()");
        uint256 proposalId = _submitAndExecuteProposal();

        vm.warp(submissionTimestamp + governance.COLLATERAL_DURATION());
        vm.prank(voter1);
        governance.reclaimCollateral(proposalId);

        vm.prank(voter1);
        vm.expectRevert(err);
        governance.reclaimCollateral(proposalId);
    }

    function testRevert_reclaimCollateral_NotAuthorized() public {
        uint256 submissionTimestamp = block.timestamp;
        bytes memory err = abi.encodeWithSignature("NotAuthorized()");
        uint256 proposalId = _submitAndExecuteProposal();

        vm.warp(submissionTimestamp + governance.COLLATERAL_DURATION());
        vm.prank(voter2);
        vm.expectRevert(err);
        governance.reclaimCollateral(proposalId);
    }

    ////////////////////////////////////////////////////////////////////////
    //                             HELPERS                               //
    //////////////////////////////////////////////////////////////////////

    function _submitProposal() internal returns (uint256 proposalId) {
        // create valid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.ActivatePolicy, address(newProposedPolicy));

        // submit proposal as voter1 (1/15 votes)
        vm.startPrank(voter1);
        VOTES.approve(address(governance), _calculateCollateral());
        governance.submitProposal(instructions, defaultProposalName, defaultProposalURI);
        vm.stopPrank();

        proposalId = INSTR.totalInstructions();

        // fast forward past activation lock
        vm.warp(block.timestamp + governance.ACTIVATION_TIMELOCK() + 1);
        vm.prank(voter1);
        governance.activateProposal(proposalId);
    }

    function _submitUnactivatedProposal() internal returns (uint256 proposalId) {
        // create valid instructions
        Instruction[] memory instructions = new Instruction[](1);
        instructions[0] = Instruction(Actions.ActivatePolicy, address(newProposedPolicy));

        // submit proposal as voter1 (1/15 votes)
        vm.startPrank(voter1);
        VOTES.approve(address(governance), type(uint256).max);
        governance.submitProposal(instructions, defaultProposalName, defaultProposalURI);
        vm.stopPrank();

        return INSTR.totalInstructions();
    }

    function _submitAndExecuteProposal() internal returns (uint256 proposalId) {
        proposalId = _submitProposal();

        // vote
        vm.prank(voter1);
        governance.vote(proposalId, true);

        vm.prank(voter2);
        governance.vote(proposalId, true);

        vm.prank(voter3);
        governance.vote(proposalId, true);

        vm.prank(voter4);
        governance.vote(proposalId, true);

        vm.prank(voter5);
        governance.vote(proposalId, true);

        // execute
        vm.warp(block.timestamp + governance.EXECUTION_TIMELOCK());
        vm.prank(voter1);
        governance.executeProposal(proposalId);
    }

    function _calculateCollateral() internal view returns (uint256 collateralAmt) {
        uint256 baseCollateral = (VOTES.totalSupply() * governance.COLLATERAL_REQUIREMENT()) /
            10_000;
        uint256 minCollateral = governance.COLLATERAL_MINIMUM();
        collateralAmt = baseCollateral > minCollateral ? baseCollateral : minCollateral;
    }
}
