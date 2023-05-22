// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// The Governance Policy submits & activates instructions in a INSTR module

import {INSTRv1} from "src/modules/INSTR/INSTR.v1.sol";
import {VOTESv1} from "src/modules/VOTES/VOTES.v1.sol";

import {OlympusInstructions} from "src/modules/INSTR/OlympusInstructions.sol";
import {OlympusVotes} from "src/modules/VOTES/OlympusVotes.sol";

import "src/Kernel.sol";

/// @notice Parthenon, OlympusDAO's on-chain governance system.
/// @dev The Parthenon policy is also the Kernel's Executor.
contract Parthenon is Policy {
    // =========  EVENTS ========= //

    event ProposalSubmitted(uint256 proposalId, string title, string proposalURI);
    event ProposalActivated(uint256 proposalId, uint256 timestamp);
    event VotesCast(uint256 proposalId, address voter, bool approve, uint256 userVotes);
    event ProposalExecuted(uint256 proposalId);
    event CollateralReclaimed(uint256 proposalId, uint256 tokensReclaimed_);

    // =========  ERRORS ========= //

    error NotAuthorized();
    error UnableToActivate();
    error ProposalAlreadyActivated();

    error WarmupNotCompleted();
    error UserAlreadyVoted();
    error UserHasNoVotes();

    error ProposalIsNotActive();
    error DepositedAfterActivation();
    error PastVotingPeriod();

    error ExecutorNotSubmitter();
    error NotEnoughVotesToExecute();
    error ProposalAlreadyExecuted();
    error ExecutionTimelockStillActive();
    error ExecutionWindowExpired();
    error UnmetCollateralDuration();
    error CollateralAlreadyReturned();

    // =========  STATE ========= //

    struct ProposalMetadata {
        address submitter;
        uint256 submissionTimestamp;
        uint256 collateralAmt;
        uint256 activationTimestamp;
        uint256 totalRegisteredVotes;
        uint256 yesVotes;
        uint256 noVotes;
        bool isExecuted;
        bool isCollateralReturned;
        mapping(address => uint256) votesCastByUser;
    }

    /// @notice Return a proposal metadata object for a given proposal id.
    mapping(uint256 => ProposalMetadata) public getProposalMetadata;

    /// @notice The amount of VOTES a proposer needs to post in collateral in order to submit a proposal
    /// @dev    This number is expressed as a percentage of total supply in basis points: 500 = 5% of the supply
    uint256 public constant COLLATERAL_REQUIREMENT = 500;

    /// @notice The minimum amount of VOTES the proposer must post in collateral to submit
    uint256 public constant COLLATERAL_MINIMUM = 10e18;

    /// @notice Amount of time a wallet must wait after depositing before they can vote.
    uint256 public constant WARMUP_PERIOD = 1 minutes; // 30 minutes;

    /// @notice Amount of time a submitted proposal must exist before triggering activation.
    uint256 public constant ACTIVATION_TIMELOCK = 1 minutes; // 2 days;

    /// @notice Amount of time a submitted proposal can exist before activation can no longer be triggered.
    uint256 public constant ACTIVATION_DEADLINE = 3 minutes; // 3 days;

    /// @notice Net votes required to execute a proposal on chain as a percentage of total registered votes.
    uint256 public constant EXECUTION_THRESHOLD = 33;

    /// @notice The period of time a proposal has for voting
    uint256 public constant VOTING_PERIOD = 3 minutes; //3 days;

    /// @notice Required time for a proposal before it can be activated.
    /// @dev    This amount should be greater than 0 to prevent flash loan attacks.
    uint256 public constant EXECUTION_TIMELOCK = VOTING_PERIOD + 1 minutes; //2 days;

    /// @notice Amount of time after the proposal is activated (NOT AFTER PASSED) when it can be activated (otherwise proposal will go stale).
    /// @dev    This is inclusive of the voting period (so the deadline is really ~4 days, assuming a 3 day voting window).
    uint256 public constant EXECUTION_DEADLINE = VOTING_PERIOD + 1 weeks;

    /// @notice Amount of time a non-executed proposal must wait for the proposal to go through.
    /// @dev    This is inclusive of the voting period (so the deadline is really ~4 days, assuming a 3 day voting window).
    uint256 public constant COLLATERAL_DURATION = 16 weeks;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    INSTRv1 public INSTR;
    VOTESv1 public VOTES;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("INSTR");
        dependencies[1] = toKeycode("VOTES");

        INSTR = INSTRv1(getModuleAddress(dependencies[0]));
        VOTES = VOTESv1(getModuleAddress(dependencies[1]));
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](4);
        requests[0] = Permissions(toKeycode("INSTR"), INSTR.store.selector);
        requests[1] = Permissions(toKeycode("VOTES"), VOTES.resetActionTimestamp.selector);
        requests[2] = Permissions(toKeycode("VOTES"), VOTES.transfer.selector);
        requests[3] = Permissions(toKeycode("VOTES"), VOTES.transferFrom.selector);
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function _max(uint256 a, uint256 b) public pure returns (uint256) {
        return a > b ? a : b;
    }

    function submitProposal(
        Instruction[] calldata instructions_,
        string calldata title_,
        string calldata proposalURI_
    ) external {
        if (VOTES.lastDepositTimestamp(msg.sender) + WARMUP_PERIOD > block.timestamp) {
            revert WarmupNotCompleted();
        }
        // transfer 5% of the total vote supply in VOTES (min 10 VOTES)
        uint256 collateral = _max(
            (VOTES.totalSupply() * COLLATERAL_REQUIREMENT) / 10_000,
            COLLATERAL_MINIMUM
        );
        VOTES.transferFrom(msg.sender, address(this), collateral);

        uint256 proposalId = INSTR.store(instructions_);
        ProposalMetadata storage proposal = getProposalMetadata[proposalId];

        proposal.submitter = msg.sender;
        proposal.collateralAmt = collateral;
        proposal.submissionTimestamp = block.timestamp;

        VOTES.resetActionTimestamp(msg.sender);

        emit ProposalSubmitted(proposalId, title_, proposalURI_);
    }

    function activateProposal(uint256 proposalId_) external {
        ProposalMetadata storage proposal = getProposalMetadata[proposalId_];

        if (msg.sender != proposal.submitter) {
            revert NotAuthorized();
        }

        if (
            block.timestamp < proposal.submissionTimestamp + ACTIVATION_TIMELOCK ||
            block.timestamp > proposal.submissionTimestamp + ACTIVATION_DEADLINE
        ) {
            revert UnableToActivate();
        }

        if (proposal.activationTimestamp != 0) {
            revert ProposalAlreadyActivated();
        }

        proposal.activationTimestamp = block.timestamp;
        proposal.totalRegisteredVotes = VOTES.totalSupply();

        VOTES.resetActionTimestamp(msg.sender);

        emit ProposalActivated(proposalId_, block.timestamp);
    }

    function vote(uint256 proposalId_, bool approve_) external {
        ProposalMetadata storage proposal = getProposalMetadata[proposalId_];
        uint256 userVotes = VOTES.balanceOf(msg.sender);

        if (proposal.activationTimestamp == 0) {
            revert ProposalIsNotActive();
        }

        if (VOTES.lastDepositTimestamp(msg.sender) + WARMUP_PERIOD > block.timestamp) {
            revert WarmupNotCompleted();
        }

        if (VOTES.lastDepositTimestamp(msg.sender) > proposal.activationTimestamp) {
            revert DepositedAfterActivation();
        }

        if (proposal.votesCastByUser[msg.sender] > 0) {
            revert UserAlreadyVoted();
        }

        if (userVotes == 0) {
            revert UserHasNoVotes();
        }

        if (block.timestamp > proposal.activationTimestamp + VOTING_PERIOD) {
            revert PastVotingPeriod();
        }

        if (approve_) {
            proposal.yesVotes += userVotes;
        } else {
            proposal.noVotes += userVotes;
        }

        proposal.votesCastByUser[msg.sender] = userVotes;
        VOTES.resetActionTimestamp(msg.sender);

        emit VotesCast(proposalId_, msg.sender, approve_, userVotes);
    }

    function executeProposal(uint256 proposalId_) external {
        ProposalMetadata storage proposal = getProposalMetadata[proposalId_];

        if (msg.sender != proposal.submitter) {
            revert ExecutorNotSubmitter();
        }

        if (
            (proposal.yesVotes - proposal.noVotes) * 100 <
            proposal.totalRegisteredVotes * EXECUTION_THRESHOLD
        ) {
            revert NotEnoughVotesToExecute();
        }

        if (proposal.isExecuted) {
            revert ProposalAlreadyExecuted();
        }

        /// @dev    2 days after the voting period ends
        if (block.timestamp < proposal.activationTimestamp + EXECUTION_TIMELOCK) {
            revert ExecutionTimelockStillActive();
        }

        /// @dev    7 days after the voting period ends
        if (block.timestamp > proposal.activationTimestamp + EXECUTION_DEADLINE) {
            revert ExecutionWindowExpired();
        }

        proposal.isExecuted = true;

        Instruction[] memory instructions = INSTR.getInstructions(proposalId_);
        uint256 totalInstructions = instructions.length;

        for (uint256 step; step < totalInstructions; ) {
            kernel.executeAction(instructions[step].action, instructions[step].target);
            unchecked {
                ++step;
            }
        }

        VOTES.resetActionTimestamp(msg.sender);

        emit ProposalExecuted(proposalId_);
    }

    function reclaimCollateral(uint256 proposalId_) external {
        ProposalMetadata storage proposal = getProposalMetadata[proposalId_];

        if (
            !proposal.isExecuted &&
            block.timestamp < proposal.submissionTimestamp + COLLATERAL_DURATION
        ) {
            revert UnmetCollateralDuration();
        }

        if (proposal.isCollateralReturned) {
            revert CollateralAlreadyReturned();
        }

        if (msg.sender != proposal.submitter) {
            revert NotAuthorized();
        }

        proposal.isCollateralReturned = true;
        VOTES.transfer(proposal.submitter, proposal.collateralAmt);

        emit CollateralReclaimed(proposalId_, proposal.collateralAmt);
    }
}
