// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {Kernel, toKeycode} from "src/Kernel.sol";

// OIP_XXX imports
import {OIP_XXX, Clearinghouse, CHREGv1, IERC20} from "src/proposals/OIP_XXX.sol";

contract OIPXXXTest is ProposalTest {
    // Data struct to cache initial balances.
    struct Cache {
        uint256 daiBalance;
        uint256 sdaiBalance;
    }

    // Clearinghouse Expected events
    event Defund(address token, uint256 amount);
    event Deactivate();

    function setUp() public virtual {
        // Mainnet Fork at a fixed block
        // Prior to actual deployment of the proposal (otherwise it will fail) and Clearinghouse v2 - 21216656
        vm.createSelectFork(_RPC_ALIAS, 21216656 - 1);

        /// @dev Deploy your proposal
        OIP_XXX proposal = new OIP_XXX();

        /// @dev Set `hasBeenSubmitted` to `true` once the proposal has been submitted on-chain.
        hasBeenSubmitted = false;

        // Simulate the proposal
        _setupSuite(address(proposal));
        _simulateProposal();
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
        assertFalse(clearinghouseV1.active(), "Clearinghouse should be shutdown");
        assertEq(CHREGv1(CHREG).activeCount(), 1, "CHREG should have 1 active policy");
        // Check the token balances
        assertEq(
            dai.balanceOf(address(clearinghouseV1)),
            0,
            "DAI balance of clearinghouse should be 0"
        );
        assertEq(
            sdai.balanceOf(address(clearinghouseV1)),
            0,
            "sDAI balance of clearinghouse should be 0"
        );
        assertEq(
            dai.balanceOf(TRSRY),
            cacheCH.daiBalance + cacheTRSRY.daiBalance,
            "DAI balance of treasury should be correct"
        );
        assertEq(
            sdai.balanceOf(TRSRY),
            cacheCH.sdaiBalance + cacheTRSRY.sdaiBalance,
            "sDAI balance of treasury should be correct"
        );
    }
}
