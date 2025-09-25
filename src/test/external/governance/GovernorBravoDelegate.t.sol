// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {console2} from "forge-std/console2.sol";

import {MockGohm} from "src/test/mocks/OlympusMocks.sol";

import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {Actions, Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";

import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {Timelock} from "src/external/governance/Timelock.sol";

contract ReentrancyExploit {
    using Address for address;

    GovernorBravoDelegator public governorBravoDelegator;
    Kernel public kernel;

    uint256 public depth = 0;
    uint256 public attackProposalId;

    function createProposal(
        GovernorBravoDelegator _governorBravoDelegator,
        Kernel _kernel
    ) external {
        governorBravoDelegator = _governorBravoDelegator;
        kernel = _kernel;

        // Proposal 1
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Proposal 1";

        targets[0] = address(kernel);
        values[0] = 0;
        signatures[0] = "";
        calldatas[0] = abi.encodeWithSelector(
            kernel.executeAction.selector,
            Actions.ActivatePolicy,
            address(this)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));
        attackProposalId = proposalId;
    }

    function attack() external {
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", attackProposalId)
        );
        console2.log("Activated", attackProposalId);
    }

    function configureDependencies() external returns (Keycode[] memory dependencies) {
        console2.log("reentrancy");

        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", attackProposalId)
        );
        console2.log("Activated", attackProposalId);

        return dependencies;
    }
}

contract GovernorBravoDelegateTest is Test {
    using Address for address;

    address internal vetoGuardian;
    address internal alice;
    uint256 internal alicePk;

    MockGohm internal gohm;

    Kernel internal kernel;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;
    RolesAdmin internal rolesAdmin;
    TreasuryCustodian internal custodian;

    GovernorBravoDelegator internal governorBravoDelegator;
    GovernorBravoDelegate internal governorBravo;
    Timelock internal timelock;

    ReentrancyExploit internal reentrancyExploit;

    // Re-declare events
    event VoteCast(
        address indexed voter,
        uint256 proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );

    function setUp() public {
        // Set up users
        {
            address[] memory users = (new UserFactory()).create(1);
            vetoGuardian = users[0];

            (alice, alicePk) = makeAddrAndKey("alice");
        }

        // Create token
        {
            gohm = new MockGohm(100e9);
        }

        // Create kernel, modules, and policies
        {
            kernel = new Kernel();
            TRSRY = new OlympusTreasury(kernel); // This will be installed by the governor later
            ROLES = new OlympusRoles(kernel);
            rolesAdmin = new RolesAdmin(kernel);
            custodian = new TreasuryCustodian(kernel);
        }

        // Create governance contracts
        {
            governorBravo = new GovernorBravoDelegate();
            timelock = new Timelock(address(this), 1 days);

            // SETS VETO GUARDIAN AS GOVERNOR BRAVO ADMIN
            vm.prank(vetoGuardian);
            governorBravoDelegator = new GovernorBravoDelegator(
                address(timelock),
                address(gohm),
                address(kernel),
                vetoGuardian,
                address(governorBravo),
                50400,
                21600,
                7200,
                17_000
            );
        }

        // Create exploit contract
        {
            reentrancyExploit = new ReentrancyExploit();
        }

        // Configure governance contracts
        {
            timelock.setFirstAdmin(address(governorBravoDelegator));
            // THIS SHOULD BE DONE VIA PROPOSAL
            vm.prank(address(timelock));
            address(governorBravoDelegator).functionCall(
                abi.encodeWithSignature(
                    "_setModuleRiskLevel(bytes5,bool)",
                    toKeycode("TRSRY"),
                    true
                )
            );
        }

        // Set up modules and policies
        {
            kernel.executeAction(Actions.InstallModule, address(ROLES));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ChangeExecutor, address(timelock));

            rolesAdmin.pushNewAdmin(address(timelock));
        }

        // Set up gOHM
        {
            gohm.mint(address(0), 890_000e18);
            gohm.mint(alice, 110_000e18); // Alice has >10% of the supply
            gohm.checkpointVotes(alice);
        }
    }

    // --- Core Proposal Tests ----------------------------------------------------

    // []   propose
    //      [X] cannot be called if the total supply drops
    //      [X] reverts if proposer doesn't have enough gOHM
    //      [X] reverts if proposal data lengths are zero
    //      [X] reverts if proposal data lengths don't match
    //      [X] reverts if proposal data lengths are greater than set max
    //      [X] reverts if another proposal from the proposer is pending or active
    //      [X] captures correct quroum votes value at time of proposal creation
    //      [X] cannot dodge high risk quorum check (removed for now)
    //      [X] captures high risk quorum level if interacting with high risk module (removed for now)
    //      [X] captures high risk quorum (other kernel actions) (removed for now)
    //      [X] captures high risk quorum (self actions) (removed for now)
    //      [X] captures high risk quorum (timelock actions) (removed for now)
    //      [X] quorum doesn't change for gohm minted after proposal activation
    //      [X] captures correct proposal threshold value at time of proposal creation
    //      [] creates correct new proposal object
    //      [X] sets proposer's latest proposal id

    function testCorrectness_proposeRevertsIfTotalSupplyIsTooLow() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Emergency_SupplyTooLow()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
    }

    function testCorrectness_proposeRevertsBelowThreshold() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        targets[0] = address(this);
        values[0] = 0;
        signatures[0] = "test()";
        calldatas[0] = abi.encodeWithSignature("test()");

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_ThresholdNotMet()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
    }

    function testCorrectness_proposeRevertsIfDataLengthsAreZero() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        string[] memory signatures = new string[](0);
        bytes[] memory calldatas = new bytes[](0);
        string memory description = "Test Proposal";

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_NoActions()");
        vm.expectRevert(err);

        vm.prank(alice); // Alice is above proposal threshold
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
    }

    function testCorrectness_proposeRevertsIfDataLengthMismatch() public {
        // Case #1
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_LengthMismatch()");
        vm.expectRevert(err);

        vm.startPrank(alice); // Alice is above proposal threshold
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );

        // Case #2
        targets = new address[](1);
        values = new uint256[](2);
        signatures = new string[](1);
        calldatas = new bytes[](1);

        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );

        // Case #3
        targets = new address[](1);
        values = new uint256[](2);
        signatures = new string[](3);
        calldatas = new bytes[](1);

        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
    }

    function testCorrectness_proposeRevertsIfActionsGreaterThanMax(uint256 operations_) public {
        vm.assume(operations_ > 15);
        if (operations_ > 50) {
            operations_ = 50; // Put a reasonable max on it so we're not testing memory limit or gas limit errors, those will revert regardless
        }

        address[] memory targets = new address[](operations_);
        uint256[] memory values = new uint256[](operations_);
        string[] memory signatures = new string[](operations_);
        bytes[] memory calldatas = new bytes[](operations_);
        string memory description = "Test Proposal";

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_TooManyActions()");
        vm.expectRevert(err);

        vm.prank(alice); // Alice is above proposal threshold
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
    }

    function testCorrectness_proposeRevertsIfProposerAlreadyHasPendingOrActiveProposal() public {
        // Create pending proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        vm.startPrank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        // Try to create another proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_AlreadyPending()");
        vm.expectRevert(err);

        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );

        // Warp forward so that the pending proposal is now active
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Try to create another proposal
        err = abi.encodeWithSignature("GovernorBravo_Proposal_AlreadyActive()");
        vm.expectRevert(err);

        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
    }

    function testCorrectness_proposeCapturesCorrectQuorum() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        // Warp forward so that the pending proposal is now active
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalQuorum(uint256)", proposalId)
        );
        uint256 quorum = abi.decode(data, (uint256));
        assertEq(quorum, 200_000e18);
    }

    // function testCorrectness_proposeCannotAvoidHighRiskQuorumCheck() public {
    //     // Activate TRSRY
    //     vm.prank(address(timelock));
    //     kernel.executeAction(Actions.InstallModule, address(TRSRY));

    //     // Create proposal that should be flagged as high risk
    //     address[] memory targets = new address[](1);
    //     uint256[] memory values = new uint256[](1);
    //     string[] memory signatures = new string[](1);
    //     bytes[] memory calldatas = new bytes[](1);
    //     string memory description = "High Risk Proposal";

    //     // Append extra bytes to calldata to make it not high risk
    //     bytes memory actualCall = abi.encodeWithSelector(
    //         kernel.executeAction.selector,
    //         Actions.ActivatePolicy,
    //         address(custodian)
    //     );
    //     bytes memory paddedCall = abi.encodePacked(actualCall, new bytes(100));

    //     targets[0] = address(kernel);
    //     values[0] = 0;
    //     signatures[0] = "";
    //     calldatas[0] = paddedCall;

    //     vm.prank(alice);
    //     bytes memory data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature(
    //             "propose(address[],uint256[],string[],bytes[],string)",
    //             targets,
    //             values,
    //             signatures,
    //             calldatas,
    //             description
    //         )
    //     );
    //     uint256 proposalId = abi.decode(data, (uint256));

    //     // Warp forward so that the proposal is active
    //     vm.roll(block.number + 21601);

    //     bytes memory err = abi.encodeWithSignature("GovernorBravo_InvalidCalldata()");
    //     vm.expectRevert(err);
    //     address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("activate(uint256)", proposalId)
    //     );
    // }

    // function testCorrectness_proposeCapturesCorrectQuorum_highRisk() public {
    //     // Activate TRSRY
    //     vm.prank(address(timelock));
    //     kernel.executeAction(Actions.InstallModule, address(TRSRY));

    //     // Create proposal that should be flagged as high risk
    //     address[] memory targets = new address[](1);
    //     uint256[] memory values = new uint256[](1);
    //     string[] memory signatures = new string[](1);
    //     bytes[] memory calldatas = new bytes[](1);
    //     string memory description = "High Risk Proposal";

    //     targets[0] = address(kernel);
    //     values[0] = 0;
    //     signatures[0] = "";
    //     calldatas[0] = abi.encodeWithSelector(
    //         kernel.executeAction.selector,
    //         Actions.ActivatePolicy,
    //         address(custodian)
    //     );

    //     vm.prank(alice);
    //     bytes memory data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature(
    //             "propose(address[],uint256[],string[],bytes[],string)",
    //             targets,
    //             values,
    //             signatures,
    //             calldatas,
    //             description
    //         )
    //     );
    //     uint256 proposalId = abi.decode(data, (uint256));

    //     // Warp forward so that the pending proposal is now active
    //     vm.roll(block.number + 21601);
    //     address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("activate(uint256)", proposalId)
    //     );

    //     data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("getProposalQuorum(uint256)", proposalId)
    //     );
    //     uint256 quorum = abi.decode(data, (uint256));
    //     assertEq(quorum, 200_000e18);
    // }

    // function testCorrectness_proposeCapturesCorrectQuorum_highRisk_kernelActions(
    //     bool executor_
    // ) public {
    //     // Create proposal that should be flagged as high risk
    //     address[] memory targets = new address[](1);
    //     uint256[] memory values = new uint256[](1);
    //     string[] memory signatures = new string[](1);
    //     bytes[] memory calldatas = new bytes[](1);
    //     string memory description = "High Risk Proposal";

    //     targets[0] = address(kernel);
    //     values[0] = 0;
    //     signatures[0] = "";
    //     calldatas[0] = abi.encodeWithSelector(
    //         kernel.executeAction.selector,
    //         executor_ ? Actions.ChangeExecutor : Actions.MigrateKernel,
    //         address(1)
    //     );

    //     vm.prank(alice);
    //     bytes memory data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature(
    //             "propose(address[],uint256[],string[],bytes[],string)",
    //             targets,
    //             values,
    //             signatures,
    //             calldatas,
    //             description
    //         )
    //     );
    //     uint256 proposalId = abi.decode(data, (uint256));

    //     // Warp forward so that the pending proposal is now active
    //     vm.roll(block.number + 21601);
    //     address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("activate(uint256)", proposalId)
    //     );

    //     data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("getProposalQuorum(uint256)", proposalId)
    //     );
    //     uint256 quorum = abi.decode(data, (uint256));
    //     assertEq(quorum, 200_000e18);
    // }

    // function testCorrectness_proposeCapturesCorrectQuorum_highRisk_selfActions() public {
    //     // Create proposal that should be flagged as high risk
    //     address[] memory targets = new address[](1);
    //     uint256[] memory values = new uint256[](1);
    //     string[] memory signatures = new string[](1);
    //     bytes[] memory calldatas = new bytes[](1);
    //     string memory description = "High Risk Proposal";

    //     targets[0] = address(governorBravoDelegator);
    //     values[0] = 0;
    //     signatures[0] = "";
    //     calldatas[0] = abi.encodeWithSelector(governorBravo._setPendingAdmin.selector, address(1));

    //     vm.prank(alice);
    //     bytes memory data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature(
    //             "propose(address[],uint256[],string[],bytes[],string)",
    //             targets,
    //             values,
    //             signatures,
    //             calldatas,
    //             description
    //         )
    //     );
    //     uint256 proposalId = abi.decode(data, (uint256));

    //     // Warp forward so that the pending proposal is now active
    //     vm.roll(block.number + 21601);
    //     address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("activate(uint256)", proposalId)
    //     );

    //     data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("getProposalQuorum(uint256)", proposalId)
    //     );
    //     uint256 quorum = abi.decode(data, (uint256));
    //     assertEq(quorum, 200_000e18);
    // }

    // function testCorrectness_proposeCapturesCorrectQuorum_highRisk_timelock() public {
    //     // Create proposal that should be flagged as high risk
    //     address[] memory targets = new address[](1);
    //     uint256[] memory values = new uint256[](1);
    //     string[] memory signatures = new string[](1);
    //     bytes[] memory calldatas = new bytes[](1);
    //     string memory description = "High Risk Proposal";

    //     targets[0] = address(timelock);
    //     values[0] = 0;
    //     signatures[0] = "";
    //     calldatas[0] = abi.encodeWithSelector(timelock.setPendingAdmin.selector, address(1));

    //     vm.prank(alice);
    //     bytes memory data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature(
    //             "propose(address[],uint256[],string[],bytes[],string)",
    //             targets,
    //             values,
    //             signatures,
    //             calldatas,
    //             description
    //         )
    //     );
    //     uint256 proposalId = abi.decode(data, (uint256));

    //     // Warp forward so that the proposal is active
    //     vm.roll(block.number + 21601);
    //     address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("activate(uint256)", proposalId)
    //     );

    //     data = address(governorBravoDelegator).functionCall(
    //         abi.encodeWithSignature("getProposalQuorum(uint256)", proposalId)
    //     );
    //     uint256 quorum = abi.decode(data, (uint256));
    //     assertEq(quorum, 200_000e18);
    // }

    function testCorrectness_proposeDoesntChangeQuorumAfterActivation(uint256 mintAmount_) public {
        vm.assume(mintAmount_ <= 100_000_000_000e18);

        // Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        // Warp forward so that the proposal is active
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Mint enough gOHM to pass quorum
        gohm.mint(address(0), mintAmount_);

        // Warp forward so that the proposal is complete
        vm.roll(block.number + 50401);

        // Validate that quorum is still 200k
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalQuorum(uint256)", proposalId)
        );
        uint256 quorum = abi.decode(data, (uint256));
        assertEq(quorum, 200_000e18);
    }

    function testCorrectness_proposeCapturesCorrectProposalThreshold() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalThreshold(uint256)", proposalId)
        );
        uint256 threshold = abi.decode(data, (uint256));
        assertEq(threshold, 170e18);
    }

    function testCorrectness_proposeCreatesCorrectProposalObject() public {
        // TODO: it's a nightmare pulling this out of the contract when using raw calls and decoding
    }

    function testCorrectness_proposeSetsProposerLatestProposalId() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Test Proposal";

        // Mint enough gOHM to pass proposal threshold
        gohm.mint(alice, 100_000e18);
        gohm.checkpointVotes(alice);

        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("latestProposalIds(address)", alice)
        );
        uint256 latestProposalId = abi.decode(data, (uint256));
        assertEq(proposalId, latestProposalId);
    }

    // [X]   emergencyPropose
    //      [X] can only be called if the total supply drops
    //      [X] can only be called by veto guardian
    //      [X] reverts if proposal data lengths are zero
    //      [X] reverts if proposal data lengths don't match
    //      [X] reverts if proposal data lengths are greater than set max
    //      [X] stores proposal data

    function testCorrectness_emergencyProposeRevertsIfSupplyAboveThreshold(uint256 supply_) public {
        vm.assume(supply_ >= 1_000e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);

        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        // Mint supply_
        gohm.mint(address(0), supply_);

        // Try to create proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_NotEmergency()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                targets,
                values,
                signatures,
                calldatas
            )
        );
    }

    function testCorrectness_emergencyProposeRevertsIfNotCalledByVetoGuardian(
        uint256 supply_
    ) public {
        vm.assume(supply_ < 1_000e18);

        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        // Mint supply_
        gohm.mint(address(0), supply_);

        // Try to create proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyVetoGuardian()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                new address[](0),
                new uint256[](0),
                new string[](0),
                new bytes[](0)
            )
        );
    }

    function testCorrectness_emergencyProposeRevertsIfDataLengthsAreZero() public {
        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        // Try to create proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_NoActions()");
        vm.expectRevert(err);

        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                new address[](0),
                new uint256[](0),
                new string[](0),
                new bytes[](0)
            )
        );
    }

    function testCorrectness_emergencyProposeRevertsIfDataLengthMismatch() public {
        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        // Case #1
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);

        // Try to create proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_LengthMismatch()");
        vm.expectRevert(err);

        vm.startPrank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                targets,
                values,
                signatures,
                calldatas
            )
        );

        // Case #2
        targets = new address[](1);
        values = new uint256[](2);
        signatures = new string[](1);
        calldatas = new bytes[](1);

        // Try to create proposal
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                targets,
                values,
                signatures,
                calldatas
            )
        );

        // Case #3
        targets = new address[](1);
        values = new uint256[](2);
        signatures = new string[](3);
        calldatas = new bytes[](1);

        // Try to create proposal
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                targets,
                values,
                signatures,
                calldatas
            )
        );
    }

    function testCorrectness_emergencyProposeRevertsIfActionsGreaterThanMax(
        uint256 operations_
    ) public {
        vm.assume(operations_ > 15);
        if (operations_ > 50) {
            operations_ = 50; // Put a reasonable max on it so we're not testing memory limit or gas limit errors, those will revert regardless
        }

        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        address[] memory targets = new address[](operations_);
        uint256[] memory values = new uint256[](operations_);
        string[] memory signatures = new string[](operations_);
        bytes[] memory calldatas = new bytes[](operations_);

        // Try to create proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_TooManyActions()");
        vm.expectRevert(err);

        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                targets,
                values,
                signatures,
                calldatas
            )
        );
    }

    function testCorrectness_emergencyProposeStoresProposalData() public {
        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(this);
        values[0] = 100;
        signatures[0] = "";
        calldatas[0] = abi.encodeWithSignature("test()");

        vm.prank(vetoGuardian);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                targets,
                values,
                signatures,
                calldatas
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getActions(uint256)", proposalId)
        );
        (
            address[] memory actualTargets,
            uint256[] memory actualValues,
            string[] memory actualSignatures,
            bytes[] memory actualCalldatas
        ) = abi.decode(data, (address[], uint256[], string[], bytes[]));

        assertEq(actualTargets.length, 1);
        assertEq(actualValues.length, 1);
        assertEq(actualSignatures.length, 1);
        assertEq(actualCalldatas.length, 1);

        assertEq(actualTargets[0], targets[0]);
        assertEq(actualValues[0], values[0]);
        assertEq(actualSignatures[0], signatures[0]);
        assertEq(actualCalldatas[0], calldatas[0]);

        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint256 state = abi.decode(data, (uint256));
        assertEq(state, 9); // Emergency
    }

    // [X]   activate
    //      [X] cannot be reentered (excluded for now)
    //      [X] reverts if after grace period

    // function testCorrectness_activateCannotBeReentered() public {
    //     // Mint gOHM to reentrancy exploit contract
    //     gohm.burn(alice, gohm.balanceOf(alice));
    //     gohm.mint(address(reentrancyExploit), 110_000e18);
    //     gohm.checkpointVotes(address(reentrancyExploit));

    //     // Set up reentrancy exploit contract
    //     reentrancyExploit.createProposal(governorBravoDelegator, kernel);

    //     // Warp forward so that the proposal can be activated
    //     vm.roll(block.number + 21601);

    //     bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_Closed()");
    //     vm.expectRevert(err);
    //     reentrancyExploit.attack();
    // }

    function testCorrectness_activateRevertsIfAfterGracePeriod() public {
        // Create proposal
        uint256 proposalId = _createTestProposal(1);

        // Warp forward so that the unactivated proposal is expired
        vm.roll(block.number + 21601 + 17280);

        // Try to activate proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_Closed()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Check that state is expired
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 6); // Expired
    }

    // [X]   queue
    //   [X] when proposal is not emergency
    //      [X] reverts if proposal is canceled
    //      [X] reverts if voting has not finished for proposal (proposal pending or active)
    //      [X] reverts if proposal has been defeated (quorum not met)
    //      [X] reverts if proposal has been defeated (quorum met but no majority)
    //      [X] reverts if proposal has already been queued
    //      [X] reverts if proposal has already been executed
    //      [X] reverts if proposal has been vetoed
    //      [X] reverts if proposer has fallen below proposal threshold
    //      [X] reverts if an action is already queued on the timelock
    //      [X] queues if an action is not already queued on the timelock
    //      [X] updates proposal object eta (this also updates proposal state to queued)
    //      [X] when supply drops below emergency threshold
    //        [X] reverts if sender is not veto guardian

    function _createTestProposal(uint256 actions_) internal returns (uint256) {
        // Create action set
        address[] memory targets = new address[](actions_);
        uint256[] memory values = new uint256[](actions_);
        string[] memory signatures = new string[](actions_);
        bytes[] memory calldatas = new bytes[](actions_);
        string memory description = "Test Proposal";

        // Create proposal
        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));
        return proposalId;
    }

    function testCorrectness_queueRevertsIfProposalIsCanceled() public {
        uint256 proposalId = _createTestProposal(1);

        // Cancel proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );

        // Try to queue proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_FailedProposal()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfProposalVotingHasNotConcluded() public {
        uint256 proposalId = _createTestProposal(1);

        // Try to queue pending proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_FailedProposal()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward so proposal is active
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Try to queue active proposal
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfProposalDefeated_quorumNotMet() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp forward so voting period is complete without any votes (quorum not met)
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );
        vm.roll(block.number + 50401);

        // Try to queue proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_FailedProposal()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfProposalDefeated_quorumMet_noMajority(
        address forVoter_,
        address againstVoter_,
        uint256 forVotes_,
        uint256 againstVotes_
    ) public {
        vm.assume(forVoter_ != againstVoter_);
        vm.assume(
            (againstVotes_ > 0 || forVotes_ > 0) && // Make sure we don't divide by zero
                againstVotes_ < 100_000_000_000e18 &&
                forVotes_ < 100_000_000_000e18 &&
                ((againstVotes_ * 100_000) / (forVotes_ + againstVotes_)) > 45_000 &&
                forVotes_ + againstVotes_ > 200_000e18
        );

        uint256 proposalId = _createTestProposal(1);

        // Make sure forVoter_ and againstVoter_ have no voting power to start
        gohm.burn(forVoter_, gohm.balanceOf(forVoter_));
        gohm.burn(againstVoter_, gohm.balanceOf(againstVoter_));

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set forVoter's voting power
        gohm.mint(forVoter_, forVotes_);
        gohm.checkpointVotes(forVoter_);

        // Set againstVoter's voting power
        gohm.mint(againstVoter_, againstVotes_);
        gohm.checkpointVotes(againstVoter_);

        // Vote for proposal
        vm.prank(forVoter_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Vote against proposal
        vm.prank(againstVoter_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 0)
        );

        // Warp forward so voting period is complete (quorum met but no majority)
        vm.roll(block.number + 50401);

        // Try to queue proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_FailedProposal()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfProposalAlreadyQueued() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set zero address's voting power
        gohm.checkpointVotes(address(0));

        // Vote for proposal
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period is complete (quorum met and majority)
        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Try to queue proposal again
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_FailedProposal()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfProposalAlreadyExecuted() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set zero address's voting power
        gohm.checkpointVotes(address(0));

        // Vote for proposal
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period is complete (quorum met and majority)
        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Attempt to queue proposal again
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_FailedProposal()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfProposalVetoed() public {
        uint256 proposalId = _createTestProposal(1);

        // Veto proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        // Try to queue proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_FailedProposal()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfProposerBelowThreshold() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set zero address's voting power
        gohm.checkpointVotes(address(0));

        // Vote for proposal
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period is complete (quorum met and majority) and warp forward so that the timelock grace period has expired
        vm.roll(block.number + 50401);

        // Burn alice's gOHM so she is below proposal threshold
        gohm.burn(alice, 110_000e18);
        gohm.checkpointVotes(alice);

        // Try to queue proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_BelowThreshold()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queueRevertsIfActionAlreadyExistsOnTimelock() public {
        // Create proposal from alice
        uint256 proposalId = _createTestProposal(1);

        // Create proposal from zero address with same actions
        gohm.checkpointVotes(address(0));

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period is complete (quorum met and majority) and warp forward so that the timelock grace period has expired
        vm.roll(block.number + 50401);

        // Artificially queue an action on the timelock
        uint256 eta = block.timestamp + timelock.delay();
        vm.prank(address(governorBravoDelegator));
        timelock.queueTransaction(proposalId, address(0), 0, "", "", eta);

        // Try to queue proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Queue_AlreadyQueued()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queue_supplyDrops_onlyVetoGuardian(address rando) public {
        vm.assume(rando != vetoGuardian);

        uint256 proposalId = _createTestProposal(1);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set zero address's voting power
        gohm.checkpointVotes(address(0));

        // Vote for proposal
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period is complete (quorum met and majority) and warp forward so that the timelock grace period has expired
        vm.roll(block.number + 50401);

        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        // Try to queue proposal as non vetoGuardian, expect revert
        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyVetoGuardian()");
        vm.expectRevert(err);
        vm.prank(rando);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Queue the proposal as vetoGuardian
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_queue() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set zero address's voting power
        gohm.checkpointVotes(address(0));

        // Vote for proposal
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period is complete (quorum met and majority) and warp forward so that the timelock grace period has expired
        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        uint256 eta = block.timestamp + 1 days;

        // Validate that queue was successful
        bytes memory stateData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(stateData, (uint8));
        assertEq(state, 5);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        bool queuedOnTimelock = timelock.queuedTransactions(
            keccak256(
                abi.encode(proposalId, targets[0], values[0], signatures[0], calldatas[0], eta)
            )
        );
        assertEq(queuedOnTimelock, true);
    }

    function testCorrectness_queueUpdatesProposalObjectEta() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set zero address's voting power
        gohm.checkpointVotes(address(0));

        // Vote for proposal
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period is complete (quorum met and majority) and warp forward so that the timelock grace period has expired
        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        uint256 eta = block.timestamp + 1 days;

        bytes memory etaData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalEta(uint256)", proposalId)
        );
        uint256 eta_ = abi.decode(etaData, (uint256));
        assertEq(eta_, eta);
    }

    // [X]   queue
    //   [X] when proposal is emergency
    //      [X] reverts if sender is not veto guardian
    //      [X] reverts if proposal is vetoed
    //      [X] reverts if proposal is already executed
    //      [X] when supply increases back above threshold
    //         [X] it's still treated as an emergency proposal
    //      [X] queues transactions

    function _createEmergencyProposal(uint256 supply_) internal returns (uint256) {
        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        console2.log("Supply: %s", gohm.totalSupply());

        // Create action set to Activate Treasury
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(kernel);
        values[0] = 0;
        signatures[0] = "executeAction(uint8,address)";
        calldatas[0] = abi.encode(0, address(TRSRY));

        // Mint supply_
        gohm.mint(address(0), supply_);
        console2.log("Supply: %s", gohm.totalSupply());

        // Create proposal
        vm.prank(vetoGuardian);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "emergencyPropose(address[],uint256[],string[],bytes[])",
                targets,
                values,
                signatures,
                calldatas
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));
        return proposalId;
    }

    function testCorrectness_emergencyQueueRevertsIfNotCalledByVetoGuardian(
        uint256 supply_
    ) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        // Try to create proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyVetoGuardian()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_emergencyQueue(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        // Queue proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        uint256 eta = block.timestamp + 1 days;

        // Validate that queue was successful
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(kernel);
        values[0] = 0;
        signatures[0] = "executeAction(uint8,address)";
        calldatas[0] = abi.encode(0, address(TRSRY));

        bool queuedOnTimelock = timelock.queuedTransactions(
            keccak256(
                abi.encode(proposalId, targets[0], values[0], signatures[0], calldatas[0], eta)
            )
        );
        assertEq(queuedOnTimelock, true);
    }

    function testCorrectness_emergencyQueue_supplyIncreases(
        uint256 supply_,
        address rando_
    ) public {
        vm.assume(supply_ < 1_000e18);
        vm.assume(rando_ != vetoGuardian);

        uint256 proposalId = _createEmergencyProposal(supply_);

        // Mint more gOHM to bring supply back above threshold
        gohm.mint(rando_, 1_000e18);

        // Try to queue proposal as non vetoGuardian, expect revert
        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyVetoGuardian()");
        vm.expectRevert(err);
        vm.prank(rando_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Queue the proposal as vetoGuardian
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_emergencyQueue_revertsIfVetoed(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        // Veto proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        // Try to queue proposal as vetoGuardian, expect revert
        bytes memory err = abi.encodeWithSignature("GovernorBravo_NotEmergency()");
        vm.expectRevert(err);
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    function testCorrectness_emergencyQueue_revertsIfExecuted(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        // Queue the proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Try to queue proposal again, expect revert
        bytes memory err = abi.encodeWithSignature("GovernorBravo_NotEmergency()");
        vm.expectRevert(err);
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );
    }

    // [X]   execute
    //   [X] when proposal is not emergency
    //      [X] reverts if proposal is not queued
    //      [X] reverts if proposal has been already executed
    //      [X] reverts if proposal has been canceled
    //      [X] reverts if proposal has been vetoed
    //      [X] reverts if proposer has fallen below proposal threshold
    //      [X] updates proposal object executed state
    //      [X] executes transactions (case 1) (Kernel action)
    //      [X] executes transactions (case 2) (Policy action)
    //      [X] executes transactions (case 3) (Multiple actions)
    //      [X] when supply drops below emergency threshold
    //         [X] reverts if sender is not veto guardian

    function _queueProposal(uint256 actions_) internal returns (uint256) {
        uint256 proposalId = _createTestProposal(actions_);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Set zero address's voting power
        gohm.checkpointVotes(address(0));

        // Vote for proposal and warp to end of voting period
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );
        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        return proposalId;
    }

    function testCorrectness_executeRevertsIfProposalNotQueued() public {
        uint256 proposalId = _createTestProposal(1);

        // Try to execute proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Execute_NotQueued()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Try to execute proposal
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Vote for proposal and warp so voting has ended
        gohm.checkpointVotes(address(0));

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );
        vm.roll(block.number + 50401);

        // Try to execute proposal
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_executeRevertsIfProposalAlreadyExecuted() public {
        uint256 proposalId = _queueProposal(1);

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Try to execute proposal again
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Execute_NotQueued()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_executeRevertsIfProposalHasBeenCanceled() public {
        uint256 proposalId = _queueProposal(1);

        // Cancel proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );

        // Try to execute proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Execute_NotQueued()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_executeRevertsIfProposalHasBeenVetoed() public {
        uint256 proposalId = _queueProposal(1);

        // Veto proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        // Try to execute proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Execute_NotQueued()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_executeRevertsIfProposerBelowThreshold() public {
        uint256 proposalId = _queueProposal(1);

        // Burn alice's gOHM so she is below proposal threshold
        gohm.burn(alice, 110_000e18);
        gohm.checkpointVotes(alice);

        // Try to execute proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Execute_BelowThreshold()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_executeUpdatesProposalObjectExecutedState() public {
        uint256 proposalId = _queueProposal(1);

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        bytes memory stateData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(stateData, (uint8));
        assertEq(state, 7);
    }

    function testCorrectness_execute_case1() public {
        // Create action set to install the TRSRY on Kernel
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Activate Treasury";

        targets[0] = address(kernel);
        values[0] = 0;
        signatures[0] = "executeAction(uint8,address)";
        calldatas[0] = abi.encode(0, address(TRSRY));

        // Create proposal
        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal and warp so voting has ended
        gohm.checkpointVotes(address(0));

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        Module moduleForTRSRY = kernel.getModuleForKeycode(toKeycode("TRSRY"));
        assertEq(address(moduleForTRSRY), address(0));

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        moduleForTRSRY = kernel.getModuleForKeycode(toKeycode("TRSRY"));
        assertEq(address(moduleForTRSRY), address(TRSRY));
    }

    function testCorrectness_execute_case2() public {
        // Create action set to pull RolesAdmin admin access
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Pull RolesAdmin Admin Access";

        targets[0] = address(rolesAdmin);
        values[0] = 0;
        signatures[0] = "pullNewAdmin()";
        calldatas[0] = "";

        // Create proposal
        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal and warp so voting has ended
        gohm.checkpointVotes(address(0));

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Check initial state
        assertEq(rolesAdmin.admin(), address(this));
        assertEq(rolesAdmin.newAdmin(), address(timelock));

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Check final state
        assertEq(rolesAdmin.admin(), address(timelock));
        assertEq(rolesAdmin.newAdmin(), address(0));
    }

    function testCorrectness_execute_case3() public {
        // Create action set
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        string[] memory signatures = new string[](3);
        bytes[] memory calldatas = new bytes[](3);
        string memory description = "Test Proposal";

        // Action 1: Install TRSRY on Kernel
        targets[0] = address(kernel);
        values[0] = 0;
        signatures[0] = "executeAction(uint8,address)";
        calldatas[0] = abi.encode(0, address(TRSRY));

        // Action 2: Pull RolesAdmin admin access
        targets[1] = address(rolesAdmin);
        values[1] = 0;
        signatures[1] = "pullNewAdmin()";
        calldatas[1] = "";

        // Action 3: Grant role "cooler_overseer" to Timelock
        targets[2] = address(rolesAdmin);
        values[2] = 0;
        signatures[2] = "grantRole(bytes32,address)";
        calldatas[2] = abi.encode(bytes32("cooler_overseer"), address(timelock));

        // Create proposal
        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal and warp so voting has ended
        gohm.checkpointVotes(address(0));

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Check initial state
        Module moduleForTRSRY = kernel.getModuleForKeycode(toKeycode("TRSRY"));
        bool hasRole = ROLES.hasRole(address(timelock), bytes32("cooler_overseer"));
        assertEq(address(moduleForTRSRY), address(0));
        assertEq(rolesAdmin.admin(), address(this));
        assertEq(rolesAdmin.newAdmin(), address(timelock));
        assertEq(hasRole, false);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Check final state
        moduleForTRSRY = kernel.getModuleForKeycode(toKeycode("TRSRY"));
        hasRole = ROLES.hasRole(address(timelock), bytes32("cooler_overseer"));
        assertEq(address(moduleForTRSRY), address(TRSRY));
        assertEq(rolesAdmin.admin(), address(timelock));
        assertEq(rolesAdmin.newAdmin(), address(0));
        assertEq(hasRole, true);
    }

    function testCorrectness_execute_supplyDrops_onlyVetoGuardian(address rando_) public {
        vm.assume(rando_ != vetoGuardian);

        uint256 proposalId = _queueProposal(1);

        // Burn all gOHM
        gohm.burn(address(0), gohm.balanceOf(address(0)));
        gohm.burn(alice, gohm.balanceOf(alice));

        // Warp forward past timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // mint rando address enough gOHM to propose
        gohm.mint(rando_, 11e18);

        // Try to execute proposal as non vetoGuardian, expect revert
        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyVetoGuardian()");
        vm.expectRevert(err);
        vm.prank(rando_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Execute the proposal as vetoGuardian
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    // [X]    execute
    //   [X] when proposal is emergency
    //      [X] reverts if not called by veto guardian
    //      [X] reverts if vetoed
    //      [X] reverts if already executed
    //      [X] executes transactions

    function testCorrectness_emergencyExecuteRevertsIfNotCalledByVetoGuardian(
        uint256 supply_
    ) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Try to execute proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyVetoGuardian()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_emergencyExecute_revertsIfVetoed(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        // Try to execute proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_NotEmergency()");
        vm.expectRevert(err);
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_emergencyExecute_revertsIfAlreadyExecuted(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        // Queue the proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute the proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Try to execute proposal again, expect revert
        bytes memory err = abi.encodeWithSignature("GovernorBravo_NotEmergency()");
        vm.expectRevert(err);
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );
    }

    function testCorrectness_emergencyExecute(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(supply_);

        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Check final state
        Module moduleForTRSRY = kernel.getModuleForKeycode(toKeycode("TRSRY"));
        assertEq(address(moduleForTRSRY), address(TRSRY));
    }

    // [X]   cancel
    //      [X] reverts if proposal is already executed
    //      [X] doesn't revert if proposer is caller
    //      [X] reverts if proposer still has more tokens than threshold
    //      [X] updates proposal object canceled state
    //      [X] cancels transactions on timelock

    function testCorrectness_cancelRevertsIfProposalExecuted() public {
        uint256 proposalId = _queueProposal(1);

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Try to cancel proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Cancel_AlreadyExecuted()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );
    }

    function testCorrectness_cancelSucceedsIfProposerIsCaller() public {
        uint256 proposalId = _createTestProposal(1);

        // Cancel proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );
    }

    function testCorrectness_cancelRevertsProposerAboveThreshold(address caller_) public {
        vm.assume(caller_ != alice);

        uint256 proposalId = _createTestProposal(1);

        // Try to cancel proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Cancel_AboveThreshold()");
        vm.expectRevert(err);
        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );
    }

    function testCorrectness_cancelUpdatesProposalObjectCanceledState() public {
        uint256 proposalId = _createTestProposal(1);

        // Cancel proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );

        bytes memory stateData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(stateData, (uint8));
        assertEq(state, 2);
    }

    function testCorrectness_cancelCancelsTransactionsOnTimelock() public {
        uint256 proposalId = _queueProposal(1);
        uint256 eta = block.timestamp + 1 days;

        // Check initial state
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);

        bool isQueuedOnTimelock = timelock.queuedTransactions(
            keccak256(
                abi.encode(proposalId, targets[0], values[0], signatures[0], calldatas[0], eta)
            )
        );
        assertEq(isQueuedOnTimelock, true);

        // Cancel proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );

        // Check final state
        isQueuedOnTimelock = timelock.queuedTransactions(
            keccak256(
                abi.encode(proposalId, targets[0], values[0], signatures[0], calldatas[0], eta)
            )
        );
        assertEq(isQueuedOnTimelock, false);
    }

    // [X]   veto
    //      [X] can only be called by the veto guardian
    //      [X] reverts if proposal is already executed
    //      [X] updates proposal object vetoed state
    //      [X] if proposal is queued, cancels transactions on timelock

    function testCorrectness_vetoRevertsIfNotCalledByVetoGuardian(address caller_) public {
        vm.assume(caller_ != vetoGuardian);

        uint256 proposalId = _createTestProposal(1);

        // Try to veto proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyVetoGuardian()");
        vm.expectRevert(err);
        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );
    }

    function testCorrectness_vetoRevertsIfProposalExecuted() public {
        uint256 proposalId = _queueProposal(1);

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Try to veto proposal
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Veto_AlreadyExecuted()");
        vm.expectRevert(err);
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );
    }

    function testCorrectness_vetoUpdatesProposalObjectVetoState() public {
        uint256 proposalId = _createTestProposal(1);

        // Veto proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        bytes memory stateData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(stateData, (uint8));
        assertEq(state, 8);
    }

    function testCorrectness_vetoCancelsTransactionsQueuedOnTimelock() public {
        uint256 proposalId = _queueProposal(1);
        uint256 eta = block.timestamp + 1 days;

        // Check initial state
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);

        bool isQueuedOnTimelock = timelock.queuedTransactions(
            keccak256(
                abi.encode(proposalId, targets[0], values[0], signatures[0], calldatas[0], eta)
            )
        );
        assertEq(isQueuedOnTimelock, true);

        // Veto proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        // Check final state
        isQueuedOnTimelock = timelock.queuedTransactions(
            keccak256(
                abi.encode(proposalId, targets[0], values[0], signatures[0], calldatas[0], eta)
            )
        );
        assertEq(isQueuedOnTimelock, false);
    }

    // --- Vote Tests -------------------------------------------------------------

    // [X]   castVote
    //      [X] reverts if proposal is not active
    //      [X] reverts if vote type is invalid
    //      [X] reverts if voter has already voted
    //      [X] updates proposal votes
    //      [X] updates proposal receipt
    //      [X] emits event with empty reason string

    function testCorrectness_castVoteRevertsIfProposalNotActive() public {
        uint256 proposalId = _createTestProposal(1);

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_Closed()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp forward so voting period has ended
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );
        vm.roll(block.number + 50401);

        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );
    }

    function testCorrectness_castVoteRevertsIfVoteInvalid(uint8 vote_) public {
        vm.assume(vote_ > 2);

        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_InvalidType()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, vote_)
        );
    }

    function testCorrectness_castVoteRevertsIfVoterAlreadyVoted() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        vm.startPrank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Try to vote again
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_AlreadyCast()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );
    }

    function testCorrectness_castVoteUpdatesProposalVotes(
        uint8 vote_,
        uint256 votes_,
        address voter_
    ) public {
        vm.assume(voter_ != alice && voter_ != address(0));
        vm.assume(vote_ < 2);

        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Mint votes to voter (max of 10,000,000 gOHM)
        if (votes_ > 10_000_000e18) {
            votes_ = 10_000_000e18;
        }
        gohm.mint(voter_, votes_);
        gohm.checkpointVotes(voter_);

        // Vote for proposal
        vm.prank(voter_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, vote_)
        );

        // Get proposal votes
        bytes memory proposalData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalVotes(uint256)", proposalId)
        );
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = abi.decode(
            proposalData,
            (uint256, uint256, uint256)
        );

        if (vote_ == 0) {
            assertEq(againstVotes, votes_);
            assertEq(forVotes, 0);
            assertEq(abstainVotes, 0);
        } else if (vote_ == 1) {
            assertEq(againstVotes, 0);
            assertEq(forVotes, votes_);
            assertEq(abstainVotes, 0);
        } else if (vote_ == 2) {
            assertEq(againstVotes, 0);
            assertEq(forVotes, 0);
            assertEq(abstainVotes, votes_);
        }
    }

    function testCorrectness_castVoteUpdatesProposalReceipt() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Check initial state
        bytes memory receiptData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getReceipt(uint256,address)", proposalId, alice)
        );
        (bool hasVoted, uint8 support, uint96 votes) = abi.decode(
            receiptData,
            (bool, uint8, uint96)
        );

        assertEq(hasVoted, false);
        assertEq(support, 0);
        assertEq(votes, 0);

        // Vote for proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Check final state
        receiptData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getReceipt(uint256,address)", proposalId, alice)
        );
        (hasVoted, support, votes) = abi.decode(receiptData, (bool, uint8, uint96));

        assertEq(hasVoted, true);
        assertEq(support, 1);
        assertEq(votes, 110_000e18);
    }

    function testCorrectness_castVoteEmitsEventWithEmptyReasonString() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        vm.expectEmit(address(governorBravoDelegator));
        emit VoteCast(alice, proposalId, 1, 110_000e18, "");
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );
    }

    // [X]   castVoteWithReason
    //      [X] reverts if proposal is not active
    //      [X] reverts if vote type is invalid
    //      [X] reverts if voter has already voted
    //      [X] updates proposal votes (user receives votes at the minimum of votes at start of proposal and current balance)
    //      [X] updates proposal receipt
    //      [X] emits event with reason string

    function testCorrectness_castVoteWithReasonRevertsIfProposalNotActive() public {
        uint256 proposalId = _createTestProposal(1);

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_Closed()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                1,
                "test"
            )
        );

        // Warp forward so voting period has ended
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );
        vm.roll(block.number + 50401);

        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                1,
                "test"
            )
        );
    }

    function testCorrectness_castVoteWithReasonRevertsIfVoteInvalid(uint8 vote_) public {
        vm.assume(vote_ > 2);

        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_InvalidType()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                vote_,
                "test"
            )
        );
    }

    function testCorrectness_castVoteWithReasonRevertsIfVoterAlreadyvoted() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        vm.startPrank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                1,
                "test"
            )
        );

        // Try to vote again
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_AlreadyCast()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                1,
                "test"
            )
        );
    }

    function testCorrectness_castVoteWithReasonUpdatesProposalVotes(
        uint8 vote_,
        uint256 votes_,
        address voter_
    ) public {
        vm.assume(voter_ != alice && voter_ != address(0));
        vm.assume(vote_ < 2);

        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Mint votes to voter (max of 10,000,000 gOHM)
        if (votes_ > 10_000_000e18) {
            votes_ = 10_000_000e18;
        }
        gohm.mint(voter_, votes_);
        gohm.checkpointVotes(voter_);

        // Vote for proposal
        vm.prank(voter_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                vote_,
                "test"
            )
        );

        // Get proposal votes
        bytes memory proposalData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalVotes(uint256)", proposalId)
        );
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = abi.decode(
            proposalData,
            (uint256, uint256, uint256)
        );

        if (vote_ == 0) {
            assertEq(againstVotes, votes_);
            assertEq(forVotes, 0);
            assertEq(abstainVotes, 0);
        } else if (vote_ == 1) {
            assertEq(againstVotes, 0);
            assertEq(forVotes, votes_);
            assertEq(abstainVotes, 0);
        } else if (vote_ == 2) {
            assertEq(againstVotes, 0);
            assertEq(forVotes, 0);
            assertEq(abstainVotes, votes_);
        }
    }

    function testCorrectness_castVoteWithReasonUpdatesProposalReceipt() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Check initial state
        bytes memory receiptData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getReceipt(uint256,address)", proposalId, alice)
        );
        (bool hasVoted, uint8 support, uint96 votes) = abi.decode(
            receiptData,
            (bool, uint8, uint96)
        );

        assertEq(hasVoted, false);
        assertEq(support, 0);
        assertEq(votes, 0);

        // Vote for proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                1,
                "test"
            )
        );

        // Check final state
        receiptData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getReceipt(uint256,address)", proposalId, alice)
        );
        (hasVoted, support, votes) = abi.decode(receiptData, (bool, uint8, uint96));

        assertEq(hasVoted, true);
        assertEq(support, 1);
        assertEq(votes, 110_000e18);
    }

    function testCorrectness_castVoteWithReasonEmitsEventWithReasonString() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        vm.expectEmit(address(governorBravoDelegator));
        emit VoteCast(alice, proposalId, 1, 110_000e18, "test");
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteWithReason(uint256,uint8,string)",
                proposalId,
                1,
                "test"
            )
        );
    }

    // [X]   castVoteBySig
    //      [X]  Reverts if proposal is not active
    //      [X]  Reverts if vote type is invalid
    //      [X]  Reverts if voter has already voted
    //      [X]  Updates proposal votes (user receives votes at the minimum of votes at start of proposal and current balance)
    //      [X]  Updates proposal receipt
    //      [X]  Emits event with empty reason string

    function _getSigningHash(uint256 proposalId_, uint8 support_) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                governorBravo.DOMAIN_TYPEHASH(),
                keccak256(bytes(governorBravo.name())),
                block.chainid,
                address(governorBravoDelegator)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(governorBravo.BALLOT_TYPEHASH(), proposalId_, support_)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return digest;
    }

    function testCorrectness_castVoteBySigRevertsIfProposalNotActive() public {
        uint256 proposalId = _createTestProposal(1);

        bytes32 validHash = _getSigningHash(proposalId, 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, validHash);

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_Closed()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                1,
                v,
                r,
                s
            )
        );

        // Warp forward so voting period has ended
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );
        vm.roll(block.number + 50401);

        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                1,
                v,
                r,
                s
            )
        );
    }

    function testCorrectness_castVoteBySigRevertsIfVoteInvalid(uint8 vote_) public {
        vm.assume(vote_ > 2);

        uint256 proposalId = _createTestProposal(1);

        bytes32 validHash = _getSigningHash(proposalId, vote_);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, validHash);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_InvalidType()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                vote_,
                v,
                r,
                s
            )
        );
    }

    function testCorrectness_castVoteBySigRevertsIfVoterAlreadyVoted() public {
        uint256 proposalId = _createTestProposal(1);

        bytes32 validHash = _getSigningHash(proposalId, 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, validHash);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                1,
                v,
                r,
                s
            )
        );

        // Try to vote again
        bytes memory err = abi.encodeWithSignature("GovernorBravo_Vote_AlreadyCast()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                1,
                v,
                r,
                s
            )
        );
    }

    function testCorrectness_castVoteBySigUpdatesProposalVotes(uint8 vote_, uint256 votes_) public {
        vm.assume(vote_ < 2);

        uint256 proposalId = _createTestProposal(1);

        bytes32 validHash = _getSigningHash(proposalId, vote_);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, validHash);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Mint votes to alice (max of 10,000,000 gOHM)
        if (votes_ > 10_000_000e18) {
            votes_ = 10_000_000e18;
        }
        gohm.burn(alice, 110_000e18);
        gohm.mint(alice, votes_);
        gohm.checkpointVotes(alice);

        // Vote for proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                vote_,
                v,
                r,
                s
            )
        );

        // Get proposal votes
        bytes memory proposalData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalVotes(uint256)", proposalId)
        );
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = abi.decode(
            proposalData,
            (uint256, uint256, uint256)
        );

        if (vote_ == 0) {
            assertEq(againstVotes, votes_);
            assertEq(forVotes, 0);
            assertEq(abstainVotes, 0);
        } else if (vote_ == 1) {
            assertEq(againstVotes, 0);
            assertEq(forVotes, votes_);
            assertEq(abstainVotes, 0);
        } else if (vote_ == 2) {
            assertEq(againstVotes, 0);
            assertEq(forVotes, 0);
            assertEq(abstainVotes, votes_);
        }
    }

    function testCorrectness_castVoteBySigUpdatesProposalReceipt() public {
        uint256 proposalId = _createTestProposal(1);

        bytes32 validHash = _getSigningHash(proposalId, 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, validHash);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Check initial state
        bytes memory receiptData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getReceipt(uint256,address)", proposalId, alice)
        );
        (bool hasVoted, uint8 support, uint96 votes) = abi.decode(
            receiptData,
            (bool, uint8, uint96)
        );

        assertEq(hasVoted, false);
        assertEq(support, 0);
        assertEq(votes, 0);

        // Vote for proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                1,
                v,
                r,
                s
            )
        );

        // Check final state
        receiptData = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getReceipt(uint256,address)", proposalId, alice)
        );
        (hasVoted, support, votes) = abi.decode(receiptData, (bool, uint8, uint96));

        assertEq(hasVoted, true);
        assertEq(support, 1);
        assertEq(votes, 110_000e18);
    }

    function testCorrectness_castVoteBySigEmitsEventWithEmptyReasonString() public {
        uint256 proposalId = _createTestProposal(1);

        bytes32 validHash = _getSigningHash(proposalId, 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, validHash);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        vm.expectEmit(address(governorBravoDelegator));
        emit VoteCast(alice, proposalId, 1, 110_000e18, "");
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "castVoteBySig(uint256,uint8,uint8,bytes32,bytes32)",
                proposalId,
                1,
                v,
                r,
                s
            )
        );
    }

    // --- Admin Tests ------------------------------------------------------------

    // [X]   _setVotingDelay
    //      [X] reverts if not called by admin
    //      [X] reverts if delay is less than minimum or greater than maximum
    //      [X] updates voting delay

    function testCorrectness_setVotingDelayRevertsIfNotCalledByAdmin(address caller_) public {
        vm.assume(caller_ != address(timelock));

        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyAdmin()");
        vm.expectRevert(err);

        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVotingDelay(uint256)", 1)
        );
    }

    function testCorrectness_setVotingDelayRevertsIfDelayIsOutsideBounds(uint256 delay_) public {
        // If delay_ is in acceptable bounds, set to minimum minus 1
        if (delay_ >= 7200 && delay_ <= 50400) {
            delay_ = 7199;
        }

        bytes memory err = abi.encodeWithSignature("GovernorBravo_InvalidDelay()");
        vm.expectRevert(err);
        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVotingDelay(uint256)", delay_)
        );
    }

    function testCorrectness_setVotingDelayUpdatesVotingDelay(uint256 delay_) public {
        if (delay_ < 7200 || delay_ > 50400) {
            delay_ = 7200;
        }

        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVotingDelay(uint256)", delay_)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("votingDelay()")
        );
        uint256 votingDelay = abi.decode(data, (uint256));
        assertEq(votingDelay, delay_);
    }

    // [X]   _setVotingPeriod
    //      [X] reverts if not called by admin
    //      [X] reverts if period is less than minimum or greater than maximum
    //      [X] updates voting period

    function testCorrectness_setVotingPeriodRevertsIfNotCalledByAdmin(address caller_) public {
        vm.assume(caller_ != address(timelock));

        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyAdmin()");
        vm.expectRevert(err);

        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVotingPeriod(uint256)", 1)
        );
    }

    function testCorrectness_setVotingPeriodRevertsIfPeriodIsOutsideBounds(uint256 period_) public {
        // If period_ is in acceptable bounds, set to minimum minus 1
        if (period_ >= 21600 && period_ <= 100800) {
            period_ = 21599;
        }

        bytes memory err = abi.encodeWithSignature("GovernorBravo_InvalidPeriod()");
        vm.expectRevert(err);
        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVotingPeriod(uint256)", period_)
        );
    }

    function testCorrectness_setVotingPeriodUpdatesVotingPeriod(uint256 period_) public {
        if (period_ < 21600 || period_ > 100800) {
            period_ = 21600;
        }

        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVotingPeriod(uint256)", period_)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("votingPeriod()")
        );
        uint256 votingPeriod = abi.decode(data, (uint256));
        assertEq(votingPeriod, period_);
    }

    // [X]   _setProposalThreshold
    //      [X] reverts if not called by admin
    //      [X] reverts if threshold is less than minimum or greater than maximum
    //      [X] updates proposal threshold

    function testCorrectness_setProposalThresholdRevertsIfNotCalledByAdmin(address caller_) public {
        vm.assume(caller_ != address(timelock));

        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyAdmin()");
        vm.expectRevert(err);

        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setProposalThreshold(uint256)", 1)
        );
    }

    function testCorrectness_setProposalThresholdRevertsIfThresholdIsOutsideBounds(
        uint256 threshold_
    ) public {
        // If threshold_ is in acceptable bounds, set to minimum minus 1
        if (threshold_ >= 15_000 && threshold_ <= 1_000_000) {
            threshold_ = 14_999;
        }

        bytes memory err = abi.encodeWithSignature("GovernorBravo_InvalidThreshold()");
        vm.expectRevert(err);
        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setProposalThreshold(uint256)", threshold_)
        );
    }

    function testCorrectness_setProposalThresholdUpdatesProposalThreshold(
        uint256 threshold_
    ) public {
        if (threshold_ < 15_000 || threshold_ > 1_000_000) {
            threshold_ = 15_000;
        }

        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setProposalThreshold(uint256)", threshold_)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("proposalThreshold()")
        );
        uint256 proposalThreshold = abi.decode(data, (uint256));
        assertEq(proposalThreshold, threshold_);
    }

    // [X]   _setVetoGuardian
    //      [X] reverts if not called by admin
    //      [X] updates veto guardian

    function testCorrectness_setVetoGuardianRevertsIfNotCalledByAdmin(address caller_) public {
        vm.assume(caller_ != address(timelock));

        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyAdmin()");
        vm.expectRevert(err);

        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVetoGuardian(address)", address(0))
        );
    }

    function testCorrectness_setVetoGuardianUpdatesVetoGuardian(address guardian_) public {
        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setVetoGuardian(address)", guardian_)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("vetoGuardian()")
        );
        address vetoGuardian_ = abi.decode(data, (address));
        assertEq(vetoGuardian_, guardian_);
    }

    // [X]   _setPendingAdmin
    //      [X] reverts if not called by admin
    //      [X] updates pending admin

    function testCorrectness_setPendingAdminRevertsIfNotCalledByAdmin(address caller_) public {
        vm.assume(caller_ != address(timelock));

        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyAdmin()");
        vm.expectRevert(err);

        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setPendingAdmin(address)", address(0))
        );
    }

    function testCorrectness_setPendingAdminUpdatesPendingAdmin(address admin_) public {
        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setPendingAdmin(address)", admin_)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("pendingAdmin()")
        );
        address pendingAdmin_ = abi.decode(data, (address));
        assertEq(pendingAdmin_, admin_);
    }

    // [X]   _acceptAdmin
    //      [X] reverts if not called by pending admin
    //      [X] reverts if called by the zero address (why is this even a check)
    //      [X] updates admin to pending admin
    //      [X] updates pending admin to zero address

    function _setUpPendingAdmin(address newAdmin_) internal returns (address) {
        vm.assume(newAdmin_ != address(0));

        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setPendingAdmin(address)", newAdmin_)
        );

        return newAdmin_;
    }

    function testCorrectness_acceptAdminRevertsIfNotCalledByPendingAdmin(
        address newAdmin_,
        address caller_
    ) public {
        vm.assume(caller_ != newAdmin_);

        _setUpPendingAdmin(newAdmin_);

        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyPendingAdmin()");
        vm.expectRevert(err);

        vm.prank(caller_);
        address(governorBravoDelegator).functionCall(abi.encodeWithSignature("_acceptAdmin()"));
    }

    function testCorrectness_acceptAdminRevertsIfCalledByZeroAddress(address newAdmin_) public {
        _setUpPendingAdmin(newAdmin_);

        bytes memory err = abi.encodeWithSignature("GovernorBravo_OnlyPendingAdmin()");
        vm.expectRevert(err);

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(abi.encodeWithSignature("_acceptAdmin()"));
    }

    function testCorrectness_acceptAdminUpdatesAdminToPendingAdmin(address newAdmin_) public {
        newAdmin_ = _setUpPendingAdmin(newAdmin_);

        vm.prank(newAdmin_);
        address(governorBravoDelegator).functionCall(abi.encodeWithSignature("_acceptAdmin()"));

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("admin()")
        );
        address admin_ = abi.decode(data, (address));
        assertEq(admin_, newAdmin_);
    }

    function testCorrectness_acceptAdminUpdatesPendingAdminToZeroAddress(address newAdmin_) public {
        newAdmin_ = _setUpPendingAdmin(newAdmin_);

        vm.prank(newAdmin_);
        address(governorBravoDelegator).functionCall(abi.encodeWithSignature("_acceptAdmin()"));

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("pendingAdmin()")
        );
        address pendingAdmin_ = abi.decode(data, (address));
        assertEq(pendingAdmin_, address(0));
    }

    // --- View Functions ---------------------------------------------------------

    // [X]   getProposalThresholdVotes

    function testCorrectness_getProposalThresholdVotes() public {
        // Baseline should be .017% of total supply
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalThresholdVotes()")
        );
        uint256 proposalThresholdVotes = abi.decode(data, (uint256));
        assertEq(proposalThresholdVotes, 170e18);

        // Increase proposal threshold to 1%
        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setProposalThreshold(uint256)", 1_000_000)
        );
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalThresholdVotes()")
        );
        proposalThresholdVotes = abi.decode(data, (uint256));
        assertEq(proposalThresholdVotes, 10_000e18);

        // Set proposal threshold back to .017%
        vm.prank(address(timelock));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("_setProposalThreshold(uint256)", 17_000)
        );

        // Increase total supply to 2,000,000
        gohm.mint(address(0), 1_000_000e18);
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalThresholdVotes()")
        );
        proposalThresholdVotes = abi.decode(data, (uint256));
        assertEq(proposalThresholdVotes, 340e18);

        // Decrease total supply to 10,000
        gohm.burn(address(0), 1_890_000e18);
        gohm.burn(alice, 100_000e18);
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getProposalThresholdVotes()")
        );
        proposalThresholdVotes = abi.decode(data, (uint256));
        assertEq(proposalThresholdVotes, 17e17);
    }

    // [X]   getQuorumVotes

    function testCorrectness_getQuorumVotes() public {
        // Baseline should be 50% of total supply
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getQuorumVotes()")
        );
        uint256 quorumVotes = abi.decode(data, (uint256));
        assertEq(quorumVotes, 200_000e18);

        // Mint 1,000,000 gOHM
        gohm.mint(address(0), 1_000_000e18);
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getQuorumVotes()")
        );
        quorumVotes = abi.decode(data, (uint256));
        assertEq(quorumVotes, 400_000e18);

        // Burn 1,500,000 gOHM
        gohm.burn(address(0), 1_500_000e18);
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getQuorumVotes()")
        );
        quorumVotes = abi.decode(data, (uint256));
        assertEq(quorumVotes, 100_000e18);
    }

    // [X]   getActions

    function testCorrectness_getActions() public {
        uint256 proposalId = _createTestProposal(1);

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getActions(uint256)", proposalId)
        );
        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        ) = abi.decode(data, (address[], uint256[], string[], bytes[]));

        assertEq(targets.length, 1);
        assertEq(values.length, 1);
        assertEq(signatures.length, 1);
        assertEq(calldatas.length, 1);

        assertEq(targets[0], address(0));
        assertEq(values[0], 0);
        assertEq(signatures[0], "");
        assertEq(calldatas[0].length, 0);
    }

    // [X]   getReceipt

    function testCorrectness_getReceipt() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Check receipt
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getReceipt(uint256,address)", proposalId, alice)
        );
        (bool hasVoted, uint8 support, uint96 votes) = abi.decode(data, (bool, uint8, uint96));

        assertEq(hasVoted, true);
        assertEq(support, 1);
        assertEq(votes, 110_000e18);
    }

    // [X]   state
    //      [X] reverts if proposal id is invalid
    //      [X] returns canceled if proposal has been canceled
    //      [X] returns pending if proposal is pre-voting period
    //      [X] returns active if proposal is in voting period
    //      [X] returns defeated if proposal has been defeated (missed quorum)
    //      [X] returns defeated if proposal has been defeated (votes against > votes for)
    //      [X] returns succeeded if proposal has been succeeded
    //      [X] returns queued if proposal has been queued
    //      [X] returns expired if proposal has expired
    //      [X] returns executed if proposal has been executed
    //      [X] returns vetoed if proposal has been vetoed
    //      [X] when proposal is emergency proposal
    //        [X] returns vetoed if the proposal has been vetoed
    //        [X] returns executed if the proposal has been executed
    //        [X] returns emergency if the proposal has not been vetoed or executed

    function testCorrectness_stateRevertsIfProposalIdInvalid(uint256 proposalId_) public {
        vm.assume(proposalId_ > 0);

        bytes memory err = abi.encodeWithSignature("GovernorBravo_Proposal_IdInvalid()");
        vm.expectRevert(err);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId_)
        );
    }

    function testCorrectness_stateReturnsCanceledIfProposalCanceled() public {
        uint256 proposalId = _createTestProposal(1);

        // Cancel proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("cancel(uint256)", proposalId)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 2);
    }

    function testCorrectness_stateReturnsPendingIfProposalPreVotingPeriod() public {
        uint256 proposalId = _createTestProposal(1);

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 0);
    }

    function testCorrectness_stateReturnsActiveIfProposalInVotingPeriod() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 1);
    }

    // TODO: Expand this to check a variety of circumstances around changing supplies
    function testCorrectness_stateReturnsDefeated_missedQuorum() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Warp through voting period
        vm.roll(block.number + 50401);

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 3);
    }

    function testCorrectness_stateReturnsDefeated_lostVotes() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Address 0 votes against
        gohm.checkpointVotes(address(0));
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 0)
        );

        // Alice votes for proposal
        vm.prank(alice);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp through voting period
        vm.roll(block.number + 50401);

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 3);
    }

    function testCorrectness_stateReturnsSucceeded() public {
        uint256 proposalId = _createTestProposal(1);

        // Warp into voting period
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Address 0 votes for proposal
        gohm.checkpointVotes(address(0));
        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        // Warp through voting period
        vm.roll(block.number + 50401);

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 4);
    }

    function testCorrectness_stateReturnsQueued() public {
        uint256 proposalId = _queueProposal(1);

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 5);
    }

    function testCorrectness_stateReturnsExpired() public {
        uint256 proposalId = _queueProposal(1);

        // Warp through timelock grace period
        vm.warp(block.timestamp + 2 days + 1);

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 6);
    }

    function testCorrectness_stateReturnsExecuted() public {
        uint256 proposalId = _queueProposal(1);

        // Warp through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 7);
    }

    function testCorrectness_stateReturnsVetoed() public {
        uint256 proposalId = _createTestProposal(1);

        // Veto proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 8);
    }

    function testCorrectness_state_emergencyVetoed_returnsVetoed(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(1);

        // Veto proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("veto(uint256)", proposalId)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );

        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 8);
    }

    function testCorrectness_state_emergencyExecuted_returnsExecuted(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(1);

        // Queue the proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        vm.prank(vetoGuardian);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 7);
    }

    function testCorrectness_state_emergency_returnsEmergency(uint256 supply_) public {
        vm.assume(supply_ < 1_000e18);

        uint256 proposalId = _createEmergencyProposal(1);

        // Verify state is emergency
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("state(uint256)", proposalId)
        );
        uint8 state = abi.decode(data, (uint8));
        assertEq(state, 9);
    }

    function testCorrectness_implementationUpgrade() public {
        // --------------------------------------------------
        // 1. Execute a proposal to change the contract state
        // --------------------------------------------------

        // Create action set to install the TRSRY on Kernel
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Activate Treasury";

        targets[0] = address(kernel);
        values[0] = 0;
        signatures[0] = "executeAction(uint8,address)";
        calldatas[0] = abi.encode(0, address(TRSRY));

        // Create proposal
        vm.prank(alice);
        bytes memory data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        uint256 proposalId = abi.decode(data, (uint256));
        assertEq(proposalId, 1);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal and warp so voting has ended
        gohm.checkpointVotes(address(0));

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        Module moduleForTRSRY = kernel.getModuleForKeycode(toKeycode("TRSRY"));
        assertEq(address(moduleForTRSRY), address(0));

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Check implementation address and proposal count
        assertEq(
            GovernorBravoDelegate(address(governorBravoDelegator)).implementation(),
            address(governorBravo)
        );
        assertEq(GovernorBravoDelegate(address(governorBravoDelegator)).proposalCount(), 1);

        // --------------------------------------------------
        // 2. Execute a proposal to upgrade the implemenation
        // --------------------------------------------------

        address newImplementation = address(new GovernorBravoDelegate());

        // Create action set to upgrade proxy implementation
        targets[0] = address(governorBravoDelegator);
        values[0] = 0;
        signatures[0] = "_setImplementation(address)";
        calldatas[0] = abi.encode(newImplementation);
        description = "Upgrade GovernorBravo Implementation";

        // Create proposal
        vm.prank(alice);
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        proposalId = abi.decode(data, (uint256));
        assertEq(proposalId, 2);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal and warp so voting has ended
        gohm.checkpointVotes(address(0));

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Check implementation address and proposal count
        assertEq(
            GovernorBravoDelegate(address(governorBravoDelegator)).implementation(),
            newImplementation
        );
        assertEq(GovernorBravoDelegate(address(governorBravoDelegator)).proposalCount(), 2);

        // --------------------------------------------------
        // 3. Execute a new proposal with the implemenation
        // --------------------------------------------------

        // Create action set to pull RolesAdmin admin access
        targets[0] = address(rolesAdmin);
        values[0] = 0;
        signatures[0] = "pullNewAdmin()";
        calldatas[0] = "";
        description = "Pull RolesAdmin Admin Access";

        // Create proposal
        vm.prank(alice);
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                targets,
                values,
                signatures,
                calldatas,
                description
            )
        );
        proposalId = abi.decode(data, (uint256));
        assertEq(proposalId, 3);

        // Warp forward so voting period has started
        vm.roll(block.number + 21601);
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("activate(uint256)", proposalId)
        );

        // Vote for proposal and warp so voting has ended
        gohm.checkpointVotes(address(0));

        vm.prank(address(0));
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, 1)
        );

        vm.roll(block.number + 50401);

        // Queue proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("queue(uint256)", proposalId)
        );

        // Warp forward through timelock delay
        vm.warp(block.timestamp + 1 days + 1);

        // Execute proposal
        address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("execute(uint256)", proposalId)
        );

        // Check implementation address and proposal count
        assertEq(
            GovernorBravoDelegate(address(governorBravoDelegator)).implementation(),
            newImplementation
        );
        assertEq(GovernorBravoDelegate(address(governorBravoDelegator)).proposalCount(), 3);

        // Check proposal 1 actions
        data = address(governorBravoDelegator).functionCall(
            abi.encodeWithSignature("getActions(uint256)", 1)
        );
        (
            address[] memory targets_,
            uint256[] memory values_,
            string[] memory signatures_,
            bytes[] memory calldatas_
        ) = abi.decode(data, (address[], uint256[], string[], bytes[]));
        assertEq(targets_.length, 1);
        assertEq(values_.length, 1);
        assertEq(signatures_.length, 1);
        assertEq(calldatas_.length, 1);

        (uint8 action, address target) = abi.decode(calldatas_[0], (uint8, address));
        assertEq(targets_[0], address(kernel));
        assertEq(values_[0], 0);
        assertEq(signatures_[0], "executeAction(uint8,address)");
        assertEq(calldatas_[0].length, 32 + 32);
        assertEq(action, 0);
        assertEq(target, address(TRSRY));
    }
}
