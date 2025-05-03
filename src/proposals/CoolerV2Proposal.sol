// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Olympus Kernel, Modules, and Policies
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {ICoolerLtvOracle} from "src/policies/interfaces/cooler/ICoolerLtvOracle.sol";

// Script
import {ProposalScript} from "./ProposalScript.sol";
import {console2} from "forge-std/console2.sol";

// Libraries
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

/// @notice Activates Cooler V2.
// solhint-disable gas-custom-errors
contract CoolerV2Proposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // TODO finalise max delegate addresses
    uint256 public constant MAX_DELEGATE_ADDRESSES = 100;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 8;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Cooler V2 Activation";
    }

    // Initial LTV:
    // 11 USDS/OHM = 11 * 269.24 = 2961.64 USDS/gOHM
    // 2961.64 × 1e18 = 2961640000000000000000
    //
    // Target LTV:
    // 11.11 USDS/OHM = 11.11 * 269.24 = 2991.2564 USDS/gOHM
    // 2991.2564 × 1e18 = 2991256400000000000000
    //
    // Target LTV change per second:
    // (2991256400000000000000 - 2961640000000000000000) / (365 * 24 * 60 * 60)
    // = 939129883307
    // Target LTV change per day:
    // = 939129883307 * 86400 = 81139840000000000 = 0.0811408219 USDS/day

    // Provides a brief description of the proposal.
    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Cooler V2 Activation\n\n",
                "This proposal activates Cooler Loans v2.\n\n",
                "## Justification\n\n",
                "Cooler Loans v2 is a re-architecture of Cooler Loans and allows for the following key improvements to the system:\n\n",
                "* Conversion to a perpetual interest system that allows interest to be calculated each second vs. every four months. This eliminates end-user friction from accidental defaults and instead, allows a loan's health to deteriorate and ultimately be liquidated much more slowly.\n",
                "* Allows governance to increase Loan to Backing over time. As the backing value of OHM increases, the amount of stables that can be lent per token logically increases. In Cooler v1, this growth cannot be realized without deploying an entirely new Clearinghouse contract. In Cooler v2, OCG (On-Chain Governance) can define new levels of backing and the associated stables will be released over time at a predefined rate. For example, a user opening their loan might get 10.74 USDS for 1 OHM at the time of origination. They might check back six months later to find that 10.80 is now allowed. The 6 cents difference would be released to them linearly over that predefined time horizon, allowing them to capture the difference against the same amount of collateral.\n",
                "* Formalises management of the delegation of gOHM voting rights through the DLGTE module. This enables individual borrowers, as well as platforms building on top of Cooler v2, to assign all or a portion of their voting power to addresses.\n",
                "  * By default, the maximum number of delegates for an account is 10. However, this can be modified on a per-account basis through governance.\n",
                "* Make Coolers more composable for other smart contracts to build upon. One of the launch products with Cooler v2 will be issued by our partners at Origami Finance called hOHM. hOHM is an OHM derivative that uses Cooler v2 to programmatically leverage OHM to buy more OHM using the aforementioned increase in Loan to Backing. This creates a maximally leveraged position whose health is contractually managed with minimized downside but leveraged upside. It also creates an economy of scale with a perpetual bid on OHM to grow.\n\n",
                "Additionally, the system includes two periphery contracts:\n\n",
                "- Composites: allows users to save gas by combining actions (deposit collateral and borrow, repay and withdraw collateral)\n",
                "- Migrator: allows users to migrate loans from a v1 Cooler to v2\n\n",
                "## Resources\n\n",
                "Cooler v2 has been well audited by several discrete parties:\n\n",
                "- [Electisec Audit Report - Cooler v2](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/Olympus_CoolerV2-Electisec_report.pdf)\n",
                "- [Electisec Audit Report - Composites and Migrator](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/Olympus_Cooler_Composite_Migrator-Electisec_report.pdf)\n",
                "- [Nethermind Audit Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2025-04-04%20Cooler%20V2%20-%20Nethermind.pdf)\n",
                "- [Guardefy Audit Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/audit_cooler_panprog_v2.pdf)\n\n",
                "The code changes can be viewed at [PR 46](https://github.com/OlympusDAO/olympus-v3/pull/46).\n\n",
                "## Initial Configuration\n\n",
                "The Cooler V2 contracts have been configured with the following parameters at the time of deployment:\n\n",
                "- Bounds check: max change to the origination LTV (using `setOriginationLtvAt()`): 500 USDS\n",
                "- Bounds check: min time delta required when setting the target origination LTV: 604800 seconds (1 week)\n",
                "- Bounds check: max (positive) rate of change of Origination LTV allowed: 0.0000011574 USDS/second (0.1 USDS/day)\n",
                "- Bounds check: max liquidation LTV premium: 333 bps (3.33%)\n",
                "- Initial origination LTV: 2961.64 USDS/gOHM (~ 11 USDS/OHM)\n",
                "- Liquidation LTV premium: 100 bps (1%)\n",
                "- Interest Rate APR: 0.005 (0.5%) per year\n",
                "- Min debt required to open a loan: 1000 USDS\n",
                "## Assumptions\n\n",
                "- The DLGTE module has been installed into the Kernel\n",
                "- The LTV Oracle, Treasury Borrower and Mono Cooler policies have been activated in the Kernel\n",
                "- The Treasury Borrower policy has been set on the Mono Cooler policy\n\n",
                "## Proposal Steps\n\n",
                '1. Grant the "admin" role to the OCG timelock\n',
                '2. Grant the "emergency" role to the Emergency MS and OCG timelock\n',
                '3. Grant the "treasuryborrower_cooler" role to the Cooler V2 policy\n',
                "4. Disable the Cooler V1 Clearinghouse policy\n",
                "5. Set the target origination LTV for the Cooler V2 policy to be 2991.2564 USDS/gOHM (~ 11.11 USDS/OHM) on 15th May 2026\n",
                "6. Enable the Cooler V2 Treasury Borrower policy. This enables the main Cooler V2 policy (MonoCooler) to operate.\n",
                string.concat(
                    "7. Set the maximum delegate addresses for hOHM to ",
                    Strings.toString(MAX_DELEGATE_ADDRESSES),
                    ".\n\n"
                ),
                "The periphery contracts have the owner set to the DAO MS, and will be enabled before or after this proposal."
            );
    }

    // solhint-enable quotes

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address timelock = addresses.getAddress("olympus-timelock");
        address emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
        address coolerV2TreasuryBorrower = addresses.getAddress(
            "olympus-policy-cooler-v2-treasury-borrower"
        );
        address coolerV2LtvOracle = addresses.getAddress("olympus-policy-cooler-v2-ltv-oracle");
        address hohm = addresses.getAddress("hohm");
        address coolerV1Clearinghouse = addresses.getAddress("olympus-policy-clearinghouse-1_2");

        // STEP 1: Grant the "admin" role to the OCG Timelock, if needed
        if (!roles.hasRole(timelock, bytes32("admin"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("admin"), timelock),
                "Grant admin to Timelock"
            );
        } else {
            console2.log("Timelock already has the admin role");
        }

        // STEP 2: Grant the "emergency" role, if needed
        if (!roles.hasRole(emergencyMS, bytes32("emergency"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("emergency"),
                    emergencyMS
                ),
                "Grant emergency to Emergency MS"
            );
        } else {
            console2.log("Emergency MS already has the emergency role");
        }

        if (!roles.hasRole(timelock, bytes32("emergency"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("emergency"),
                    timelock
                ),
                "Grant emergency to Timelock"
            );
        } else {
            console2.log("Timelock already has the emergency role");
        }

        // STEP 3: Grant the "treasuryborrower_cooler" role to the MonoCooler policy
        if (!roles.hasRole(coolerV2, bytes32("treasuryborrower_cooler"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("treasuryborrower_cooler"),
                    coolerV2
                ),
                "Grant treasuryborrower_cooler to MonoCooler"
            );
        } else {
            console2.log("MonoCooler already has the treasuryborrower_cooler role");
        }

        // STEP 4: Disable the Cooler V1 Clearinghouse policy
        _pushAction(
            coolerV1Clearinghouse,
            abi.encodeWithSelector(Clearinghouse.emergencyShutdown.selector),
            "Disable Cooler V1 Clearinghouse"
        );

        // Cooler V2 MonoCooler policy does not needed to be enabled
        // Will not function until the treasury borrower policy is enabled

        // STEP 5: Set the target origination LTV for the Cooler V2 policy
        _pushAction(
            coolerV2LtvOracle,
            abi.encodeWithSelector(
                ICoolerLtvOracle.setOriginationLtvAt.selector,
                uint96(2991256400000000000000),
                uint40(1778803200) // 15th May 2026
            ),
            "Set target origination LTV for Cooler V2"
        );

        // STEP 6: Enable the Cooler V2 Treasury Borrower policy
        _pushAction(
            coolerV2TreasuryBorrower,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, abi.encode("")),
            "Enable Cooler V2 Treasury Borrower"
        );

        // STEP 7: Set the maximum delegate addresses for the hOHM account
        _pushAction(
            coolerV2,
            abi.encodeWithSelector(
                IMonoCooler.setMaxDelegateAddresses.selector,
                hohm,
                MAX_DELEGATE_ADDRESSES
            ),
            "Set max delegate addresses for hOHM"
        );

        // CoolerV2Migrator is owned by the DAO MS, so does not need to be enabled here
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
        // Load the contract addresses
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address timelock = addresses.getAddress("olympus-timelock");
        address emergencyMS = addresses.getAddress("olympus-multisig-emergency");
        address coolerV2 = addresses.getAddress("olympus-policy-cooler-v2");
        address coolerV2TreasuryBorrower = addresses.getAddress(
            "olympus-policy-cooler-v2-treasury-borrower"
        );
        address hohm = addresses.getAddress("hohm");
        address coolerV1Clearinghouse = addresses.getAddress("olympus-policy-clearinghouse-1_2");

        // Validate that the emergency MS has the emergency role
        require(
            roles.hasRole(emergencyMS, bytes32("emergency")),
            "Emergency MS does not have the emergency role"
        );

        // Validate that the OCG timelock has the emergency role
        require(
            roles.hasRole(timelock, bytes32("emergency")),
            "Timelock does not have the emergency role"
        );

        // Validate that the OCG timelock has the admin role
        require(roles.hasRole(timelock, bytes32("admin")), "Timelock does not have the admin role");

        // Validate that the Cooler V2 policy is enabled
        require(IMonoCooler(coolerV2).liquidationsPaused() == false, "Cooler V2 is not enabled");
        require(IMonoCooler(coolerV2).borrowsPaused() == false, "Cooler V2 is not enabled");

        // Validate that the Cooler V2 Treasury Borrower policy is enabled
        require(
            PolicyEnabler(coolerV2TreasuryBorrower).isEnabled(),
            "Cooler V2 Treasury Borrower is not enabled"
        );

        // Validate that the hOHM account has an updated maximum number of delegate addresses
        require(
            IMonoCooler(coolerV2).accountPosition(hohm).maxDelegateAddresses ==
                MAX_DELEGATE_ADDRESSES,
            "hOHM does not have the updated maximum number of delegate addresses"
        );

        // Validate that the Cooler V1 Clearinghouse policy is disabled
        require(
            Clearinghouse(coolerV1Clearinghouse).active() == false,
            "Cooler V1 Clearinghouse is not disabled"
        );
    }
}

contract CoolerV2ProposalScript is ProposalScript {
    constructor() ProposalScript(new CoolerV2Proposal()) {}
}
