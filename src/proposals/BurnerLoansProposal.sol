// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IProposal} from "proposal-sim/proposals/IProposal.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BACKING_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE, EMERGENCY_ROLE, HEART_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
import {Kernel, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ProposalScript} from "src/proposals/ProposalScript.sol";

/// @notice Launches the deployed and Kernel-prepared Burner Loans stack.
contract BurnerLoansProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    function id() public pure override returns (uint256) {
        return 20;
    }

    function name() public pure override returns (string memory) {
        return "Burner Loans - Activation";
    }

    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Burner Loans Activation\n\n",
                "This proposal launches USDS and USDe lending markets, configures shared DepositManager v1.1 and revenue routing, and delegates DAO operational authority.\n\n",
                "## Resources\n\n",
                "- Parameters: documentation/burner_loans_launch_parameters.md\n",
                "- Deployment and operations: documentation/burner_loans_launch_runbook.md\n\n",
                "## Assumptions\n\n",
                "- The reviewed contracts are deployed; FLOAN is installed and the new policies are Kernel-active but have never been enabled.\n",
                "- BackingOracle and its queue are separately deployed and configured; the oracle is active, enabled and populated.\n",
                "- Heart and PriceConfigv2 are active and enabled; compatible PRICE supports OHM and USDS.\n",
                "- The governance timelock holds ADMIN and controls RolesAdmin.\n\n",
                "## Proposal Steps\n\n",
                "1. Grant custody, settlement and automation roles; grant DAO lending, inventory-provider, distributor and backing administration roles.\n",
                "2. Grant temporary ADMIN to the one-use activator.\n",
                "3. Activate the reviewed launch: admit USDe into PRICE if absent, configure USDS/sUSDS and USDe/sUSDe custody, select Core-bound Auth, services and timelocks, configure and enable both markets, and set up Heart tasks.\n",
                "4. Revoke activator ADMIN in the same execution.\n\n",
                "Heart order becomes Seizer, Yield, RevenueDistributorTask, then the six existing tasks in their original order. Market parameters and exact task indexes are recorded in the linked documents."
            );
    }

    // Deployment and Kernel membership are prepared before this proposal.
    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses, address) internal pure override {
        return;
    }

    function _build(Addresses addresses) internal override {
        RolesAdmin admin = RolesAdmin(addresses.getAddress("olympus-policy-roles-admin"));
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address activator = addresses.getAddress("olympus-proposal-burner-loans-activator");

        // STEP 1: Install permanent operational roles. Core needs custody authority, action
        // policies need settlement authority, and the DAO needs delegated administration.
        // These grants remain after launch; only the activator's ADMIN below is temporary.
        _grant(
            admin,
            roles,
            DEPOSIT_OPERATOR_ROLE,
            addresses.getAddress("olympus-policy-burner-loans-core")
        );
        _grant(
            admin,
            roles,
            BL_COLLATERAL_POLICY_ROLE,
            addresses.getAddress("olympus-policy-burner-loans-collateral")
        );
        _grant(
            admin,
            roles,
            BL_DEBT_POLICY_ROLE,
            addresses.getAddress("olympus-policy-burner-loans-debt")
        );
        _grant(
            admin,
            roles,
            BL_LIQUIDATION_POLICY_ROLE,
            addresses.getAddress("olympus-policy-burner-loans-seize")
        );
        _grant(
            admin,
            roles,
            BL_YIELD_CLAIMER_ROLE,
            addresses.getAddress("olympus-policy-burner-loans-yield-claimer-task")
        );
        _grant(
            admin,
            roles,
            BURNER_LOANS_SEIZER_ROLE,
            addresses.getAddress("olympus-policy-burner-loans-seizer-task")
        );
        _grant(admin, roles, BURNER_LOANS_ADMIN_ROLE, addresses.getAddress("olympus-multisig-dao"));
        _grant(
            admin,
            roles,
            BURNER_LOANS_INVENTORY_PROVIDER_ROLE,
            addresses.getAddress("olympus-multisig-dao")
        );
        _grant(
            admin,
            roles,
            REVENUE_DISTRIBUTOR_ADMIN_ROLE,
            addresses.getAddress("olympus-multisig-dao")
        );
        _grant(admin, roles, BACKING_ADMIN_ROLE, addresses.getAddress("olympus-multisig-dao"));
        _grant(admin, roles, HEART_ROLE, addresses.getAddress("olympus-policy-heart-1_7"));
        _grant(admin, roles, EMERGENCY_ROLE, addresses.getAddress("olympus-multisig-emergency"));

        // STEP 2: Grant the only temporary role immediately before using it. The activator
        // needs ADMIN to configure several independent policies and PRICE in one call.
        _pushAction(
            address(admin),
            abi.encodeCall(RolesAdmin.grantRole, (ADMIN_ROLE, activator)),
            "Grant activator ADMIN"
        );

        // STEP 3: The timelock invokes the one-use activator. Its own address is the caller
        // of downstream setters, so its temporary ADMIN supplies their required authority.
        _pushAction(
            activator,
            abi.encodeCall(IBurnerLoansActivator.activate, ()),
            "Activate Burner Loans"
        );

        // STEP 4: Always revoke temporary ADMIN as the final proposal action. RolesAdmin
        // is controlled by the timelock, so cleanup belongs here rather than in the activator.
        // Governor executes the action list in one transaction: a failed launch or revocation
        // rolls back every preceding action, including the temporary grant.
        _pushAction(
            address(admin),
            abi.encodeCall(RolesAdmin.revokeRole, (ADMIN_ROLE, activator)),
            "Revoke activator ADMIN"
        );
    }

    // Existing permanent roles are retained without duplicate grants. Temporary ADMIN uses
    // explicit grant/revoke actions above so its complete lifetime is visible in the proposal.
    function _grant(RolesAdmin admin, ROLESv1 roles, bytes32 role, address wallet) private {
        if (!roles.hasRole(wallet, role)) {
            _pushAction(
                address(admin),
                abi.encodeCall(RolesAdmin.grantRole, (role, wallet)),
                "Grant launch role"
            );
        }
    }

    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    function _validate(Addresses addresses, address) internal view override {
        address activator = addresses.getAddress("olympus-proposal-burner-loans-activator");
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        // Simulation must prove both successful initialization and removal of launch-only
        // authority. DAO operators retain their named roles without receiving broad ADMIN.
        assert(IBurnerLoansActivator(activator).isActivated());
        assert(!roles.hasRole(activator, ADMIN_ROLE));
        assert(!roles.hasRole(addresses.getAddress("olympus-multisig-dao"), ADMIN_ROLE));
        assert(roles.hasRole(addresses.getAddress("olympus-multisig-dao"), BACKING_ADMIN_ROLE));
        assert(
            IPRICEv2(address(_kernel.getModuleForKeycode(toKeycode("PRICE")))).isAssetApproved(
                addresses.getAddress("external-tokens-usde")
            )
        );
    }
}

contract BurnerLoansProposalScript is ProposalScript {
    constructor() ProposalScript(IProposal(address(new BurnerLoansProposal()))) {}
}
