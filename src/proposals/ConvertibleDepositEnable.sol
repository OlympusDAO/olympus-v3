// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Contracts
import {Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IReserveMigrator} from "src/policies/interfaces/IReserveMigrator.sol";
import {IOperator} from "src/policies/interfaces/IOperator.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

/// @notice Enables the Convertible Deposit contracts
contract ConvertibleDepositEnable is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    string constant CDF_NAME = "cdf";

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 12;
    }

    function name() public pure override returns (string memory) {
        return "Convertible Deposits - Enabling Contracts";
    }

    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Convertible Deposits - Enabling Contracts\n",
                "\n",
                "This is the first out of two proposals related to the Convertible Deposit system. This proposal enables base contracts and performs initial configuration.\n",
                "\n",
                "## Summary\n",
                "\n",
                "This proposal has three main components:\n",
                "- The Convertible Deposit system provides a mechanism for the protocol to operate an auction that is infinite duration and infinite capacity. This proposal enables and configures base layer contracts, with asset configuration deferred to a second proposal.\n",
                "- The ReserveWrapper contract periodically withdraws USDS from the protocol treasury (TRSRY) and wraps it into sUSDS. This proposal enables the contract.\n",
                "- The new version of the Heart contract (1.7) has new functionality to maintain a list of periodic tasks that will be executed with each heartbeat. This proposal adds existing periodic tasks (ReserveMigrator, Operator, YieldRepurchaseFacility) and the new ReserveWrapper.\n",
                "\n",
                "Note: This proposal will leave the system in a state where it is able to perform a heartbeat and execute the normal periodic tasks (excluding the EmissionManager and CD system).\n",
                "\n",
                "## Affected Contracts\n",
                "\n",
                "- Heart policy (new - 1.7)\n",
                "- Heart policy (existing - 1.6)\n",
                "- DepositManager policy (new - 1.0)\n",
                "- ConvertibleDepositFacility policy (new - 1.0)\n",
                "- DepositRedemptionVault policy (new - 1.0)\n",
                "- ReserveWrapper policy (new - 1.0)\n",
                "- ReserveMigrator policy (existing)\n",
                "- Operator policy (existing - 1.5)\n",
                "- YieldRepurchaseFacility policy (existing - 1.3)\n",
                "\n",
                "## Resources\n",
                "\n",
                "- [View the audit report](TODO)\n", // TODO: Add audit report
                "- [View the pull request](https://github.com/OlympusDAO/olympus-v3/pull/29)\n",
                "\n",
                "## Pre-requisites\n",
                "\n",
                "- Old Heart policy has been deactivated in the kernel\n",
                "- Old EmissionManager policy has been deactivated in the kernel\n",
                "- DEPOS module has been installed in the kernel\n",
                "- DepositManager policy has been activated in the kernel\n",
                "- ConvertibleDepositFacility policy has been activated in the kernel\n",
                "- DepositRedemptionVault policy has been activated in the kernel\n",
                "- ReserveWrapper policy has been activated in the kernel\n",
                "- Heart policy has been activated in the kernel\n",
                "\n",
                "## Proposal Steps\n",
                "\n",
                "1. Revoke the `heart` role from the old Heart policy\n",
                "2. Enable DepositManager contract\n",
                "3. Set operator name on DepositManager for ConvertibleDepositFacility\n",
                "4. Grant the `deposit_operator` role to ConvertibleDepositFacility\n",
                "5. Enable ConvertibleDepositFacility contract\n",
                "6. Authorize ConvertibleDepositFacility in DepositRedemptionVault\n",
                "7. Authorize DepositRedemptionVault in ConvertibleDepositFacility\n",
                "8. Enable DepositRedemptionVault contract\n",
                "9. Enable ReserveWrapper contract\n",
                "10. Add ReserveMigrator.migrate() to periodic tasks\n",
                "11. Add ReserveWrapper to periodic tasks\n",
                "12. Add Operator.operate() to periodic tasks\n",
                "13. Add YieldRepurchaseFacility.endEpoch() to periodic tasks\n",
                "14. Grant the `heart` role to Heart contract\n",
                "15. Enable Heart contract\n",
                "\n",
                "## Subsequent Steps\n",
                "\n",
                "A second OCG proposal will configure assets and initialize the auction parameters for the ConvertibleDeposit system.\n"
            );
    }

    // No deploy actions needed
    function _deploy(Addresses addresses, address) internal override {
        // Cache the kernel address in state
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address deployer) internal override {}

    // Sets up actions for the proposal
    function _build(Addresses addresses) internal override {
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        // Get old Heart policy address
        address heartOld = addresses.getAddress("olympus-policy-heart-1_6");

        // Get contract addresses
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
        address cdFacility = addresses.getAddress(
            "olympus-policy-convertible-deposit-facility-1_0"
        );
        address depositRedemptionVault = addresses.getAddress(
            "olympus-policy-deposit-redemption-vault-1_0"
        );
        address reserveWrapper = addresses.getAddress("olympus-policy-reserve-wrapper-1_0");
        address reserveMigrator = addresses.getAddress("olympus-policy-reserve-migrator-1_0");
        address operator = addresses.getAddress("olympus-policy-operator-1_5");
        address yieldRepo = addresses.getAddress("olympus-policy-yieldrepurchasefacility");

        // Pre-requisites:
        // - All required modules and policies have been installed and activated in the kernel
        // - DEPOS module has been installed in the kernel
        // - All deposit-related policies have been activated

        // 1. Revoke "heart" role from old Heart contract
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("heart"), heartOld),
            "Revoke heart role from old Heart policy"
        );

        // 2. Enable DepositManager contract
        _pushAction(
            depositManager,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable DepositManager contract"
        );

        // 3. Set operator name on DepositManager for ConvertibleDepositFacility
        _pushAction(
            depositManager,
            abi.encodeWithSelector(IDepositManager.setOperatorName.selector, cdFacility, CDF_NAME),
            "Set operator name on DepositManager for ConvertibleDepositFacility"
        );

        // 4. Grant "deposit_operator" role to ConvertibleDepositFacility
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("deposit_operator"),
                cdFacility
            ),
            "Grant deposit_operator role to ConvertibleDepositFacility"
        );

        // 5. Enable ConvertibleDepositFacility contract
        _pushAction(
            cdFacility,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable ConvertibleDepositFacility contract"
        );

        // 6. Authorize ConvertibleDepositFacility in DepositRedemptionVault
        _pushAction(
            depositRedemptionVault,
            abi.encodeWithSelector(IDepositRedemptionVault.authorizeFacility.selector, cdFacility),
            "Authorize ConvertibleDepositFacility in DepositRedemptionVault"
        );

        // 7. Authorize DepositRedemptionVault in ConvertibleDepositFacility
        _pushAction(
            cdFacility,
            abi.encodeWithSelector(
                IDepositFacility.authorizeOperator.selector,
                depositRedemptionVault
            ),
            "Authorize DepositRedemptionVault in ConvertibleDepositFacility"
        );

        // 8. Enable DepositRedemptionVault
        _pushAction(
            depositRedemptionVault,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable DepositRedemptionVault"
        );

        // 9. Enable ReserveWrapper
        _pushAction(
            reserveWrapper,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable ReserveWrapper"
        );

        // 10. Add ReserveMigrator.migrate() to periodic tasks
        _pushAction(
            heart,
            abi.encodeWithSelector(
                IPeriodicTaskManager.addPeriodicTaskAtIndex.selector,
                reserveMigrator,
                IReserveMigrator.migrate.selector,
                0 // First task
            ),
            "Add ReserveMigrator.migrate() to periodic tasks"
        );

        // 11. Add ReserveWrapper to periodic tasks
        _pushAction(
            heart,
            abi.encodeWithSelector(IPeriodicTaskManager.addPeriodicTask.selector, reserveWrapper),
            "Add ReserveWrapper to periodic tasks"
        );

        // 12. Add Operator.operate() to periodic tasks
        _pushAction(
            heart,
            abi.encodeWithSelector(
                IPeriodicTaskManager.addPeriodicTaskAtIndex.selector,
                operator,
                IOperator.operate.selector,
                2 // Third task
            ),
            "Add Operator.operate() to periodic tasks"
        );

        // 13. Add YieldRepurchaseFacility.endEpoch() to periodic tasks
        _pushAction(
            heart,
            abi.encodeWithSelector(
                IPeriodicTaskManager.addPeriodicTaskAtIndex.selector,
                yieldRepo,
                IYieldRepo.endEpoch.selector,
                3 // Fourth task
            ),
            "Add YieldRepurchaseFacility.endEpoch() to periodic tasks"
        );

        // 14. Grant "heart" role to Heart contract
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart),
            "Grant heart role to Heart contract"
        );

        // 15. Enable Heart contract
        _pushAction(
            heart,
            abi.encodeWithSelector(IEnabler.enable.selector, ""),
            "Enable Heart contract"
        );

        // If the second proposal isn't executed in time, the Heart will be able to perform a heartbeat.
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
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        address heartOld = addresses.getAddress("olympus-policy-heart-1_6");
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
        address cdFacility = addresses.getAddress(
            "olympus-policy-convertible-deposit-facility-1_0"
        );
        address depositRedemptionVault = addresses.getAddress(
            "olympus-policy-deposit-redemption-vault-1_0"
        );
        address reserveWrapper = addresses.getAddress("olympus-policy-reserve-wrapper-1_0");
        address reserveMigrator = addresses.getAddress("olympus-policy-reserve-migrator-1_0");
        address operator = addresses.getAddress("olympus-policy-operator-1_5");
        address yieldRepo = addresses.getAddress("olympus-policy-yieldrepurchasefacility");

        // solhint-disable custom-errors

        // 1. Validate that the "heart" role is revoked from the old Heart policy
        require(
            roles.hasRole(heartOld, bytes32("heart")) == false,
            "Old Heart policy still has the heart role"
        );

        // 2. Validate that DepositManager is enabled
        require(IEnabler(depositManager).isEnabled() == true, "DepositManager is not enabled");

        // 3. Validate operator name is set
        require(
            keccak256(bytes(IDepositManager(depositManager).getOperatorName(cdFacility))) ==
                keccak256(bytes(CDF_NAME)),
            "DepositManager operator name for ConvertibleDepositFacility is incorrect"
        );

        // 4. Validate that ConvertibleDepositFacility has "deposit_operator" role
        require(
            roles.hasRole(cdFacility, bytes32("deposit_operator")) == true,
            "ConvertibleDepositFacility does not have the deposit_operator role"
        );

        // 5. Validate that ConvertibleDepositFacility is enabled
        require(
            IEnabler(cdFacility).isEnabled() == true,
            "ConvertibleDepositFacility is not enabled"
        );

        // 6. ConvertibleDepositFacility is authorized with DepositRedemptionVault
        require(
            IDepositRedemptionVault(depositRedemptionVault).isAuthorizedFacility(cdFacility) ==
                true,
            "ConvertibleDepositFacility is not an authorized facility with DepositRedemptionVault"
        );

        // 7. DepositRedemptionVault is authorized with ConvertibleDepositFacility
        require(
            IDepositFacility(cdFacility).isAuthorizedOperator(depositRedemptionVault) == true,
            "DepositRedemptionVault is not an authorized operator with ConvertibleDepositFacility"
        );

        // 8. Validate that DepositRedemptionVault is enabled
        require(
            IEnabler(depositRedemptionVault).isEnabled() == true,
            "DepositRedemptionVault is not enabled"
        );

        // 9. Validate that ReserveWrapper is enabled
        require(IEnabler(reserveWrapper).isEnabled() == true, "ReserveWrapper is not enabled");

        // 10-13. Validate periodic tasks are added to Heart
        // Check that Heart has the expected number of periodic tasks
        require(
            IPeriodicTaskManager(heart).getPeriodicTaskCount() == 4,
            "Heart does not have the expected number of periodic tasks"
        );

        // Validate specific periodic tasks are set (requires checking task addresses)
        (address[] memory periodicTasks, ) = IPeriodicTaskManager(heart).getPeriodicTasks();
        require(
            periodicTasks[0] == reserveMigrator,
            "ReserveMigrator is not the first periodic task"
        );

        require(
            periodicTasks[1] == reserveWrapper,
            "ReserveWrapper is not the second periodic task"
        );

        require(periodicTasks[2] == operator, "Operator is not the third periodic task");

        require(
            periodicTasks[3] == yieldRepo,
            "YieldRepurchaseFacility is not the fourth periodic task"
        );

        // 14. Validate that Heart has the "heart" role
        require(
            roles.hasRole(heart, bytes32("heart")) == true,
            "Heart does not have the heart role"
        );

        // 15. Validate that Heart is enabled
        require(IEnabler(heart).isEnabled() == true, "Heart is not enabled");

        // Validate that all policies are active
        require(Policy(depositManager).isActive() == true, "DepositManager policy is not active");
        require(
            Policy(cdFacility).isActive() == true,
            "ConvertibleDepositFacility policy is not active"
        );
        require(
            Policy(depositRedemptionVault).isActive() == true,
            "DepositRedemptionVault policy is not active"
        );
        require(Policy(reserveWrapper).isActive() == true, "ReserveWrapper policy is not active");
        require(Policy(heart).isActive() == true, "Heart policy is not active");
    }
}

// solhint-disable-next-line contract-name-camelcase
contract ConvertibleDepositEnableProposalScript is ProposalScript {
    constructor() ProposalScript(new ConvertibleDepositEnable()) {}
}
