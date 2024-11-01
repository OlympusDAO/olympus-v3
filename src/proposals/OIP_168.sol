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

/// @notice OIP-168 migrates the reserve used in the Olympus protocol from DAI to USDS.
// solhint-disable-next-line contract-name-camelcase
contract OIP_168 is GovernorBravoProposal {
    Kernel internal _kernel;

    // TODO set initial yield value
    uint256 public constant INITIAL_YIELD = 0;

    // Returns the id of the proposal.
    function id() public pure override returns (uint256) {
        return 168;
    }

    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "OIP-168";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return
            "# Migrate the reserve token from DAI to USDS\n\n"
            "[Proposal](https://forum.olympusdao.finance/d/4633-oip-168-olympus-treasury-migration-from-daisdai-to-usdssusds)\n\n"
            "## Roles to Assign\n\n"
            "1. `heart` to the new Heart policy (renamed from `operator_operate`)\n"
            "2. `reserve_migrator_admin` to the Timelock and DAO MS\n"
            "3. `callback_whitelist` to the new Operator policy\n\n"
            "## Roles to Revoke\n\n"
            "1. `heart` from the old Heart policy\n"
            "2. `operator_operate` from the old Heart policy\n"
            "3. `callback_whitelist` from the old Operator policy\n\n"
            "## Policy Initialization Steps\n\n"
            "1. Set `BondCallback.operator()` to the new Operator policy\n"
            "2. Set sUSDS as the wrapped token for USDS on BondCallback\n"
            "3. Initialize the new YieldRepurchaseFacility policy\n"
            "4. Initialize the new Operator policy\n"
            "5. Activate the new Clearinghouse policy";
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
        address bondCallback = addresses.getAddress("olympus-policy-bondcallback");
        address operator_1_4 = addresses.getAddress("olympus-policy-operator-1_4");
        address operator_1_5 = addresses.getAddress("olympus-policy-operator-1_5");
        address heart_1_5 = addresses.getAddress("olympus-policy-heart-1_5");
        address heart_1_6 = addresses.getAddress("olympus-policy-heart-1_6");
        address clearinghouse = addresses.getAddress("olympus-policy-clearinghouse-1_2");
        address usds = addresses.getAddress("external-tokens-usds");
        address susds = addresses.getAddress("external-tokens-susds");
        address timelock = addresses.getAddress("olympus-timelock");
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        // STEP 1: Assign roles
        // 1a. Grant "heart" to the new Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart_1_6),
            "Grant heart to new Heart policy"
        );

        // 1b. Grant "reserve_migrator_admin" to the Timelock and DAO MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("reserve_migrator_admin"),
                timelock
            ),
            "Grant reserve_migrator_admin to Timelock"
        );
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("reserve_migrator_admin"),
                daoMS
            ),
            "Grant reserve_migrator_admin to DAO MS"
        );

        // 1c. Grant "callback_whitelist" to the new Operator policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("callback_whitelist"),
                operator_1_5
            ),
            "Grant callback_whitelist to new Operator policy"
        );

        // STEP 2: Revoke roles
        // 2a. Revoke "heart" from the old Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("heart"), heart_1_5),
            "Revoke heart from old Heart policy"
        );

        // 2b. Revoke "operator_operate" from the old Heart policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("operator_operate"),
                heart_1_5
            ),
            "Revoke operator_operate from old Heart policy"
        );

        // 2c. Revoke "callback_whitelist" from the old Operator policy
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("callback_whitelist"),
                operator_1_4
            ),
            "Revoke callback_whitelist from old Operator policy"
        );

        // STEP 3: Policy initialization steps
        // 3a. Set `BondCallback.operator()` to the new Operator policy
        _pushAction(
            bondCallback,
            abi.encodeWithSelector(BondCallback.setOperator.selector, operator_1_5),
            "Set BondCallback.operator() to new Operator policy"
        );

        // 3b. Set sUSDS as the wrapped token for USDS on BondCallback
        _pushAction(
            bondCallback,
            abi.encodeWithSelector(BondCallback.useWrappedVersion.selector, usds, susds),
            "Set sUSDS as the wrapped token for USDS on BondCallback"
        );

        // 3c. Initialize the new YieldRepurchaseFacility policy
        _pushAction(
            yieldRepurchaseFacility,
            abi.encodeWithSelector(
                YieldRepurchaseFacility.initialize.selector,
                0, // initialReserveBalance: will be set in the next epoch
                0, // initialConversionRate: will be set in the next epoch
                INITIAL_YIELD // initialYield
            ),
            "Initialize the new YieldRepurchaseFacility policy"
        );

        // 3d. Initialize the new Operator policy
        _pushAction(
            operator_1_5,
            abi.encodeWithSelector(Operator.initialize.selector),
            "Initialize the new Operator policy"
        );

        // 3e. Activate the new Clearinghouse policy
        _pushAction(
            clearinghouse,
            abi.encodeWithSelector(Clearinghouse.activate.selector),
            "Activate the new Clearinghouse policy"
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
        address bondCallback = addresses.getAddress("olympus-policy-bondcallback");
        address operator_1_4 = addresses.getAddress("olympus-policy-operator-1_4");
        address operator_1_5 = addresses.getAddress("olympus-policy-operator-1_5");
        address heart_1_5 = addresses.getAddress("olympus-policy-heart-1_5");
        address heart_1_6 = addresses.getAddress("olympus-policy-heart-1_6");
        address clearinghouse = addresses.getAddress("olympus-policy-clearinghouse-1_2");
        address usds = addresses.getAddress("external-tokens-usds");
        address susds = addresses.getAddress("external-tokens-susds");

        // Validate the new Heart policy has the "heart" role
        require(
            roles.hasRole(heart_1_6, bytes32("heart")),
            "New Heart policy does not have the heart role"
        );

        // Validate the new Operator policy has the "callback_whitelist" role
        require(
            roles.hasRole(operator_1_5, bytes32("callback_whitelist")),
            "New Operator policy does not have the callback_whitelist role"
        );

        // Validate the old Heart policy does not have the "heart" role
        require(
            !roles.hasRole(heart_1_5, bytes32("heart")),
            "Old Heart policy still has the heart role"
        );

        // Validate the old Heart policy does not have the "operator_operate" role
        require(
            !roles.hasRole(heart_1_5, bytes32("operator_operate")),
            "Old Heart policy still has the operator_operate role"
        );

        // Validate the old Operator policy does not have the "callback_whitelist" role
        require(
            !roles.hasRole(operator_1_4, bytes32("callback_whitelist")),
            "Old Operator policy still has the callback_whitelist role"
        );

        // Validate BondCallback.operator() is set to the new Operator policy
        require(
            address(BondCallback(bondCallback).operator()) == operator_1_5,
            "BondCallback.operator() is not set to the new Operator policy"
        );

        // Validate BondCallback.wrapped() is set to sUSDS for USDS
        require(
            BondCallback(bondCallback).wrapped(usds) == susds,
            "BondCallback.wrapped() is not set to sUSDS for USDS"
        );

        // Validate the new Operator policy is initialized
        require(Operator(operator_1_5).initialized(), "New Operator policy is not initialized");

        // Validate the new YieldRepurchaseFacility policy is initialized
        require(
            YieldRepurchaseFacility(yieldRepurchaseFacility).initialized(),
            "New YieldRepurchaseFacility policy is not initialized"
        );

        // Validate the new Clearinghouse policy is activated
        require(Clearinghouse(clearinghouse).active(), "New Clearinghouse policy is not activated");
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
contract OIP_168_Script is ScriptSuite {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";

    constructor() ScriptSuite(ADDRESSES_PATH, new OIP_168()) {}

    function run() public override {
        // set debug mode to true and run it to build the actions list
        proposal.setDebug(true);

        // run the proposal to build it
        proposal.run(addresses, address(0));

        // get the calldata for the proposal, doing so in debug mode prints it to the console
        proposal.getCalldata();
    }
}
