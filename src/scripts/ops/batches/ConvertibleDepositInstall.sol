// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Kernel
import {Kernel, Actions} from "src/Kernel.sol";

// Interfaces
import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ConvertibleDepositActivator} from "src/proposals/ConvertibleDepositActivator.sol";

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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
        address reserveWrapper = _envAddressNotZero("olympus.policies.ReserveWrapper");
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");

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

        console2.log("7. Activating ReserveWrapper policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                reserveWrapper
            )
        );

        console2.log("8. Activating Heart policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, heart)
        );

        console2.log("=== Installation batch prepared ===");
        console2.log(
            "Note: Heart periodic tasks should be configured by HeartPeriodicTasksConfig script"
        );

        proposeBatch();

        // Notes:
        // - The current Heart and EmissionManager policies are still activated in the kernel and enabled (operating)
        // - After the OCG proposal has been executed, the current Heart and EmissionManager policies will need to be deactivated using the `deactivateOldPolicies` function
    }

    /// @notice Replaces the initial EmissionManager policy with the new one
    function replaceEmissionManager(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");
        address prevEmissionManager = 0xb4f620c39F3BA4a1E7aD264fEd6239B0C618DB50;

        console2.log("=== Replacing EmissionManager ===");

        console2.log("Deactivating old EmissionManager policy:", prevEmissionManager);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                prevEmissionManager
            )
        );

        console2.log("Activating new EmissionManager policy:", emissionManager);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                emissionManager
            )
        );

        console2.log("EmissionManager replacement batch prepared");

        proposeBatch();
    }

    /// @notice Deactivate old policies
    /// @dev    Currently, the DAO MS has kernel executor role, so this will be run as a batch script through the DAO MS
    function deactivateOldPolicies(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address kernel = _envAddressNotZero("olympus.Kernel");

        // Get old policy addresses (may be zero)
        address oldHeart = _envLastAddress(chain, "olympus.policies.OlympusHeart");
        address oldEmissionManager = _envLastAddress(chain, "olympus.policies.EmissionManager");

        if (oldHeart == address(0)) {
            revert("No old OlympusHeart policy to deactivate");
        }
        if (oldEmissionManager == address(0)) {
            revert("No old EmissionManager policy to deactivate");
        }

        console2.log("=== Deactivating Old Policies ===");

        console2.log("Deactivating old OlympusHeart policy:", oldHeart);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldHeart
            )
        );

        console2.log("Deactivating old EmissionManager policy:", oldEmissionManager);
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldEmissionManager
            )
        );
        console2.log("Old policies deactivated");

        proposeBatch();
    }

    function grantHeartRole(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");

        console2.log("=== Granting Heart Role ===");

        // Grant heart role to OlympusHeart
        console2.log("Granting heart role to:", heart);
        addToBatch(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart)
        );

        console2.log("Heart role grant batch prepared");
        proposeBatch();
    }

    /// @notice Configure DepositManager and enable it
    function configureDepositManager(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("cd_auctioneer"),
                convertibleDepositAuctioneer
            )
        );

        console2.log("Granting deposit_operator role to:", convertibleDepositFacility);
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );

        console2.log("=== Configuring ConvertibleDepositAuctioneer ===");
        console2.log("Enabling auction functionality with initial parameters");
        console2.log("- Target: 1000 OHM");
        console2.log("- Tick size: 200 OHM");
        console2.log("- Min price: 22 USDS/OHM");
        console2.log("- Tick size base: 2.0");
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
                        target: 1000e9, // 1000 OHM
                        tickSize: 200e9, // 200 OHM per tick
                        minPrice: 22e18, // 22 USDS / OHM
                        tickSizeBase: 2e18, // 2.0
                        tickStep: 110e2, // 10% increase
                        auctionTrackingPeriod: 7 // 7 days
                    })
                )
            )
        );

        console2.log("ConvertibleDepositAuctioneer configuration batch prepared");
        proposeBatch();
    }

    function configureEmissionManagerRoles(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");

        // Grant roles
        console2.log("Granting cd_emissionmanager role to:", emissionManager);
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                bytes32("cd_emissionmanager"),
                emissionManager
            )
        );

        console2.log("Granting heart role to:", heart);
        addToBatch(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), heart)
        );

        console2.log("EmissionManager roles batch prepared");
        proposeBatch();
    }

    /// @notice Configure and initialize EmissionManager
    function configureEmissionManager(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");
        address heart = _envAddressNotZero("olympus.policies.OlympusHeart");

        console2.log("=== Configuring EmissionManager ===");
        console2.log("Setting up emissions system for supply growth");

        console2.log("Enabling EmissionManager with parameters:");
        console2.log("- Base emissions rate: 0.02%/day");
        console2.log("- Minimum premium: 100%");
        console2.log("- Backing: 11.67 USDS/OHM");
        console2.log("- Tick size scalar: 20%");
        console2.log("- Min price scalar: 100%");
        console2.log("- Bond market capacity scalar: 100%");
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
                        tickSize: 100e9, // 100 OHM
                        minPriceScalar: 1e18, // Minimum price is market price
                        bondMarketCapacityScalar: 1e18, // 100% bond market capacity scalar
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
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

    function enableReserveWrapper(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address reserveWrapper = _envAddressNotZero("olympus.policies.ReserveWrapper");

        console2.log("=== Enabling ReserveWrapper ===");
        console2.log("Enabling ReserveWrapper to start wrapping reserves");

        // Enable the ReserveWrapper
        addToBatch(reserveWrapper, abi.encodeWithSelector(IEnabler.enable.selector, ""));

        console2.log("ReserveWrapper enablement batch prepared");
        proposeBatch();
    }

    function runActivator(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        _validateArgsFileEmpty(argsFile_);

        address activator = _envAddressNotZero("olympus.periphery.ConvertibleDepositActivator");
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");

        console2.log("=== Activator ===");

        console2.log("Granting admin role to activator");
        addToBatch(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("admin"), activator)
        );

        console2.log("Running activator");
        addToBatch(
            activator,
            abi.encodeWithSelector(ConvertibleDepositActivator.activate.selector)
        );

        console2.log("Revoking admin role from activator");
        addToBatch(
            rolesAdmin,
            /// forge-lint: disable-next-line(unsafe-typecast)
            abi.encodeWithSelector(RolesAdmin.revokeRole.selector, bytes32("admin"), activator)
        );

        console2.log("Activator batch prepared");
        proposeBatch();
    }

    /// @notice Reconfigure ConvertibleDeposit parameters
    /// @dev    Only adds parameters to batch if they differ from current values
    ///         Reads desired values from args file
    function configureDepositParameters(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath, signature_) {
        address depositRedemptionVault = _envAddressNotZero(
            "olympus.policies.DepositRedemptionVault"
        );
        address convertibleDepositFacility = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositFacility"
        );
        address convertibleDepositAuctioneer = _envAddressNotZero(
            "olympus.policies.ConvertibleDepositAuctioneer"
        );
        address emissionManager = _envAddressNotZero("olympus.policies.EmissionManager");
        address usds = _envAddressNotZero("external.tokens.USDS");

        console2.log("=== Configuring ConvertibleDeposit Parameters ===");

        // Read desired values from args file
        uint256 annualInterestRateDesired = _readBatchArgUint256(
            "ConfigureDepositParameters",
            "annualInterestRate"
        );
        uint256 maxBorrowPercentageDesired = _readBatchArgUint256(
            "ConfigureDepositParameters",
            "maxBorrowPercentage"
        );
        uint256 minPriceScalarDesired = _readBatchArgUint256(
            "ConfigureDepositParameters",
            "minPriceScalar"
        );
        uint256 baseEmissionsRateDesired = _readBatchArgUint256(
            "ConfigureDepositParameters",
            "baseEmissionsRate"
        );
        uint256[] memory enabledPeriods = _readBatchArgUint256Array(
            "ConfigureDepositParameters",
            "enabledPeriods"
        );
        uint256[] memory reclaimRatePeriods = _readBatchArgUint256Array(
            "ConfigureDepositParameters",
            "reclaimRatePeriods"
        );
        uint256[] memory reclaimRates = _readBatchArgUint256Array(
            "ConfigureDepositParameters",
            "reclaimRates"
        );

        // Configure each category
        _configureEmissionsParameters(
            emissionManager,
            minPriceScalarDesired,
            baseEmissionsRateDesired
        );
        _configureBorrowingParameters(
            depositRedemptionVault,
            convertibleDepositFacility,
            usds,
            annualInterestRateDesired,
            maxBorrowPercentageDesired
        );
        _configureDepositPeriods(
            convertibleDepositAuctioneer,
            convertibleDepositFacility,
            usds,
            enabledPeriods
        );
        _configureReclaimRates(convertibleDepositFacility, usds, reclaimRatePeriods, reclaimRates);

        console2.log("ConvertibleDeposit parameters reconfiguration batch prepared");
        proposeBatch();
    }

    /// @notice Configure borrowing parameters
    function _configureBorrowingParameters(
        address depositRedemptionVault,
        address convertibleDepositFacility,
        address usds,
        uint256 annualInterestRateDesired,
        uint256 maxBorrowPercentageDesired
    ) internal {
        uint16 currentAnnualInterestRate = IDepositRedemptionVault(depositRedemptionVault)
            .getAnnualInterestRate(IERC20(usds), convertibleDepositFacility);
        uint16 currentMaxBorrowPercentage = IDepositRedemptionVault(depositRedemptionVault)
            .getMaxBorrowPercentage(IERC20(usds), convertibleDepositFacility);
        uint16 annualInterestRate = SafeCast.encodeUInt16(annualInterestRateDesired);
        uint16 maxBorrowPercentage = SafeCast.encodeUInt16(maxBorrowPercentageDesired);

        if (currentAnnualInterestRate != annualInterestRate) {
            console2.log("Annual Interest Rate changed:");
            console2.log("orig: ", currentAnnualInterestRate);
            console2.log("new:  ", annualInterestRate);
            addToBatch(
                depositRedemptionVault,
                abi.encodeWithSelector(
                    IDepositRedemptionVault.setAnnualInterestRate.selector,
                    IERC20(usds),
                    convertibleDepositFacility,
                    annualInterestRate
                )
            );
        } else {
            console2.log("Annual Interest Rate unchanged:", annualInterestRate);
        }

        if (currentMaxBorrowPercentage != maxBorrowPercentage) {
            console2.log("Max Borrow Percentage changed:");
            console2.log("orig: ", currentMaxBorrowPercentage);
            console2.log("new:  ", maxBorrowPercentage);
            addToBatch(
                depositRedemptionVault,
                abi.encodeWithSelector(
                    IDepositRedemptionVault.setMaxBorrowPercentage.selector,
                    IERC20(usds),
                    convertibleDepositFacility,
                    maxBorrowPercentage
                )
            );
        } else {
            console2.log("Max Borrow Percentage unchanged:", maxBorrowPercentage);
        }
    }

    /// @notice Configure reclaim rates for deposit periods
    /// @dev    Perform this after configuring deposit periods
    function _configureReclaimRates(
        address convertibleDepositFacility,
        address usds,
        uint256[] memory reclaimRatePeriods,
        uint256[] memory reclaimRates
    ) internal {
        // solhint-disable-next-line gas-custom-errors
        require(
            reclaimRatePeriods.length == reclaimRates.length,
            "ConvertibleDepositInstall: reclaimRatePeriods and reclaimRates must have same length"
        );

        for (uint256 i = 0; i < reclaimRatePeriods.length; i++) {
            uint8 period = SafeCast.encodeUInt8(reclaimRatePeriods[i]);
            uint16 desiredReclaimRate = SafeCast.encodeUInt16(reclaimRates[i]);
            uint16 currentReclaimRate = IDepositFacility(convertibleDepositFacility)
                .getAssetPeriodReclaimRate(IERC20(usds), period);

            if (currentReclaimRate != desiredReclaimRate) {
                console2.log("Reclaim Rate for period", period);
                console2.log("orig: ", currentReclaimRate);
                console2.log("new:  ", desiredReclaimRate);
                addToBatch(
                    convertibleDepositFacility,
                    abi.encodeWithSelector(
                        IDepositFacility.setAssetPeriodReclaimRate.selector,
                        IERC20(usds),
                        period,
                        desiredReclaimRate
                    )
                );
            } else {
                console2.log("Reclaim Rate for period", period);
                console2.log("unchanged:", desiredReclaimRate);
            }
        }
    }

    /// @notice Configure emissions parameters
    function _configureEmissionsParameters(
        address emissionManager,
        uint256 minPriceScalarDesired,
        uint256 baseEmissionsRateDesired
    ) internal {
        uint256 currentMinPriceScalar = EmissionManager(emissionManager).minPriceScalar();
        uint256 currentBaseEmissionsRate = EmissionManager(emissionManager).baseEmissionRate();

        if (currentMinPriceScalar != minPriceScalarDesired) {
            console2.log("Min Price Scalar changed:");
            console2.log("orig: ", currentMinPriceScalar);
            console2.log("new:  ", minPriceScalarDesired);
            addToBatch(
                emissionManager,
                abi.encodeWithSelector(
                    EmissionManager.setMinPriceScalar.selector,
                    minPriceScalarDesired
                )
            );
        } else {
            console2.log("Min Price Scalar unchanged:", minPriceScalarDesired);
        }

        if (currentBaseEmissionsRate != baseEmissionsRateDesired) {
            console2.log("Base Emissions Rate changed:");
            console2.log("orig: ", currentBaseEmissionsRate);
            console2.log("new:  ", baseEmissionsRateDesired);
            uint256 changeNeeded;
            bool shouldAdd;
            if (baseEmissionsRateDesired > currentBaseEmissionsRate) {
                changeNeeded = baseEmissionsRateDesired - currentBaseEmissionsRate;
                shouldAdd = true;
            } else {
                changeNeeded = currentBaseEmissionsRate - baseEmissionsRateDesired;
                shouldAdd = false;
            }
            addToBatch(
                emissionManager,
                abi.encodeWithSelector(
                    EmissionManager.changeBaseRate.selector,
                    changeNeeded,
                    uint48(1), // Next heartbeat
                    shouldAdd
                )
            );
        } else {
            console2.log("Base Emissions Rate unchanged:", baseEmissionsRateDesired);
        }
    }

    /// @notice Configure deposit periods (enable/disable)
    function _configureDepositPeriods(
        address convertibleDepositAuctioneer,
        address convertibleDepositFacility,
        address usds,
        uint256[] memory enabledPeriods
    ) internal {
        uint8[] memory currentEnabledPeriods = IConvertibleDepositAuctioneer(
            convertibleDepositAuctioneer
        ).getDepositPeriods();

        // Disable all currently enabled periods that are not in the desired list
        for (uint256 i = 0; i < currentEnabledPeriods.length; i++) {
            uint8 period = currentEnabledPeriods[i];
            bool shouldBeEnabled = false;
            for (uint256 j = 0; j < enabledPeriods.length; j++) {
                if (SafeCast.encodeUInt8(enabledPeriods[j]) == period) {
                    shouldBeEnabled = true;
                    break;
                }
            }
            if (!shouldBeEnabled) {
                console2.log("Disabling deposit period:", period);
                addToBatch(
                    convertibleDepositAuctioneer,
                    abi.encodeWithSelector(
                        IConvertibleDepositAuctioneer.disableDepositPeriod.selector,
                        period
                    )
                );
                console2.log("Setting reclaim rate to 0 for disabled period:", period);
                addToBatch(
                    convertibleDepositFacility,
                    abi.encodeWithSelector(
                        IDepositFacility.setAssetPeriodReclaimRate.selector,
                        IERC20(usds),
                        period,
                        uint16(0)
                    )
                );
            }
        }

        // Enable all desired periods that are not currently enabled
        for (uint256 i = 0; i < enabledPeriods.length; i++) {
            uint8 period = SafeCast.encodeUInt8(enabledPeriods[i]);
            (bool isEnabled, ) = IConvertibleDepositAuctioneer(convertibleDepositAuctioneer)
                .isDepositPeriodEnabled(period);

            if (!isEnabled) {
                console2.log("Enabling deposit period:", period);
                addToBatch(
                    convertibleDepositAuctioneer,
                    abi.encodeWithSelector(
                        IConvertibleDepositAuctioneer.enableDepositPeriod.selector,
                        period
                    )
                );
            } else {
                console2.log("Deposit period already enabled:", period);
            }
        }
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
