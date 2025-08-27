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
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {SafeCast} from "src/libraries/SafeCast.sol";

import {console2} from "@forge-std-1.9.6/console2.sol";

/// @notice Installs and activates the complete ConvertibleDeposit system including EmissionManager
/// @dev    This script handles the complete activation sequence based on ConvertibleDepositAuctioneerTest setup
contract ConvertibleDepositInstall is BatchScriptV2 {
    /// @notice Install modules and activate policies
    /// @dev    Currently, the DAO MS has kernel executor role, so this will be run as a batch script through the DAO MS
    function install(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address depositPositionManager = _envAddressNotZero(
            "olympus.modules.OlympusDepositPositionManager"
        );
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );
        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );
        address depositRedemptionVault = _envAddressNotZero(
            "olympus.policies.DepositRedemptionVault"
        );
        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");

        // Get old policy addresses (may be zero)
        address oldHeart = _envLastAddress(chain, "olympus.policies.OlympusHeart");
        address oldEmissionManager = _envLastAddress(chain, "olympus.policies.EmissionManager");

        console2.log("=== Installing ConvertibleDeposit System ===");
        console2.log("Installing modules and activating policies");

        // Deactivate old policies if they exist
        if (oldHeart != address(0)) {
            console2.log("0. Deactivating old OlympusHeart policy:", oldHeart);
            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.DeactivatePolicy,
                    oldHeart
                )
            );
        } else {
            console2.log("0. No old OlympusHeart policy to deactivate");
        }

        if (oldEmissionManager != address(0)) {
            console2.log("0. Deactivating old EmissionManager policy:", oldEmissionManager);
            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.DeactivatePolicy,
                    oldEmissionManager
                )
            );
        } else {
            console2.log("0. No old EmissionManager policy to deactivate");
        }

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
        console2.log("2. Activating DepositManager policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                depositManager
            )
        );

        console2.log("3. Activating ConvertibleDepositFacility policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                convertibleDepositFacility
            )
        );

        console2.log("4. Activating ConvertibleDepositAuctioneer policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                convertibleDepositAuctioneer
            )
        );

        console2.log("5. Activating DepositRedemptionVault policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                depositRedemptionVault
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

        console2.log("7. Activating Heart policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, heart)
        );

        console2.log("=== Installation batch prepared ===");
        console2.log(
            "Note: Heart periodic tasks should be configured by HeartPeriodicTasksConfig script"
        );

        proposeBatch();
    }

    /// @notice Configure DepositManager and enable it
    function configureDepositManager(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

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
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        string memory facilityName = _readBatchArgString(
            "ConfigureConvertibleDepositFacility",
            "facilityName"
        );
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );

        console2.log("=== Configuring ConvertibleDepositFacility ===");
        console2.log("Setting facility name:", facilityName);

        // Set facility name
        addToBatch(
            depositManager,
            abi.encodeWithSignature(
                "setOperatorName(address,string)",
                convertibleDepositFacility,
                facilityName
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
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address usds = _envAddressNotZero("external.tokens.USDS");
        address usdsVault = _envAddressNotZero("external.tokens.sUSDS");
        uint256 maxCapacity = _readBatchArgUint256("ConfigureUSDS", "maxCapacity");
        uint256 minDeposit = _readBatchArgUint256("ConfigureUSDS", "minDeposit");

        console2.log("=== Configuring USDS Asset ===");
        console2.log("Adding USDS as supported deposit asset");
        console2.log("USDS token:", usds);
        console2.log("sUSDS vault:", usdsVault);
        console2.log("Max capacity:", maxCapacity);
        console2.log("Min deposit:", minDeposit);

        // Add asset to DepositManager
        addToBatch(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAsset.selector,
                usds,
                usdsVault,
                maxCapacity,
                minDeposit
            )
        );

        console2.log("USDS asset configuration batch prepared");
        proposeBatch();
    }

    /// @notice Add asset period for ConvertibleDepositFacility
    function configureUSDSDepositPeriod(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        address depositManager = _envAddressNotZero("olympus.policies.DepositManager");
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );
        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );
        address usds = _envAddressNotZero("external.tokens.USDS");
        uint8 depositPeriod = SafeCast.encodeUInt8(
            _readBatchArgUint256("ConfigureUSDSDepositPeriod", "depositPeriod")
        );
        uint16 reclaimRate = SafeCast.encodeUInt16(
            _readBatchArgUint256("ConfigureUSDSDepositPeriod", "reclaimRate")
        );

        console2.log("=== Configuring USDS Deposit Period ===");
        console2.log("Setting up deposit period for USDS conversions");
        console2.log("Asset:", usds);
        console2.log("Deposit Period (months):", depositPeriod);
        console2.log("Reclaim rate (bps):", reclaimRate);
        console2.log("Facility:", convertibleDepositFacility);

        // Add asset period
        addToBatch(
            depositManager,
            abi.encodeWithSelector(
                IDepositManager.addAssetPeriod.selector,
                usds,
                depositPeriod,
                convertibleDepositFacility,
                reclaimRate
            )
        );

        // Enable deposit period in auctioneer
        console2.log("Enabling deposit period in auctioneer");
        addToBatch(
            convertibleDepositAuctioneer,
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.enableDepositPeriod.selector,
                depositPeriod
            )
        );

        console2.log("USDS deposit period configuration batch prepared");
        proposeBatch();
    }

    /// @notice Grant roles for ConvertibleDeposit system
    function grantConvertibleDepositRoles(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );

        console2.log("=== Granting ConvertibleDeposit Roles ===");

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

        console2.log("ConvertibleDeposit roles batch prepared");
        proposeBatch();
    }

    /// @notice Configure ConvertibleDepositAuctioneer
    function configureConvertibleDepositAuctioneer(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );

        console2.log("=== Configuring ConvertibleDepositAuctioneer ===");
        console2.log("Enabling auction functionality with initial parameters");
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
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

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

    /// @notice Disable ConvertibleDepositAuctioneer
    function disableConvertibleDepositAuctioneer(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );

        console2.log("=== Disabling ConvertibleDepositAuctioneer ===");
        console2.log("Disabling auctioneer to halt new auctions");

        // Disable the ConvertibleDepositAuctioneer
        addToBatch(
            convertibleDepositAuctioneer,
            abi.encodeWithSelector(IEnabler.disable.selector, "")
        );

        console2.log("ConvertibleDepositAuctioneer disable batch prepared");
        proposeBatch();
    }

    /// @notice Enable DepositRedemptionVault and configure cross-authorization
    function enableDepositRedemptionVault(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        _validateArgsFileEmpty(argsFile_);

        address depositRedemptionVault = _envAddressNotZero(
            "olympus.policies.DepositRedemptionVault"
        );
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );

        console2.log("=== Enabling DepositRedemptionVault ===");
        console2.log("Authorizing ConvertibleDepositFacility in DepositRedemptionVault");

        // Authorize ConvertibleDepositFacility in DepositRedemptionVault
        addToBatch(
            depositRedemptionVault,
            abi.encodeWithSelector(
                IDepositRedemptionVault.authorizeFacility.selector,
                convertibleDepositFacility
            )
        );

        console2.log(
            "Authorizing DepositRedemptionVault as operator in ConvertibleDepositFacility"
        );

        // Authorize DepositRedemptionVault as operator in ConvertibleDepositFacility
        addToBatch(
            convertibleDepositFacility,
            abi.encodeWithSelector(
                IDepositFacility.authorizeOperator.selector,
                depositRedemptionVault
            )
        );

        console2.log("Enabling DepositRedemptionVault");

        // Enable the DepositRedemptionVault
        addToBatch(depositRedemptionVault, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        console2.log("DepositRedemptionVault enablement batch prepared");
        proposeBatch();
    }

    /// @notice Configure asset settings in DepositRedemptionVault
    function configureDepositRedemptionVaultAsset(
        bool useDaoMS_,
        string calldata argsFile_
    ) external setUpWithChainIdAndArgsFile(useDaoMS_, argsFile_) {
        address depositRedemptionVault = _envAddressNotZero(
            "olympus.policies.DepositRedemptionVault"
        );
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );
        address usds = _envAddressNotZero("external.tokens.USDS");

        uint16 maxBorrowPercentage = SafeCast.encodeUInt16(
            _readBatchArgUint256("ConfigureDepositRedemptionVaultAsset", "maxBorrowPercentage")
        );
        uint16 annualInterestRate = SafeCast.encodeUInt16(
            _readBatchArgUint256("ConfigureDepositRedemptionVaultAsset", "annualInterestRate")
        );

        console2.log("=== Configuring DepositRedemptionVault Asset Settings ===");
        console2.log("Asset (USDS):", usds);
        console2.log("Facility:", convertibleDepositFacility);
        console2.log("Max Borrow Percentage (bps):", maxBorrowPercentage);
        console2.log("Annual Interest Rate (bps):", annualInterestRate);

        // Set max borrow percentage
        addToBatch(
            depositRedemptionVault,
            abi.encodeWithSelector(
                IDepositRedemptionVault.setMaxBorrowPercentage.selector,
                IERC20(usds),
                convertibleDepositFacility,
                maxBorrowPercentage
            )
        );

        // Set annual interest rate
        addToBatch(
            depositRedemptionVault,
            abi.encodeWithSelector(
                IDepositRedemptionVault.setAnnualInterestRate.selector,
                IERC20(usds),
                convertibleDepositFacility,
                annualInterestRate
            )
        );

        console2.log("DepositRedemptionVault asset configuration batch prepared");
        proposeBatch();
    }
}
