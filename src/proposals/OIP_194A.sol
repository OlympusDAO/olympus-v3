// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Olympus Kernel
import {Kernel} from "src/Kernel.sol";

// Interfaces
import {ICoolerLtvOracle} from "src/policies/interfaces/cooler/ICoolerLtvOracle.sol";

// Scripts
import {ProposalScript} from "./ProposalScript.sol";

/// @notice OIP-194A updates the Cooler V2 origination LTV target.
contract OIP_194A is GovernorBravoProposal {
    Kernel internal _kernel;

    uint96 private constant TARGET_ORIGINATION_LTV = 3_123_183_268_921_960_038_400;
    // 2026-10-27 00:00:00 UTC (2026-04-15 00:00:00 + 12 days + 6 months).
    uint40 private constant TARGET_ORIGINATION_LTV_TIME = 1_793_059_200;

    // Temporary max rate-of-change guard to accommodate the requested target schedule.
    // Unit: USDS/gOHM/s in 18-decimal precision.
    // 10_000_000_000_000 / 1e18 = 0.00001 USDS/gOHM/s.
    // 0.00001 * 86400 = 0.864 USDS/gOHM/day.
    uint96 private constant PROPOSAL_MAX_ORIGINATION_LTV_RATE = 10_000_000_000_000;
    uint32 private constant PROPOSAL_MAX_ORIGINATION_LTV_RATE_TIME_DELTA = 1;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 14;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OIP-194A";
    }

    // Provides a brief description of the proposal.
    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# OIP-194A: Cooler Drip Acceleration\n\n",
                "## Context\n\n",
                "OIP-194A implements the follow-up drip schedule to realize additional borrowing power from backing gains captured in OIP-191.\n\n",
                "## Objective\n\n",
                "The DAO recovered an estimated $0.49/OHM of backing gain in OIP-191. That gain is repurposed in this proposal by raising the Cooler V2 target origination LTV to",
                " 3123.1833 USDS/gOHM in a phased manner.\n\n",
                "This is equivalent to ~131.9269 USDS/gOHM over six months and is implemented as a linear target via the cooler LTV oracle so borrowers can benefit progressively instead of through a discrete jump.\n\n",
                "## Actions\n\n",
                "1. Temporarily relax the max origination LTV rate-of-change guard on `olympus-policy-cooler-v2-ltv-oracle` to permit scheduling the proposed target increment.\n",
                "   - Current guard: 1_157_407_407_407 (1_157_407_407_407 / 1e18 = 0.000001157407407 USDS/gOHM/second; * 86400 = 0.1 USDS/gOHM/day)\n",
                "   - Proposal guard: 10_000_000_000_000 (10_000_000_000_000 / 1e18 = 0.00001 USDS/gOHM/second; * 86400 = 0.864 USDS/gOHM/day)\n",
                "   - Rationale: required to move to 3123.1833 USDS/gOHM by 2026-10-27 while execution occurs at current schedule state.\n",
                "   - Required schedule rate from current on-chain state at execution: 7_964_547_568_016 (7_964_547_568_016 / 1e18 = 0.000007964547568016 USDS/gOHM/second; * 86400 = 0.6881369098765824 USDS/gOHM/day).\n",
                "2. Set the target origination LTV on `olympus-policy-cooler-v2-ltv-oracle` to 3123.1833 USDS/gOHM (3123183268921960038400 in 18dp) with a target date of 1793059200."
            );
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        address coolerV2LtvOracle = addresses.getAddress("olympus-policy-cooler-v2-ltv-oracle");

        _pushAction(
            coolerV2LtvOracle,
            abi.encodeWithSelector(
                ICoolerLtvOracle.setMaxOriginationLtvRateOfChange.selector,
                PROPOSAL_MAX_ORIGINATION_LTV_RATE,
                PROPOSAL_MAX_ORIGINATION_LTV_RATE_TIME_DELTA
            ),
            "Relax max rate-of-change for temporary schedule update"
        );

        _pushAction(
            coolerV2LtvOracle,
            abi.encodeWithSelector(
                ICoolerLtvOracle.setOriginationLtvAt.selector,
                TARGET_ORIGINATION_LTV,
                TARGET_ORIGINATION_LTV_TIME
            ),
            "Set target origination LTV for Cooler drip acceleration"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        // Simulates actions on TimelockController
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    // Validates the post-execution state.
    function _validate(Addresses addresses, address) internal view override {
        ICoolerLtvOracle ltvOracle = ICoolerLtvOracle(
            addresses.getAddress("olympus-policy-cooler-v2-ltv-oracle")
        );

        // Validate the oracle target state for the Cooler drip schedule.
        (
            uint96 startingValue,
            uint40 startTime,
            uint96 targetValue,
            uint40 targetTime,
            uint96 slope
        ) = ltvOracle.originationLtvData();

        require(targetValue == TARGET_ORIGINATION_LTV, "Target value is incorrect");
        require(targetTime == TARGET_ORIGINATION_LTV_TIME, "Target time is incorrect");
        require(startTime <= block.timestamp, "Start time should not be in the future");
        require(startTime < targetTime, "Target time should be in the future");
        require(targetValue >= startingValue, "Target value should be non-decreasing");
        require(slope > 0, "Slope should be positive");

        require(
            ltvOracle.maxOriginationLtvRateOfChange() == PROPOSAL_MAX_ORIGINATION_LTV_RATE,
            "Max rate-of-change should match proposal value"
        );

        uint96 expectedSlope = (TARGET_ORIGINATION_LTV - startingValue) / (targetTime - startTime);
        require(slope == expectedSlope, "Slope should match target linear schedule");

        require(
            ltvOracle.currentOriginationLtv() == startingValue,
            "Current LTV should equal starting value after scheduling"
        );
    }
}

contract OIP_194AProposalScript is ProposalScript {
    constructor() ProposalScript(new OIP_194A()) {}
}
