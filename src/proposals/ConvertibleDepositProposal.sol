// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
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
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IReserveMigrator} from "src/policies/interfaces/IReserveMigrator.sol";
import {IOperator} from "src/policies/interfaces/IOperator.sol";
import {IYieldRepo} from "src/policies/interfaces/IYieldRepo.sol";
import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

/// @notice Combined proposal that enables and configures the Convertible Deposit system
contract ConvertibleDepositProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    address public constant ACTIVATOR = 0x0000000000000000000000000000000000000000;

    string internal constant CDF_NAME = "cdf";

    // Asset configuration
    uint256 internal constant USDS_MAX_CAPACITY = 1_000_000e18; // 1M USDS
    uint256 internal constant USDS_MIN_DEPOSIT = 1e18; // 1 USDS

    // Deposit periods (in months)
    uint8 internal constant PERIOD_1M = 1;
    uint8 internal constant PERIOD_2M = 2;
    uint8 internal constant PERIOD_3M = 3;

    // Reclaim rate (in basis points)
    uint16 internal constant RECLAIM_RATE = 90e2; // 90%

    // ConvertibleDepositAuctioneer initial parameters
    uint256 internal constant CDA_INITIAL_TARGET = 0;
    uint256 internal constant CDA_INITIAL_TICK_SIZE = 0;
    uint256 internal constant CDA_INITIAL_MIN_PRICE = 0;
    uint24 internal constant CDA_INITIAL_TICK_STEP_MULTIPLIER = 10075; // 0.75% increase
    uint8 internal constant CDA_AUCTION_TRACKING_PERIOD = 7; // 7 days

    // EmissionManager parameters
    uint256 internal constant EM_BASE_EMISSIONS_RATE = 200000; // 0.02%/day
    uint256 internal constant EM_MINIMUM_PREMIUM = 1e18; // 100% premium
    uint256 internal constant EM_BACKING = 11740000000000000000; // 11.74 USDS/OHM
    uint256 internal constant EM_TICK_SIZE = 150e9; // 150 OHM
    uint256 internal constant EM_MIN_PRICE_SCALAR = 1e18; // 100% min price multiplier
    uint48 internal constant EM_RESTART_TIMEFRAME = 950400; // 11 days

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        return 12;
    }

    function name() public pure override returns (string memory) {
        return "Convertible Deposits - Activation";
    }

    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Convertible Deposits - Complete Activation\n",
                "\n",
                "This proposal combines the enabling of Convertible Deposit contracts with asset configuration into a single atomic operation.\n",
                "\n",
                "## Summary\n",
                "\n",
                "This proposal has four main components:\n",
                "- Enable base Convertible Deposit system contracts and perform initial configuration\n",
                "- Configure USDS assets with different deposit periods (1m, 2m, 3m)\n",
                "- Enable the ReserveWrapper contract for periodic USDS wrapping to sUSDS\n",
                "- Configure the new Heart contract (1.7) with all necessary periodic tasks\n",
                "- Enable the EmissionManager and ConvertibleDepositAuctioneer for full system operation\n",
                "\n",
                "## Affected Contracts\n",
                "\n",
                "- Heart policy (new - 1.7)\n",
                "- Heart policy (existing - 1.6)\n",
                "- DepositManager policy (new - 1.0)\n",
                "- ConvertibleDepositFacility policy (new - 1.0)\n",
                "- ConvertibleDepositAuctioneer policy (new - 1.0)\n",
                "- DepositRedemptionVault policy (new - 1.0)\n",
                "- ReserveWrapper policy (new - 1.0)\n",
                "- EmissionManager policy (existing - 1.2)\n",
                "- ReserveMigrator policy (existing)\n",
                "- Operator policy (existing - 1.5)\n",
                "- YieldRepurchaseFacility policy (existing - 1.3)\n",
                "\n",
                "## Resources\n" //,
                // "\n",
                // "- [View the audit report](TODO)\n", // TODO: Add audit report
                // "- [View the pull request](https://github.com/OlympusDAO/olympus-v3/pull/29)\n",
                // "\n",
                // "## Pre-requisites\n",
                // "\n",
                // "- Old Heart policy has been deactivated in the kernel\n",
                // "- Old EmissionManager policy has been deactivated in the kernel\n",
                // "- DEPOS module has been installed in the kernel\n",
                // "- All new deposit-related policies have been activated in the kernel\n",
                // "- New Heart policy has been activated in the kernel\n",
                // "- New EmissionManager policy has been activated in the kernel\n",
                // "\n",
                // "## Proposal Steps\n",
                // "\n",
                // "### Phase 1: Base System Enablement (15 steps)\n",
                // "1. Revoke the `heart` role from the old Heart policy\n",
                // "2. Enable DepositManager contract\n",
                // "3. Set operator name on DepositManager for ConvertibleDepositFacility\n",
                // "4. Grant the `deposit_operator` role to ConvertibleDepositFacility\n",
                // "5. Enable ConvertibleDepositFacility contract\n",
                // "6. Authorize ConvertibleDepositFacility in DepositRedemptionVault\n",
                // "7. Authorize DepositRedemptionVault in ConvertibleDepositFacility\n",
                // "8. Enable DepositRedemptionVault contract\n",
                // "9. Enable ReserveWrapper contract\n",
                // "10. Add ReserveMigrator.migrate() to periodic tasks\n",
                // "11. Add ReserveWrapper to periodic tasks\n",
                // "12. Add Operator.operate() to periodic tasks\n",
                // "13. Add YieldRepurchaseFacility.endEpoch() to periodic tasks\n",
                // "14. Grant the `heart` role to Heart contract\n",
                // "15. Enable Heart contract\n",
                // "\n",
                // "### Phase 2: Asset Configuration (13 steps)\n",
                // "16. Grant the `manager` role to the DAO MS\n",
                // "17. Configure USDS in DepositManager\n",
                // "18. Add USDS-1m to DepositManager\n",
                // "19. Enable USDS-1m in ConvertibleDepositAuctioneer\n",
                // "20. Add USDS-2m to DepositManager\n",
                // "21. Enable USDS-2m in ConvertibleDepositAuctioneer\n",
                // "22. Add USDS-3m to DepositManager\n",
                // "23. Enable USDS-3m in ConvertibleDepositAuctioneer\n",
                // "24. Grant the `cd_auctioneer` role to ConvertibleDepositAuctioneer\n",
                // "25. Enable ConvertibleDepositAuctioneer (with disabled auction)\n",
                // "26. Grant the `cd_emissionmanager` role to EmissionManager\n",
                // "27. Add EmissionManager to periodic tasks\n",
                // "28. Enable EmissionManager\n",
                // "\n",
                // "## Result\n",
                // "\n",
                // "After execution, the Convertible Deposit system will be fully operational with USDS assets configured for 1, 2, and 3 month deposit periods.\n"
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

        // Pre-requisites:
        // - All required modules and policies have been installed and activated in the kernel
        // - DEPOS module has been installed in the kernel
        // - All deposit-related policies have been activated

        // ========== PHASE 1: CLEAN UP PREVIOUS POLICIES ========== //

        {
            address heartOld = addresses.getAddress("olympus-policy-heart-1_6");

            // 1. Revoke "heart" role from old Heart contract
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("heart"), heartOld),
                "Revoke heart role from old Heart policy"
            );

            // 2. Disable old Heart contract
            _pushAction(
                heartOld,
                abi.encodeWithSignature("deactivate()"),
                "Disable previous version of Heart"
            );
        }

        // 3. Disable old EmissionManager contract
        {
            address emissionManagerOld = addresses.getAddress("olympus-policy-emissionmanager");
            _pushAction(
                emissionManagerOld,
                abi.encodeWithSignature("shutdown()"),
                "Disable previous version of EmissionManager"
            );
        }

        // ========== PHASE 2: GRANT ROLES TO NEW POLICIES ========== //

        // 16. Grant "manager" role to DAO MS
        {
            address daoMS = addresses.getAddress("olympus-multisig-dao");
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("manager"), daoMS),
                "Grant manager role to DAO MS"
            );
        }

        // 2. Grant "deposit_operator" role to ConvertibleDepositFacility
        {
            address cdFacility = addresses.getAddress(
                "olympus-policy-convertible-deposit-facility-1_0"
            );

            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("deposit_operator"),
                    cdFacility
                ),
                "Grant deposit_operator role to ConvertibleDepositFacility"
            );
        }

        // 24. Grant "cd_auctioneer" role to ConvertibleDepositAuctioneer
        {
            address cdAuctioneer = addresses.getAddress(
                "olympus-policy-convertible-deposit-auctioneer-1_0"
            );

            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("cd_auctioneer"),
                    cdAuctioneer
                ),
                "Grant cd_auctioneer role to ConvertibleDepositAuctioneer"
            );
        }

        // 26. Grant "cd_emissionmanager" role to EmissionManager
        {
            address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");

            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("cd_emissionmanager"),
                    emissionManager
                ),
                "Grant cd_emissionmanager role to EmissionManager"
            );
        }

        // 14. Grant "heart" role to Heart contract
        {
            address heart = addresses.getAddress("olympus-policy-heart-1_7");

            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart),
                "Grant heart role to Heart contract"
            );
        }

        // ========== PHASE 3: EXECUTE ACTIVATOR CONTRACT ========== //

        // Grant "admin" role (temporarily) to Activator contract
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("admin"), ACTIVATOR),
            "Grant admin role to temporary activator contract"
        );

        // Run activator
        _pushAction(
            ACTIVATOR,
            abi.encodeWithSignature("activate()"),
            "Call temporary activator contract"
        );

        // Revoke "admin" role from Activator contract
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("admin"), ACTIVATOR),
            "Revoke admin role from temporary activator contract"
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

        // TODO should validate everything

        // address daoMS = addresses.getAddress("olympus-multisig-dao");
        // address heartOld = addresses.getAddress("olympus-policy-heart-1_6");
        // address heart = addresses.getAddress("olympus-policy-heart-1_7");
        // address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
        // address cdFacility = addresses.getAddress(
        //     "olympus-policy-convertible-deposit-facility-1_0"
        // );
        // address cdAuctioneer = addresses.getAddress(
        //     "olympus-policy-convertible-deposit-auctioneer-1_0"
        // );
        // address depositRedemptionVault = addresses.getAddress(
        //     "olympus-policy-deposit-redemption-vault-1_0"
        // );
        // address reserveWrapper = addresses.getAddress("olympus-policy-reserve-wrapper-1_0");
        // address reserveMigrator = addresses.getAddress("olympus-policy-reserve-migrator-1_0");
        // address operator = addresses.getAddress("olympus-policy-operator-1_5");
        // address yieldRepo = addresses.getAddress("olympus-policy-yieldrepurchasefacility");
        // address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");

        // address usds = addresses.getAddress("external-tokens-USDS");
        // address sUsds = addresses.getAddress("external-tokens-sUSDS");

        // solhint-disable custom-errors

        // ========== PHASE 1 VALIDATIONS ========== //

        // // 1. Validate that the "heart" role is revoked from the old Heart policy
        // require(
        //     roles.hasRole(heartOld, bytes32("heart")) == false,
        //     "Old Heart policy still has the heart role"
        // );

        // // 2. Validate that DepositManager is enabled
        // require(IEnabler(depositManager).isEnabled() == true, "DepositManager is not enabled");

        // // 3. Validate operator name is set
        // require(
        //     keccak256(bytes(IDepositManager(depositManager).getOperatorName(cdFacility))) ==
        //         keccak256(bytes(CDF_NAME)),
        //     "DepositManager operator name for ConvertibleDepositFacility is incorrect"
        // );

        // // 4. Validate that ConvertibleDepositFacility has "deposit_operator" role
        // require(
        //     roles.hasRole(cdFacility, bytes32("deposit_operator")) == true,
        //     "ConvertibleDepositFacility does not have the deposit_operator role"
        // );

        // // 5. Validate that ConvertibleDepositFacility is enabled
        // require(
        //     IEnabler(cdFacility).isEnabled() == true,
        //     "ConvertibleDepositFacility is not enabled"
        // );

        // // 6. ConvertibleDepositFacility is authorized with DepositRedemptionVault
        // require(
        //     IDepositRedemptionVault(depositRedemptionVault).isAuthorizedFacility(cdFacility) ==
        //         true,
        //     "ConvertibleDepositFacility is not an authorized facility with DepositRedemptionVault"
        // );

        // // 7. DepositRedemptionVault is authorized with ConvertibleDepositFacility
        // require(
        //     IDepositFacility(cdFacility).isAuthorizedOperator(depositRedemptionVault) == true,
        //     "DepositRedemptionVault is not an authorized operator with ConvertibleDepositFacility"
        // );

        // // 8. Validate that DepositRedemptionVault is enabled
        // require(
        //     IEnabler(depositRedemptionVault).isEnabled() == true,
        //     "DepositRedemptionVault is not enabled"
        // );

        // // 9. Validate that ReserveWrapper is enabled
        // require(IEnabler(reserveWrapper).isEnabled() == true, "ReserveWrapper is not enabled");

        // // 10-13. Validate periodic tasks are added to Heart
        // // Check that Heart has the expected number of periodic tasks (5 total now with EmissionManager)
        // require(
        //     IPeriodicTaskManager(heart).getPeriodicTaskCount() == 5,
        //     "Heart does not have the expected number of periodic tasks"
        // );

        // // Validate specific periodic tasks are set
        // (address[] memory periodicTasks, ) = IPeriodicTaskManager(heart).getPeriodicTasks();
        // require(
        //     periodicTasks[0] == reserveMigrator,
        //     "ReserveMigrator is not the first periodic task"
        // );

        // require(
        //     periodicTasks[1] == reserveWrapper,
        //     "ReserveWrapper is not the second periodic task"
        // );

        // require(periodicTasks[2] == operator, "Operator is not the third periodic task");

        // require(
        //     periodicTasks[3] == yieldRepo,
        //     "YieldRepurchaseFacility is not the fourth periodic task"
        // );

        // require(
        //     periodicTasks[4] == emissionManager,
        //     "EmissionManager is not the fifth periodic task"
        // );

        // // 14. Validate that Heart has the "heart" role
        // require(
        //     roles.hasRole(heart, bytes32("heart")) == true,
        //     "Heart does not have the heart role"
        // );

        // // 15. Validate that Heart is enabled
        // require(IEnabler(heart).isEnabled() == true, "Heart is not enabled");

        // // ========== PHASE 2 VALIDATIONS ========== //

        // // 16. Validate that DAO MS has "manager" role
        // require(
        //     roles.hasRole(daoMS, bytes32("manager")) == true,
        //     "DAO MS does not have the manager role"
        // );

        // // 17. Validate USDS is configured in DepositManager
        // require(
        //     IAssetManager(depositManager).getAssetConfiguration(IERC20(usds)).isConfigured == true,
        //     "USDS is not registered in DepositManager"
        // );

        // // 18-23. Validate asset periods are configured
        // require(
        //     IDepositManager(depositManager).isAssetPeriod(IERC20(usds), PERIOD_1M, cdFacility).isConfigured == true,
        //     "USDS-1m is not registered in DepositManager"
        // );

        // require(
        //     IDepositManager(depositManager).isAssetPeriod(IERC20(usds), PERIOD_2M, cdFacility).isConfigured == true,
        //     "USDS-2m is not registered in DepositManager"
        // );

        // require(
        //     IDepositManager(depositManager).isAssetPeriod(IERC20(usds), PERIOD_3M, cdFacility).isConfigured == true,
        //     "USDS-3m is not registered in DepositManager"
        // );

        // // 24. Validate that ConvertibleDepositAuctioneer has "cd_auctioneer" role
        // require(
        //     roles.hasRole(cdAuctioneer, bytes32("cd_auctioneer")) == true,
        //     "ConvertibleDepositAuctioneer does not have the cd_auctioneer role"
        // );

        // // 25. Validate that ConvertibleDepositAuctioneer is enabled
        // require(
        //     IEnabler(cdAuctioneer).isEnabled() == true,
        //     "ConvertibleDepositAuctioneer is not enabled"
        // );

        // // 26. Validate that EmissionManager has "cd_emissionmanager" role
        // require(
        //     roles.hasRole(emissionManager, bytes32("cd_emissionmanager")) == true,
        //     "EmissionManager does not have the cd_emissionmanager role"
        // );

        // // 28. Validate that EmissionManager is enabled
        // require(IEnabler(emissionManager).isEnabled() == true, "EmissionManager is not enabled");

        // // Validate that all policies are active
        // require(Policy(depositManager).isActive() == true, "DepositManager policy is not active");
        // require(
        //     Policy(cdFacility).isActive() == true,
        //     "ConvertibleDepositFacility policy is not active"
        // );
        // require(
        //     Policy(cdAuctioneer).isActive() == true,
        //     "ConvertibleDepositAuctioneer policy is not active"
        // );
        // require(
        //     Policy(depositRedemptionVault).isActive() == true,
        //     "DepositRedemptionVault policy is not active"
        // );
        // require(Policy(reserveWrapper).isActive() == true, "ReserveWrapper policy is not active");
        // require(Policy(heart).isActive() == true, "Heart policy is not active");
        // require(Policy(emissionManager).isActive() == true, "EmissionManager policy is not active");
    }
}

// solhint-disable-next-line contract-name-camelcase
contract ConvertibleDepositProposalScript is ProposalScript {
    constructor() ProposalScript(new ConvertibleDepositProposal()) {}
}
