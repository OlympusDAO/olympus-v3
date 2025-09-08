// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity ^0.8.15;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Contracts
import {Kernel, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

/// @notice Configures assets for the Convertible Deposit system
contract ConvertibleDepositAssets is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

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
        return 13;
    }

    function name() public pure override returns (string memory) {
        return "Convertible Deposits - Asset Configuration";
    }

    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# Convertible Deposits - Asset Configuration\n",
                "\n",
                "This is the second out of two proposals related to the Convertible Deposit system. This proposal configures assets and activates the auction system.\n",
                "\n",
                "## Summary\n",
                "\n",
                "The Convertible Deposit system provides a mechanism for the protocol to operate an auction that is infinite duration and infinite capacity. This proposal configures USDS assets with different deposit periods (1m, 2m, 3m), grants necessary roles, and enables the EmissionManager and ConvertibleDepositAuctioneer.\n",
                "\n",
                "## Affected Contracts\n",
                "\n",
                "- DepositManager policy (existing - 1.0)\n",
                "- ConvertibleDepositAuctioneer policy (existing - 1.0)\n",
                "- EmissionManager policy (existing - 1.2)\n",
                "- Heart policy (existing - 1.7)\n",
                "\n",
                "## Resources\n",
                "\n",
                "- [View the audit report](TODO)\n", // TODO: Add audit report
                "- [View the pull request](https://github.com/OlympusDAO/olympus-v3/pull/29)\n",
                "\n",
                "## Pre-requisites\n",
                "\n",
                "- First Convertible Deposit proposal (proposal 12) has been executed\n",
                "- All required policies have been activated in the kernel\n",
                "- DEPOS module has been installed in the kernel\n",
                "- Heart is enabled and running periodic tasks\n",
                "\n",
                "## Proposal Steps\n",
                "\n",
                "1. Grant the `manager` role to the DAO MS\n",
                "2. Configure USDS in DepositManager\n",
                "3. Add USDS-1m to DepositManager\n",
                "4. Enable USDS-1m in ConvertibleDepositAuctioneer\n",
                "5. Add USDS-2m to DepositManager\n",
                "6. Enable USDS-2m in ConvertibleDepositAuctioneer\n",
                "7. Add USDS-3m to DepositManager\n",
                "8. Enable USDS-3m in ConvertibleDepositAuctioneer\n",
                "9. Grant the `cd_auctioneer` role to ConvertibleDepositAuctioneer\n",
                "10. Enable ConvertibleDepositAuctioneer (with disabled auction)\n",
                "11. Grant the `cd_emissionmanager` role to EmissionManager\n",
                "12. Add EmissionManager to periodic tasks\n",
                "13. Enable EmissionManager\n",
                "\n",
                "## Result\n",
                "\n",
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
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        // Get contract addresses
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
        address cdAuctioneer = addresses.getAddress(
            "olympus-policy-convertible-deposit-auctioneer-1_0"
        );
        address cdFacility = addresses.getAddress(
            "olympus-policy-convertible-deposit-facility-1_0"
        );
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");

        // Get asset addresses
        address usds = addresses.getAddress("external-tokens-USDS");
        address sUsds = addresses.getAddress("external-tokens-sUSDS");

        // Pre-requisites:
        // - First Convertible Deposit proposal (proposal 12) has been executed
        // - All required policies have been activated in the kernel
        // - DEPOS module has been installed in the kernel
        // - Heart is enabled and running periodic tasks

        // Validate that DepositManager is enabled (indicates proposal 12 was executed)
        if (!IEnabler(depositManager).isEnabled()) {
            revert("DepositManager not enabled - proposal 12 may not have been executed");
        }

        // 1. Grant "manager" role to DAO MS
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("manager"), daoMS),
            "Grant manager role to DAO MS"
        );

        // 2. Configure USDS in DepositManager
        _pushAction(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAsset.selector,
                usds,
                sUsds,
                USDS_MAX_CAPACITY,
                USDS_MIN_DEPOSIT
            ),
            "Configure USDS in DepositManager"
        );

        // 3. Add USDS-1m to DepositManager
        _pushAction(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAssetPeriod.selector,
                usds,
                PERIOD_1M,
                cdFacility,
                RECLAIM_RATE
            ),
            "Add USDS-1m to DepositManager"
        );

        // 4. Enable USDS-1m in ConvertibleDepositAuctioneer
        _pushAction(
            cdAuctioneer,
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.enableDepositPeriod.selector,
                PERIOD_1M
            ),
            "Enable USDS-1m in ConvertibleDepositAuctioneer"
        );

        // 5. Add USDS-2m to DepositManager
        _pushAction(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAssetPeriod.selector,
                usds,
                PERIOD_2M,
                cdFacility,
                RECLAIM_RATE
            ),
            "Add USDS-2m to DepositManager"
        );

        // 6. Enable USDS-2m in ConvertibleDepositAuctioneer
        _pushAction(
            cdAuctioneer,
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.enableDepositPeriod.selector,
                PERIOD_2M
            ),
            "Enable USDS-2m in ConvertibleDepositAuctioneer"
        );

        // 7. Add USDS-3m to DepositManager
        _pushAction(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAssetPeriod.selector,
                usds,
                PERIOD_3M,
                cdFacility,
                RECLAIM_RATE
            ),
            "Add USDS-3m to DepositManager"
        );

        // 8. Enable USDS-3m in ConvertibleDepositAuctioneer
        _pushAction(
            cdAuctioneer,
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.enableDepositPeriod.selector,
                PERIOD_3M
            ),
            "Enable USDS-3m in ConvertibleDepositAuctioneer"
        );

        // 9. Grant "cd_auctioneer" role to ConvertibleDepositAuctioneer
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("cd_auctioneer"),
                cdAuctioneer
            ),
            "Grant cd_auctioneer role to ConvertibleDepositAuctioneer"
        );

        // 10. Enable ConvertibleDepositAuctioneer (with disabled auction)
        _pushAction(
            cdAuctioneer,
            abi.encodeWithSelector(
                IEnabler.enable.selector,
                abi.encode(
                    IConvertibleDepositAuctioneer.EnableParams({
                        target: CDA_INITIAL_TARGET,
                        tickSize: CDA_INITIAL_TICK_SIZE,
                        minPrice: CDA_INITIAL_MIN_PRICE,
                        tickStep: CDA_INITIAL_TICK_STEP_MULTIPLIER,
                        auctionTrackingPeriod: CDA_AUCTION_TRACKING_PERIOD
                    })
                )
            ),
            "Enable ConvertibleDepositAuctioneer (with disabled auction)"
        );

        // 11. Grant "cd_emissionmanager" role to EmissionManager
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("cd_emissionmanager"),
                emissionManager
            ),
            "Grant cd_emissionmanager role to EmissionManager"
        );

        // 12. Add EmissionManager to periodic tasks
        _pushAction(
            heart,
            abi.encodeWithSelector(IPeriodicTaskManager.addPeriodicTask.selector, emissionManager),
            "Add EmissionManager to periodic tasks"
        );

        // 13. Enable EmissionManager
        _pushAction(
            emissionManager,
            abi.encodeWithSelector(
                IEnabler.enable.selector,
                abi.encode(
                    IEmissionManager.EnableParams({
                        baseEmissionsRate: EM_BASE_EMISSIONS_RATE,
                        minimumPremium: EM_MINIMUM_PREMIUM,
                        backing: EM_BACKING,
                        tickSize: EM_TICK_SIZE,
                        minPriceScalar: EM_MIN_PRICE_SCALAR,
                        restartTimeframe: EM_RESTART_TIMEFRAME
                    })
                )
            ),
            "Enable EmissionManager"
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
        address daoMS = addresses.getAddress("olympus-multisig-dao");

        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        address depositManager = addresses.getAddress("olympus-policy-deposit-manager-1_0");
        address cdAuctioneer = addresses.getAddress(
            "olympus-policy-convertible-deposit-auctioneer-1_0"
        );
        address cdFacility = addresses.getAddress(
            "olympus-policy-convertible-deposit-facility-1_0"
        );
        address emissionManager = addresses.getAddress("olympus-policy-emissionmanager-1_2");

        address usds = addresses.getAddress("external-tokens-USDS");
        address sUsds = addresses.getAddress("external-tokens-sUSDS");

        // solhint-disable custom-errors

        // Validate that DepositManager is enabled (indicates proposal 12 was executed)
        require(
            IEnabler(depositManager).isEnabled() == true,
            "DepositManager is not enabled - proposal 12 may not have been executed"
        );

        // 1. Validate that the DAO MS has the "manager" role
        require(
            roles.hasRole(daoMS, bytes32("manager")) == true,
            "DAO MS does not have the manager role"
        );

        // 2. Validate USDS is configured in DepositManager
        IAssetManager.AssetConfiguration memory assetConfig = IDepositManager(depositManager)
            .getAssetConfiguration(IERC20(usds));
        require(assetConfig.vault == sUsds, "USDS is not configured correctly in DepositManager");

        require(assetConfig.depositCap == USDS_MAX_CAPACITY, "USDS capacity is not set correctly");

        require(
            assetConfig.minimumDeposit == USDS_MIN_DEPOSIT,
            "USDS minimum deposit is not set correctly"
        );

        // 3-8. Validate asset periods are added and enabled
        // Validate USDS-1m period
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

        (bool period1MEnabled, ) = IConvertibleDepositAuctioneer(cdAuctioneer)
            .isDepositPeriodEnabled(PERIOD_1M);
        require(
            period1MEnabled == true,
            "USDS-1m period is not enabled in ConvertibleDepositAuctioneer"
        );

        // Validate USDS-2m period
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

        (bool period2MEnabled, ) = IConvertibleDepositAuctioneer(cdAuctioneer)
            .isDepositPeriodEnabled(PERIOD_2M);
        require(
            period2MEnabled == true,
            "USDS-2m period is not enabled in ConvertibleDepositAuctioneer"
        );

        // Validate USDS-3m period
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

        (bool period3MEnabled, ) = IConvertibleDepositAuctioneer(cdAuctioneer)
            .isDepositPeriodEnabled(PERIOD_3M);
        require(
            period3MEnabled == true,
            "USDS-3m period is not enabled in ConvertibleDepositAuctioneer"
        );

        // 9. Validate that the CDAuctioneer has the "cd_auctioneer" role
        require(
            roles.hasRole(cdAuctioneer, bytes32("cd_auctioneer")) == true,
            "CDAuctioneer policy does not have the cd_auctioneer role"
        );

        // 10. Validate that the ConvertibleDepositAuctioneer is enabled
        require(IEnabler(cdAuctioneer).isEnabled() == true, "CDAuctioneer policy is not enabled");

        // 11. Validate that the EmissionManager has the "cd_emissionmanager" role
        require(
            roles.hasRole(emissionManager, bytes32("cd_emissionmanager")) == true,
            "EmissionManager policy does not have the cd_emissionmanager role"
        );

        // 12. Validate EmissionManager is added to periodic tasks
        // Check that Heart has EmissionManager in its periodic tasks
        (address[] memory periodicTasks, ) = IPeriodicTaskManager(heart).getPeriodicTasks();
        bool emissionManagerFound = false;
        for (uint256 i = 0; i < periodicTasks.length; i++) {
            if (periodicTasks[i] == emissionManager) {
                emissionManagerFound = true;
                break;
            }
        }
        require(emissionManagerFound, "EmissionManager is not in Heart's periodic tasks");

        // 13. Validate that the EmissionManager is enabled
        require(
            IEnabler(emissionManager).isEnabled() == true,
            "EmissionManager policy is not enabled"
        );

        // Validate that all policies are active
        require(Policy(depositManager).isActive() == true, "DepositManager policy is not active");
        require(Policy(cdAuctioneer).isActive() == true, "CDAuctioneer policy is not active");
        require(Policy(cdFacility).isActive() == true, "CDFacility policy is not active");
        require(Policy(emissionManager).isActive() == true, "EmissionManager policy is not active");
        require(Policy(heart).isActive() == true, "Heart policy is not active");
    }
}

// solhint-disable-next-line contract-name-camelcase
contract ConvertibleDepositAssetsScript is ProposalScript {
    constructor() ProposalScript(new ConvertibleDepositAssets()) {}
}
