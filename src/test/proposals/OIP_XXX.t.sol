// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Proposal test-suite imports
import "forge-std/Test.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {GovernorBravoDelegator} from "src/external/governance/GovernorBravoDelegator.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {Timelock} from "src/external/governance/Timelock.sol";

// OIP_XXX imports
import {OIP_XXX, Clearinghouse, CHREGv1, IERC20, IERC4626} from "proposals/OIP_XXX.sol";

/// @notice Creates a sandboxed environment from a mainnet fork, to simulate the proposal.
/// @dev    Update the `setUp` function to deploy your proposal and set the submission
///         flag to `true` once the proposal has been submitted on-chain.
contract OCGProposalTest is Test {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";
    TestSuite public suite;
    Addresses public addresses;

    // Data struct to cache initial balances.
    struct Cache {
        uint256 daiBalance;
        uint256 sdaiBalance;
    }

    // Wether the proposal has been submitted or not.
    // If true, the framework will check that calldatas match.
    bool public hasBeenSubmitted;

    // Clearinghouse Expected events
    event Defund(address token, uint256 amount);
    event Deactivate();

    /// @notice Creates a sandboxed environment from a mainnet fork.
    function setUp() public virtual {
        /// @dev Deploy your proposal
        OIP_XXX proposal = new OIP_XXX();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        /// [DO NOT DELETE]
        /// @notice This section is used to simulate the proposal on the mainnet fork.
        {
            // Populate addresses array
            address[] memory proposalsAddresses = new address[](1);
            proposalsAddresses[0] = address(proposal);

            // Deploy TestSuite contract
            suite = new TestSuite(ADDRESSES_PATH, proposalsAddresses);

            // Set addresses object
            addresses = suite.addresses();

            suite.setDebug(true);
            // Execute proposals
            suite.testProposals();

            // Proposals execution may change addresses, so we need to update the addresses object.
            addresses = suite.addresses();

            // Check if simulated calldatas match the ones from mainnet.
            if (hasBeenSubmitted) {
                address governor = addresses.getAddress("olympus-governor");
                bool[] memory matches = suite.checkProposalCalldatas(governor);
                for (uint256 i; i < matches.length; i++) {
                    assertTrue(matches[i]);
                }
            } else {
                console.log("\n\n------- Calldata check (simulation vs mainnet) -------\n");
                console.log("Proposal has NOT been submitted on-chain yet.\n");
            }
        }
    }

    // [DO NOT DELETE] Dummy test to ensure `setUp` is executed and the proposal simulated.
    function testProposal_simulate() public {
        assertTrue(true);
    }

    /// -- OPTIONAL INTEGRATION TESTS ----------------------------------------------------
    /// @dev Section for anyone to fork the repo and add integration tests.
    ///      This feature allows anyone to expand the test suite of the proposal in a sandboxed environment.

    function testProposal_emergencyShutdown() public {
        // Get relevant olympus contracts
        Kernel kernel = Kernel(addresses.getAddress("olympus-kernel"));
        address emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        address TRSRY = address(kernel.getModuleForKeycode(toKeycode(bytes5("TRSRY"))));
        address CHREG = address(kernel.getModuleForKeycode(toKeycode(bytes5("CHREG"))));
        Clearinghouse clearinghouseV1 = Clearinghouse(
            addresses.getAddress("olympus-policy-clearinghouse-v1.1")
        );
        // Get relevant tokens
        IERC20 dai = IERC20(addresses.getAddress("external-tokens-dai"));
        IERC20 sdai = IERC20(addresses.getAddress("external-tokens-sdai"));

        // Cache initial balances
        Cache memory cacheCH = Cache({
            daiBalance: dai.balanceOf(address(clearinghouseV1)),
            sdaiBalance: sdai.balanceOf(address(clearinghouseV1))
        });
        Cache memory cacheTRSRY = Cache({
            daiBalance: dai.balanceOf(TRSRY),
            sdaiBalance: sdai.balanceOf(TRSRY)
        });

        // Random actors cannot shut down the system
        vm.expectRevert();
        clearinghouseV1.emergencyShutdown();

        // Only the emergency MS can shutdown the system
        vm.prank(emergencyMS);
        // Ensure that the event is emitted
        vm.expectEmit(address(clearinghouseV1));
        emit Deactivate();
        clearinghouseV1.emergencyShutdown();

        // Check that the system is shutdown and logged in the CHREG
        assertFalse(clearinghouseV1.active());
        // assertEq(CHREGv1(CHREG).activeCount(), 0);
        // Check the token balances
        assertEq(dai.balanceOf(address(clearinghouseV1)), 0);
        assertEq(sdai.balanceOf(address(clearinghouseV1)), 0);
        assertEq(dai.balanceOf(TRSRY), cacheCH.daiBalance + cacheTRSRY.daiBalance);
        assertEq(sdai.balanceOf(TRSRY), cacheCH.sdaiBalance + cacheTRSRY.sdaiBalance);
    }
}
