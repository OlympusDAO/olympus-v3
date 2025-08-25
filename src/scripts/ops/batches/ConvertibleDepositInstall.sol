// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Kernel
import {Kernel, Actions} from "src/Kernel.sol";

// Interfaces
import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Installs and activates the complete ConvertibleDeposit system including EmissionManager
/// @dev    This script handles the complete activation sequence based on ConvertibleDepositAuctioneerTest setup
contract ConvertibleDepositInstall is BatchScriptV2 {
    /// @notice Install modules and activate policies
    function install(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address kernel = _envAddressNotZero("olympus.Kernel");
        address depositPositionManager = _envAddressNotZero(
            "olympus.modules.OlympusDepositPositionManager"
        );
        address receiptTokenManager = _envAddressNotZero("olympus.policies.ReceiptTokenManager");
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );
        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );
        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");

        console2.log("=== Installing ConvertibleDeposit System ===");
        console2.log("Installing modules and activating policies");

        // Install DEPOS module
        console2.log("1. Installing OlympusDepositPositionManager module");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.InstallModule,
                depositPositionManager
            )
        );

        // Activate policies
        console2.log("2. Activating ReceiptTokenManager policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                receiptTokenManager
            )
        );

        console2.log("3. Activating DepositManager policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                depositManager
            )
        );

        console2.log("4. Activating ConvertibleDepositFacility policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                convertibleDepositFacility
            )
        );

        console2.log("5. Activating ConvertibleDepositAuctioneer policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                convertibleDepositAuctioneer
            )
        );

        console2.log("6. Activating EmissionManager policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                emissionManager
            )
        );

        // Note: Heart policy should be activated by HeartPeriodicTasksConfig script
        console2.log("7. Heart policy assumed to be activated by HeartPeriodicTasksConfig");
        console2.log("=== Installation batch prepared ===");

        proposeBatch();
    }

    /// @notice Configure DepositManager and enable it
    function configureDepositManager(bool useDaoMS_) external setUpWithChainId(useDaoMS_) {
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");

        console2.log("=== Configuring DepositManager ===");
        console2.log("Enabling DepositManager policy to accept deposits");

        // Enable the DepositManager
        addToBatch(depositManager, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        console2.log("DepositManager configuration batch prepared");
        proposeBatch();
    }

    /// @notice Configure ConvertibleDepositFacility and enable it
    function configureConvertibleDepositFacility(
        string memory facilityName_,
        bool useDaoMS_
    ) external setUpWithChainId(useDaoMS_) {
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );

        console2.log("=== Configuring ConvertibleDepositFacility ===");
        console2.log("Setting facility name:", facilityName_);

        // Set facility name
        addToBatch(
            depositManager,
            abi.encodeWithSignature(
                "setOperatorName(address,string)",
                convertibleDepositFacility,
                facilityName_
            )
        );

        console2.log("Enabling ConvertibleDepositFacility for user deposits");
        // Enable the facility
        addToBatch(
            convertibleDepositFacility,
            abi.encodeWithSelector(IEnabler.enable.selector, "")
        );

        console2.log("ConvertibleDepositFacility configuration batch prepared");
        proposeBatch();
    }

    /// @notice Add a new asset and its vault to the DepositManager
    function configureUSDS(
        uint256 maxCapacity_,
        uint256 minDeposit_,
        bool useDaoMS_
    ) external setUpWithChainId(useDaoMS_) {
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address usds = _envAddressNotZero("external.tokens.USDS");
        address usdsVault = _envAddressNotZero("external.tokens.sUSDS");

        console2.log("=== Configuring USDS Asset ===");
        console2.log("Adding USDS as supported deposit asset");
        console2.log("USDS token:", usds);
        console2.log("sUSDS vault:", usdsVault);
        console2.log("Max capacity:", maxCapacity_);
        console2.log("Min deposit:", minDeposit_);

        // Add asset to DepositManager
        addToBatch(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAsset.selector,
                usds,
                usdsVault,
                maxCapacity_,
                minDeposit_
            )
        );

        console2.log("USDS asset configuration batch prepared");
        proposeBatch();
    }

    /// @notice Add asset period for ConvertibleDepositFacility
    function configureUSDSDepositPeriod(
        uint8 periodMonths_,
        uint16 reclaimRate_,
        bool useDaoMS_
    ) external setUpWithChainId(useDaoMS_) {
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );
        address usds = _envAddressNotZero("external.tokens.USDS");

        console2.log("=== Configuring USDS Deposit Period ===");
        console2.log("Setting up deposit period for USDS conversions");
        console2.log("Asset:", usds);
        console2.log("Period (months):", periodMonths_);
        console2.log("Reclaim rate (bps):", reclaimRate_);
        console2.log("Facility:", convertibleDepositFacility);

        // Add asset period
        addToBatch(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAssetPeriod.selector,
                usds,
                periodMonths_,
                convertibleDepositFacility,
                reclaimRate_
            )
        );

        console2.log("USDS deposit period configuration batch prepared");
        proposeBatch();
    }

    /// @notice Configure ConvertibleDepositAuctioneer
    function configureConvertibleDepositAuctioneer(
        bool useDaoMS_
    ) external setUpWithChainId(useDaoMS_) {
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );

        console2.log("=== Configuring ConvertibleDepositAuctioneer ===");
        console2.log("Granting roles and enabling auction functionality");

        // Grant required roles
        console2.log("Granting cd_auctioneer role to:", convertibleDepositAuctioneer);
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("cd_auctioneer"),
                convertibleDepositAuctioneer
            )
        );

        console2.log("Granting deposit_operator role to:", convertibleDepositFacility);
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("deposit_operator"),
                convertibleDepositFacility
            )
        );

        console2.log("Enabling ConvertibleDepositAuctioneer with initial parameters");
        console2.log("- Target: 1000 OHM");
        console2.log("- Tick size: 200 OHM");
        console2.log("- Min price: 22 USDS/OHM");
        console2.log("- Tick step: 110% (10% increase)");
        console2.log("- Tracking period: 7 days");
        // Enable the ConvertibleDepositAuctioneer
        // The parameters will be tweaked when the EmissionManager runs
        addToBatch(
            convertibleDepositAuctioneer,
            abi.encodeWithSelector(
                IEnabler.enable.selector,
                abi.encode(
                    IConvertibleDepositAuctioneer.EnableParams({
                        target: 1000e9, // 100 OHM
                        tickSize: 200e9, // 200 OHM per tick
                        minPrice: 22e18, // 22 USDS / OHM
                        tickStep: 110e2, // 10% increase
                        auctionTrackingPeriod: 7 // 7 days
                    })
                )
            )
        );

        console2.log("ConvertibleDepositAuctioneer configuration batch prepared");
        proposeBatch();
    }

    /// @notice Configure and initialize EmissionManager
    function configureEmissionManager(
        bool useDaoMS_
    ) external setUpWithChainId(useDaoMS_) {
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");

        console2.log("=== Configuring EmissionManager ===");
        console2.log("Setting up emissions system for supply growth");

        // Grant roles
        console2.log("Granting cd_emissionmanager role to:", emissionManager);
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("cd_emissionmanager"),
                emissionManager
            )
        );

        console2.log("Granting heart role to:", heart);
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart)
        );

        console2.log("Enabling EmissionManager with parameters:");
        console2.log("- Base emissions rate: 0.02%/day");
        console2.log("- Minimum premium: 100%");
        console2.log("- Backing: 11.67 USDS/OHM");
        console2.log("- Tick size scalar: 20%");
        console2.log("- Min price scalar: 100%");
        console2.log("- Restart timeframe: 11 days");
        // Enable EmissionManager
        addToBatch(
            emissionManager,
            abi.encodeWithSelector(
                IEnabler.enable.selector,
                abi.encode(
                    IEmissionManager.EnableParams({
                        baseEmissionsRate: 200000, // 200000 = 0.02%/day
                        minimumPremium: 1e18, // 100% premium
                        backing: 11670000000000000000, // 11.67 USDS / OHM
                        tickSizeScalar: 20e16, // 20% of target per tick
                        minPriceScalar: 1e18, // Minimum price is market price
                        restartTimeframe: 950400 // 11 days
                    })
                )
            )
        );

        console2.log("Adding EmissionManager to Heart periodic tasks");
        // Add EmissionManager to Heart periodic tasks
        addToBatch(
            heart,
            abi.encodeWithSelector(IPeriodicTaskManager.addPeriodicTask.selector, emissionManager)
        );

        console2.log("EmissionManager configuration batch prepared");
        console2.log("=== All ConvertibleDeposit components configured ===");
        proposeBatch();
    }
}
