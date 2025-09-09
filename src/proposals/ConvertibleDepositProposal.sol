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
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

import {ConvertibleDepositActivator} from "src/proposals/ConvertibleDepositActivator.sol";

/// @notice Combined proposal that enables and configures the Convertible Deposit system
contract ConvertibleDepositProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

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
                _getHeaderSection(),
                _getContractsSection(),
                _getResourcesAndPrerequisitesSection(),
                _getProposalStepsSection(),
                _getConclusionSection()
            );
    }

    /// @dev Returns the header and summary section of the proposal description
    function _getHeaderSection() private pure returns (string memory) {
        return
            string.concat(
                "# Convertible Deposits - Complete Activation\n\n",
                "This proposal combines the enabling of Convertible Deposit contracts with asset configuration into a single atomic operation.\n\n",
                "## Summary\n\n",
                "This proposal has four main components:\n",
                "- Enable base Convertible Deposit system contracts and perform initial configuration\n",
                "- Configure USDS assets with different deposit periods (1m, 2m, 3m)\n",
                "- Enable the ReserveWrapper contract for periodic USDS wrapping to sUSDS\n",
                "- Configure the new Heart contract (1.7) with all necessary periodic tasks\n",
                "- Enable the EmissionManager and ConvertibleDepositAuctioneer for full system operation\n\n"
            );
    }

    /// @dev Returns the affected contracts section of the proposal description
    function _getContractsSection() private pure returns (string memory) {
        return
            string.concat(
                "## Affected Contracts\n\n",
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
                "- YieldRepurchaseFacility policy (existing - 1.3)\n\n"
            );
    }

    /// @dev Returns the resources and prerequisites section of the proposal description
    function _getResourcesAndPrerequisitesSection() private pure returns (string memory) {
        return
            string.concat(
                "## Resources\n\n",
                "- [View the audit report](TODO)\n", // TODO: Add audit report
                "- [View the pull request](https://github.com/OlympusDAO/olympus-v3/pull/29)\n\n",
                "## Pre-requisites\n\n",
                "- Old Heart policy has been deactivated in the kernel\n",
                "- Old EmissionManager policy has been deactivated in the kernel\n",
                "- DEPOS module has been installed in the kernel\n",
                "- All new deposit-related policies have been activated in the kernel\n",
                "- New Heart policy has been activated in the kernel\n",
                "- New EmissionManager policy has been activated in the kernel\n\n"
            );
    }

    /// @dev Returns the proposal steps section of the proposal description
    function _getProposalStepsSection() private pure returns (string memory) {
        return
            string.concat(
                _getProposalStepsPhase1and2(),
                _getProposalStepsPhase3Part1(),
                _getProposalStepsPhase3Part2()
            );
    }

    /// @dev Returns Phase 1 and 2 of the proposal steps
    function _getProposalStepsPhase1and2() private pure returns (string memory) {
        return
            string.concat(
                "## Proposal Steps\n\n",
                "### Phase 1: Cleanup Previous Policies\n",
                "1. Revoke the `heart` role from the old Heart policy\n\n",
                "### Phase 2: Grant Roles to New Policies\n",
                "2. Grant the `manager` role to the DAO MS\n",
                "3. Grant the `deposit_operator` role to ConvertibleDepositFacility\n",
                "4. Grant the `cd_auctioneer` role to ConvertibleDepositAuctioneer\n",
                "5. Grant the `cd_emissionmanager` role to EmissionManager\n",
                "6. Grant the `heart` role to Heart contract\n\n",
                "### Phase 3: Execute Activator Contract\n",
                "7. Grant temporary `admin` role to ConvertibleDepositActivator contract\n"
            );
    }

    /// @dev Returns the first part of Phase 3 steps
    function _getProposalStepsPhase3Part1() private pure returns (string memory) {
        return
            string.concat(
                "8. Execute ConvertibleDepositActivator.activate() which performs:\n",
                "   - Enable DepositManager contract\n",
                "   - Set operator name on DepositManager for ConvertibleDepositFacility\n",
                "   - Enable ConvertibleDepositFacility contract\n",
                "   - Authorize ConvertibleDepositFacility in DepositRedemptionVault\n",
                "   - Authorize DepositRedemptionVault in ConvertibleDepositFacility\n",
                "   - Enable DepositRedemptionVault contract\n",
                "   - Configure USDS in DepositManager (1M USDS capacity, 1 USDS minimum)\n",
                "   - Add USDS deposit periods: 1m, 2m, 3m (90% reclaim rate each)\n"
            );
    }

    /// @dev Returns the second part of Phase 3 steps
    function _getProposalStepsPhase3Part2() private pure returns (string memory) {
        return
            string.concat(
                "   - Enable deposit periods in ConvertibleDepositAuctioneer\n",
                "   - Enable ConvertibleDepositAuctioneer with initial parameters (disabled auction)\n",
                "   - Enable EmissionManager with production parameters\n",
                "   - Enable ReserveWrapper contract\n",
                "   - Add ReserveMigrator.migrate() as first periodic task\n",
                "   - Add ReserveWrapper as second periodic task\n",
                "   - Add Operator.operate() as third periodic task\n",
                "   - Add YieldRepurchaseFacility.endEpoch() as fourth periodic task\n",
                "   - Add EmissionManager as fifth periodic task\n",
                "   - Enable Heart contract\n"
            );
    }

    /// @dev Returns the conclusion section of the proposal description
    function _getConclusionSection() private pure returns (string memory) {
        return
            string.concat(
                "9. Revoke `admin` role from ConvertibleDepositActivator contract\n\n",
                "## Result\n\n",
                "After execution, the Convertible Deposit system will be fully operational with USDS assets configured for 1, 2, and 3 month deposit periods.\n"
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
        // - Previous Heart and EmissionManager have been deactivated from the kernel
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
        }

        // ========== PHASE 2: GRANT ROLES TO NEW POLICIES ========== //

        // 2. Grant "manager" role to DAO MS
        {
            address daoMS = addresses.getAddress("olympus-multisig-dao");
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("manager"), daoMS),
                "Grant manager role to DAO MS"
            );
        }

        // 3. Grant "deposit_operator" role to ConvertibleDepositFacility
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

        // 4. Grant "cd_auctioneer" role to ConvertibleDepositAuctioneer
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

        // 5. Grant "cd_emissionmanager" role to EmissionManager
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

        // 6. Grant "heart" role to Heart contract
        {
            address heart = addresses.getAddress("olympus-policy-heart-1_7");

            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart),
                "Grant heart role to Heart contract"
            );
        }

        // ========== PHASE 3: EXECUTE ACTIVATOR CONTRACT ========== //

        address activator = addresses.getAddress("olympus-periphery-convertible-deposit-activator");

        // 7. Grant "admin" role (temporarily) to Activator contract
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("admin"), activator),
            "Grant admin role to temporary activator contract"
        );

        // 8. Run activator
        _pushAction(
            activator,
            abi.encodeWithSelector(ConvertibleDepositActivator.activate.selector),
            "Call temporary activator contract"
        );

        // 9. Revoke "admin" role from Activator contract
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("admin"), activator),
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

        // solhint-disable custom-errors

        // ========== PHASE 1 VALIDATIONS ========== //

        // 1. Validate that the "heart" role is revoked from the old Heart policy
        {
            address heartOld = addresses.getAddress("olympus-policy-heart-1_6");
            require(
                roles.hasRole(heartOld, bytes32("heart")) == false,
                "Old Heart policy still has the heart role"
            );
        }

        // ========== PHASE 2 VALIDATIONS ========== //

        // 2. Validate that DAO MS has "manager" role
        {
            address daoMS = addresses.getAddress("olympus-multisig-dao");
            require(
                roles.hasRole(daoMS, bytes32("manager")) == true,
                "DAO MS does not have the manager role"
            );
        }

        // 3. Validate that ConvertibleDepositFacility has "deposit_operator" role
        {
            address cdFacility = addresses.getAddress(
                "olympus-policy-convertible-deposit-facility-1_0"
            );
            require(
                roles.hasRole(cdFacility, bytes32("deposit_operator")) == true,
                "ConvertibleDepositFacility does not have the deposit_operator role"
            );
        }

        // 4. Validate that ConvertibleDepositAuctioneer has "cd_auctioneer" role
        {
            address cdAuctioneer = addresses.getAddress(
                "olympus-policy-convertible-deposit-auctioneer-1_0"
            );
            require(
                roles.hasRole(cdAuctioneer, bytes32("cd_auctioneer")) == true,
                "ConvertibleDepositAuctioneer does not have the cd_auctioneer role"
            );
        }

        // 5. Validate that EmissionManager has "cd_emissionmanager" role
        {
            address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");
            require(
                roles.hasRole(emissionManager, bytes32("cd_emissionmanager")) == true,
                "EmissionManager does not have the cd_emissionmanager role"
            );
        }

        // 6. Validate that Heart has the "heart" role
        {
            address heart = addresses.getAddress("olympus-policy-heart-1_7");
            require(
                roles.hasRole(heart, bytes32("heart")) == true,
                "Heart does not have the heart role"
            );
        }

        // ========== ACTIVATOR VALIDATIONS ========== //
        // Validate all the work done by the ConvertibleDepositActivator

        // Contract enablement validations
        {
            address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
            address cdFacility = addresses.getAddress(
                "olympus-policy-convertible-deposit-facility-1_0"
            );
            address depositRedemptionVault = addresses.getAddress(
                "olympus-policy-deposit-redemption-vault-1_0"
            );

            require(IEnabler(depositManager).isEnabled() == true, "DepositManager is not enabled");

            require(
                keccak256(bytes(IDepositManager(depositManager).getOperatorName(cdFacility))) ==
                    keccak256(bytes(CDF_NAME)),
                "DepositManager operator name for ConvertibleDepositFacility is incorrect"
            );

            require(
                IEnabler(cdFacility).isEnabled() == true,
                "ConvertibleDepositFacility is not enabled"
            );

            require(
                IDepositRedemptionVault(depositRedemptionVault).isAuthorizedFacility(cdFacility) ==
                    true,
                "ConvertibleDepositFacility is not an authorized facility with DepositRedemptionVault"
            );

            require(
                IDepositFacility(cdFacility).isAuthorizedOperator(depositRedemptionVault) == true,
                "DepositRedemptionVault is not an authorized operator with ConvertibleDepositFacility"
            );

            require(
                IEnabler(depositRedemptionVault).isEnabled() == true,
                "DepositRedemptionVault is not enabled"
            );
        }

        // Asset configuration validations
        {
            address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
            address usds = addresses.getAddress("external-tokens-USDS");
            address sUsds = addresses.getAddress("external-tokens-sUSDS");

            IAssetManager.AssetConfiguration memory assetConfig = IAssetManager(depositManager)
                .getAssetConfiguration(IERC20(usds));
            require(
                assetConfig.vault == sUsds,
                "USDS is not configured correctly in DepositManager"
            );
            require(
                assetConfig.depositCap == USDS_MAX_CAPACITY,
                "USDS capacity is not set correctly"
            );
            require(
                assetConfig.minimumDeposit == USDS_MIN_DEPOSIT,
                "USDS minimum deposit is not set correctly"
            );
        }

        // Validate USDS deposit periods
        {
            address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
            address usds = addresses.getAddress("external-tokens-USDS");
            address cdFacility = addresses.getAddress(
                "olympus-policy-convertible-deposit-facility-1_0"
            );

            IDepositManager.AssetPeriod memory assetPeriod1M = IDepositManager(depositManager)
                .getAssetPeriod(IERC20(usds), PERIOD_1M, cdFacility);
            require(
                assetPeriod1M.operator == cdFacility,
                "USDS-1m period facility is not set correctly"
            );
            require(
                assetPeriod1M.reclaimRate == RECLAIM_RATE,
                "USDS-1m period reclaim rate is not set correctly"
            );

            IDepositManager.AssetPeriod memory assetPeriod2M = IDepositManager(depositManager)
                .getAssetPeriod(IERC20(usds), PERIOD_2M, cdFacility);
            require(
                assetPeriod2M.operator == cdFacility,
                "USDS-2m period facility is not set correctly"
            );
            require(
                assetPeriod2M.reclaimRate == RECLAIM_RATE,
                "USDS-2m period reclaim rate is not set correctly"
            );

            IDepositManager.AssetPeriod memory assetPeriod3M = IDepositManager(depositManager)
                .getAssetPeriod(IERC20(usds), PERIOD_3M, cdFacility);
            require(
                assetPeriod3M.operator == cdFacility,
                "USDS-3m period facility is not set correctly"
            );
            require(
                assetPeriod3M.reclaimRate == RECLAIM_RATE,
                "USDS-3m period reclaim rate is not set correctly"
            );
        }

        // Validate auction system
        {
            address cdAuctioneer = addresses.getAddress(
                "olympus-policy-convertible-deposit-auctioneer-1_0"
            );
            address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");

            (bool period1MEnabled, ) = IConvertibleDepositAuctioneer(cdAuctioneer)
                .isDepositPeriodEnabled(PERIOD_1M);
            require(
                period1MEnabled == true,
                "USDS-1m period is not enabled in ConvertibleDepositAuctioneer"
            );

            (bool period2MEnabled, ) = IConvertibleDepositAuctioneer(cdAuctioneer)
                .isDepositPeriodEnabled(PERIOD_2M);
            require(
                period2MEnabled == true,
                "USDS-2m period is not enabled in ConvertibleDepositAuctioneer"
            );

            (bool period3MEnabled, ) = IConvertibleDepositAuctioneer(cdAuctioneer)
                .isDepositPeriodEnabled(PERIOD_3M);
            require(
                period3MEnabled == true,
                "USDS-3m period is not enabled in ConvertibleDepositAuctioneer"
            );

            require(
                IEnabler(cdAuctioneer).isEnabled() == true,
                "ConvertibleDepositAuctioneer is not enabled"
            );
            require(
                IEnabler(emissionManager).isEnabled() == true,
                "EmissionManager is not enabled"
            );
        }

        // Validate periodic tasks
        {
            address heart = addresses.getAddress("olympus-policy-heart-1_7");
            address reserveWrapper = addresses.getAddress("olympus-policy-reserve-wrapper-1_0");
            address reserveMigrator = addresses.getAddress("olympus-policy-reserve-migrator-1_0");
            address operator = addresses.getAddress("olympus-policy-operator-1_5");
            address yieldRepo = addresses.getAddress("olympus-policy-yieldrepurchasefacility-1_2");
            address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");

            require(IEnabler(reserveWrapper).isEnabled() == true, "ReserveWrapper is not enabled");

            require(
                IPeriodicTaskManager(heart).getPeriodicTaskCount() == 5,
                "Heart does not have the expected number of periodic tasks"
            );

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
            require(
                periodicTasks[4] == emissionManager,
                "EmissionManager is not the fifth periodic task"
            );

            require(IEnabler(heart).isEnabled() == true, "Heart is not enabled");
        }

        // Validate that all policies are active
        {
            address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
            address cdFacility = addresses.getAddress(
                "olympus-policy-convertible-deposit-facility-1_0"
            );
            address cdAuctioneer = addresses.getAddress(
                "olympus-policy-convertible-deposit-auctioneer-1_0"
            );
            address depositRedemptionVault = addresses.getAddress(
                "olympus-policy-deposit-redemption-vault-1_0"
            );
            address reserveWrapper = addresses.getAddress("olympus-policy-reserve-wrapper-1_0");
            address heart = addresses.getAddress("olympus-policy-heart-1_7");
            address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");

            require(
                Policy(depositManager).isActive() == true,
                "DepositManager policy is not active"
            );
            require(
                Policy(cdFacility).isActive() == true,
                "ConvertibleDepositFacility policy is not active"
            );
            require(
                Policy(cdAuctioneer).isActive() == true,
                "ConvertibleDepositAuctioneer policy is not active"
            );
            require(
                Policy(depositRedemptionVault).isActive() == true,
                "DepositRedemptionVault policy is not active"
            );
            require(
                Policy(reserveWrapper).isActive() == true,
                "ReserveWrapper policy is not active"
            );
            require(Policy(heart).isActive() == true, "Heart policy is not active");
            require(
                Policy(emissionManager).isActive() == true,
                "EmissionManager policy is not active"
            );
        }

        // ========== ACTIVATOR CLEANUP ========== //
        {
            address activator = addresses.getAddress(
                "olympus-periphery-convertible-deposit-activator"
            );

            // Validate that the activator is marked as activated (and hence disabled)
            require(
                ConvertibleDepositActivator(activator).isActivated() == true,
                "Activator is not marked as activated"
            );

            // Validate that the activator does not have the "admin" role
            require(
                roles.hasRole(activator, bytes32("admin")) == false,
                "Activator should not have the admin role"
            );
        }
    }
}

// solhint-disable-next-line contract-name-camelcase
contract ConvertibleDepositProposalScript is ProposalScript {
    constructor() ProposalScript(new ConvertibleDepositProposal()) {}
}
