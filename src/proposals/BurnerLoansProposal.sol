// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IProposal} from "proposal-sim/proposals/IProposal.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BACKING_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
import {Kernel, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ProposalScript} from "src/proposals/ProposalScript.sol";

/// @notice Launches the deployed and Kernel-prepared Burner Loans stack.
// The deployment script below is the entry point for this specific proposal.
// forge-lint: disable-next-line(multi-contract-file)
contract BurnerLoansProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    function id() public pure override returns (uint256) {
        return 20;
    }

    function name() public pure override returns (string memory) {
        return "Burner Loans";
    }

    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Burner Loans\n\n",
                "## Summary\n\n",
                "This proposal activates the Burner Loans shorting facility. Initial collateral assets are USDS and USDe, held in sUSDS and sUSDe through shared DepositManager v1.1. Borrowers deposit collateral to borrow OHM for fixed terms; collateral must satisfy both the market LTV limit and the OHM backing requirement.\n\n",
                "Both markets launch with an 85% maximum LTV, a 125% backing multiplier, a 30-day term and a 90-day maximum maturity horizon. Each market has a 50,000 OHM debt cap and the facility has a 100,000 OHM global cap. Origination fees are zero at launch. Seizure rewards are 1%, capped at 100 collateral tokens. USDe withdrawals return sUSDe shares because the vault cannot synchronously redeem underlying.\n\n",
                "## Resources\n\n",
                "- Pull request: TBC\n",
                "- Audit report: TBC\n",
                "\n",
                "## Assumptions\n\n",
                "- The reviewed contracts are deployed and recorded in the address registry.\n",
                "- The DAO multisig, as Kernel executor, has installed the OlympusFixedTermLoan (FLOAN) module and activated the following policies without enabling them: DepositManager v1.1 and DepositManagerConfigTimelock; PriceCache; BackingOracle and BackingOracleConfigTimelock; RevenueDistributor, RevenueDistributorConfigTimelock and RevenueDistributorTask; BurnerLoansCore, Config, Inventory, Payout, Risk, Collateral, Debt and Seize; BurnerLoansConfigTimelock, RiskConfigTimelock, PayoutConfigTimelock and InventoryConfigTimelock; BurnerLoansSeizerTask and BurnerLoansYieldClaimerTask.\n",
                "- BurnerLoansAuth, BurnerLoansLens and the one-use BurnerLoansActivator are deployed periphery/helpers, rather than Kernel policies.\n",
                "- Heart and PriceConfigv2 are active and enabled, and Heart already holds HEART_ROLE. PRICE supports OHM and USDS. Heart retains the reviewed six-task order: ConvertibleDepositFacility, ReserveMigrator, ReserveWrapper, Operator, YieldRepurchaseFacility and EmissionManager.\n",
                "- The governance timelock holds ADMIN and controls RolesAdmin. No DAO multisig initial enablement or configuration-operator selection is assumed.\n\n",
                "## Proposal Steps\n\n",
                "1. Grant the custody, settlement and automation roles required by Core, Collateral, Debt, Seize, SeizerTask and YieldClaimerTask. Grant the named lending, inventory, revenue, backing and custody operational roles to the DAO multisig.\n",
                "2. Grant temporary ADMIN to the one-use activator.\n",
                "3. Call the activator atomically. It verifies the prepared Kernel membership, immutable target bindings and fresh disabled state; adds USDe PRICE support if absent; initializes BackingOracle to $11.99 per OHM and selects and enables its configuration timelock.\n",
                "4. Select Core-bound Auth, services and delayed configuration operators. Enable PriceCache, RevenueDistributor, DepositManager v1.1, Inventory, Payout, Risk, Core, Config, Collateral, Debt and Seize in dependency order. Configure Treasury-only routes for USDS, sUSDS, USDe and sUSDe revenue. Select DepositManager's configuration timelock after manager enablement.\n",
                "5. Register USDS/sUSDS and USDe/sUSDe custody routes and markets with the published launch parameters. Enable all six lending/revenue/custody configuration timelocks and the SeizerTask, YieldClaimerTask and RevenueDistributorTask. Insert these tasks at Heart indexes 3, 4 and 5, respectively, after reserve preparation and immediately before Operator. Existing tasks and their selectors retain relative order.\n",
                "6. Revoke the activator ADMIN role in the same governance execution. Any failed action rolls back the entire proposal.\n\n",
                "## Next Steps\n\n",
                "No further governance action is required to enable the configured markets. Yield recipient remains unset and all new revenue goes to Treasury. When YRF V2 is deployed and activated, its own OCG must select the compatible IYieldRepurchaseRecipient through ADMIN before enabling nonzero repurchase allocations. Before borrowers can draw debt, the DAO inventory provider must supply OHM or the delegated lending administrator must configure a Treasury-backed mint limit. Operators must confirm live prices and capacity, then monitor Heart task execution, outstanding debt and collateral custody using the launch runbook.\n"
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
        // Heart is already operational; requiring its existing role saves a Governor action.
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        if (!roles.hasRole(heart, HEART_ROLE))
            revert IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite(heart);
        _grant(
            admin,
            roles,
            DEPOSIT_MANAGER_ADMIN_ROLE,
            addresses.getAddress("olympus-multisig-dao")
        );
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
            roles.hasRole(addresses.getAddress("olympus-multisig-dao"), DEPOSIT_MANAGER_ADMIN_ROLE)
        );
        assert(
            IPRICEv2(address(_kernel.getModuleForKeycode(toKeycode("PRICE")))).isAssetApproved(
                addresses.getAddress("external-tokens-usde")
            )
        );
    }
}

// Keep the script entry point in the existing proposal file.
// forge-lint: disable-next-line(multi-contract-file)
contract BurnerLoansProposalScript is ProposalScript {
    constructor() ProposalScript(IProposal(address(new BurnerLoansProposal()))) {}
}
