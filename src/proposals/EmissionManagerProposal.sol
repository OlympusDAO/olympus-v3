// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import {console2} from "forge-std/console2.sol";
import {ScriptSuite} from "proposal-sim/script/ScriptSuite.s.sol";

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";
// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
// Olympus Kernel, Modules, and Policies
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {GovernorBravoDelegate} from "src/external/governance/GovernorBravoDelegate.sol";
import {BondCallback} from "src/policies/BondCallback.sol";
import {Operator} from "src/policies/Operator.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {YieldRepurchaseFacility} from "src/policies/YieldRepurchaseFacility.sol";
import {EmissionManager} from "src/policies/EmissionManager.sol";

/// @notice Initializes the EmissionManager policy
contract EmissionManagerProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    /// @notice The base emission rate, in OHM scale. Set to 0.02%.
    uint256 public constant BASE_EMISSIONS_RATE = 2e5;
    /// @notice The minimum premium, where 100% = 1e18. Set to 100%.
    uint256 public constant MINIMUM_PREMIUM = 1e18;
    // TODO fill in values
    uint256 public constant BACKING = 0;
    uint48 public constant RESTART_TIMEFRAME = 0;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        // 3: ReserveMigrator/OIP-168
        return 4;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "Initialize Emissions Manager";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Initialize Emissions Manager Policy\n",
                "\n",
                "## Summary\n",
                "Install the Emissions Manager into the protocol, providing it with minter privileges to allow it to emit new supply.\n",
                "\n",
                "## Justification\n",
                "The Emissions Manager allows the protocol to grow treasury, backing, and supply upon an increase in demand for OHM sufficient to push higher premiums.\n",
                "\n",
                "## Description\n",
                "\n",
                "This proposal will result in the following:\n",
                "- Activation of the new EmissionManager policy\n",
                "\n",
                "## Resources\n",
                "\n",
                "- [Read the forum proposal](https://forum.olympusdao.finance/d/4656-install-emissions-manager) for more context.\n",
                "- The EmissionManager policy has been audited. [Read the audit report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2024_11_EmissionManager_ReserveMigrator.pdf)\n",
                "- The code changes can be found in pull request [#18](https://github.com/OlympusDAO/olympus-v3/pull/18)\n",
                "- The proposal can be found in pull request [#21](https://github.com/OlympusDAO/olympus-v3/pull/21)\n",
                "\n",
                "## Roles to Assign\n",
                "\n",
                "1. `emissions_admin` to the Timelock\n",
                "\n",
                "## Policy Initialization Steps\n",
                "\n",
                "1. Initialize the new EmissionManager policy"
            );
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // NOTE: In its current form, OCG is limited to admin roles when it refers to interactions with
    //       exsting policies and modules. Nevertheless, the DAO MS is still the Kernel executor.
    //       Because of that, OCG can't interact (un/install policies/modules) with the Kernel, yet.

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        // Load the roles admin contract
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");

        // Load variables
        address timelock = addresses.getAddress("olympus-timelock");
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager");

        // STEP 1: Assign roles
        // 1a. Grant "emissions_admin" to the Timelock
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emissions_admin"),
                timelock
            ),
            "Grant emissions_admin to Timelock"
        );

        // STEP 2: Policy initialization steps
        // 2a. Initialize the new EmissionManager policy
        _pushAction(
            emissionManager,
            abi.encodeWithSelector(
                EmissionManager.initialize.selector,
                BASE_EMISSIONS_RATE,
                MINIMUM_PREMIUM,
                BACKING,
                RESTART_TIMEFRAME
            ),
            "Initialize the new EmissionManager policy"
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
        // Load the contract addresses
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address heart_1_6 = addresses.getAddress("olympus-policy-heart-1_6");
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager");

        // Validate the new Heart policy has the "heart" role
        require(
            roles.hasRole(heart_1_6, bytes32("heart")),
            "New Heart policy does not have the heart role"
        );

        // Validate the Timelock has the "emissions_admin" role
        require(
            roles.hasRole(emissionManager, bytes32("emissions_admin")),
            "Timelock does not have the emissions_admin role"
        );

        // Validate the new EmissionManager policy is initialized
        require(
            EmissionManager(emissionManager).locallyActive(),
            "New EmissionManager policy is not initialized"
        );

        // Validate the new EmissionManager policy has the correct parameters
        require(
            EmissionManager(emissionManager).baseEmissionRate() == BASE_EMISSIONS_RATE,
            "New EmissionManager policy has incorrect baseEmissionRate"
        );
        require(
            EmissionManager(emissionManager).minimumPremium() == MINIMUM_PREMIUM,
            "New EmissionManager policy has incorrect minimumPremium"
        );
        require(
            EmissionManager(emissionManager).backing() == BACKING,
            "New EmissionManager policy has incorrect backing"
        );
        require(
            EmissionManager(emissionManager).restartTimeframe() == RESTART_TIMEFRAME,
            "New EmissionManager policy has incorrect restartTimeframe"
        );
    }
}

/// @notice GovernorBravoScript is a script that runs BRAVO_01 proposal.
///         BRAVO_01 proposal deploys a Vault contract and an ERC20 token contract
///         Then the proposal transfers ownership of both Vault and ERC20 to the timelock address
///         Finally the proposal whitelist the ERC20 token in the Vault contract
/// @dev    Use this script to simulates or run a single proposal
///         Use this as a template to create your own script
///         `forge script script/GovernorBravo.s.sol:GovernorBravoScript -vvvv --rpc-url {rpc} --broadcast --verify --etherscan-api-key {key}`
// solhint-disable-next-line contract-name-camelcase
contract EmissionManagerProposalScript is ScriptSuite {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";

    constructor() ScriptSuite(ADDRESSES_PATH, new EmissionManagerProposal()) {}

    function run() public override {
        // set debug mode to true and run it to build the actions list
        proposal.setDebug(true);

        // run the proposal to build it
        proposal.run(addresses, address(0));

        // get the calldata for the proposal, doing so in debug mode prints it to the console
        proposal.getCalldata();
    }
}
