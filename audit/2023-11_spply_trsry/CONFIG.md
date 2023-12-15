# Configuration

This file contains details on how the TRSRY and SPPLY modules will be configured. It should help auditors in assessing risks.

A Solidity-based batch script system is used to add contract calls into a batch for a Safe Multi-sig. The function is `addToBatch()`, which you will see used routinely below.

## TRSRY Configuration

TreasuryConfig (not in scope in this audit, and not in the current repository) is a permissioned policy that simply forwards on the call to the TRSRY module.

For example:

```solidity
    /// @notice Add a new asset to the treasury for tracking
    /// @param asset_ The address of the asset to add
    /// @param locations_ Array of locations other than TRSRY to get balance from
    function addAsset(
        address asset_,
        address[] calldata locations_
    ) external onlyRole("treasuryconfig_policy") {
        TRSRY.addAsset(asset_, locations_);
    }
```

Here is how TRSRY will be configured:

```solidity
        // 5. Install the new TreasuryConfig
        {
            console2.log("Installing new TreasuryConfig");

            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.ActivatePolicy,
                    treasuryConfig
                )
            );
            console2.log("    Installed new TreasuryConfig");
        }

        // 6. Set roles for policy access control
        //  - Give DAO MS the treasuryconfig_policy role
        {
            console2.log("Granting policy role for TreasuryConfig policy");
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("treasuryconfig_policy"),
                    daoMS
                )
            );
        }

        // 7. Add and categorize DAI on TreasuryCustodian
        //      - liquid, stable, reserves
        //      - Clearinghouse policies use the debt functionality, so don't need to be explicitly added
        address[] memory locations = new address[](2);
        locations[0] = daoWorkingWallet;
        locations[1] = daoMS;
        console2.log("Adding DAI to TRSRY");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(TreasuryConfig.addAsset.selector, dai, locations)
        );
        console2.log("    Categorizing DAI as liquid");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("    Categorizing DAI as stable");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("stable")
            )
        );
        console2.log("    Categorizing DAI as reserves");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("reserves")
            )
        );

        // 8. Add and categorize sDAI on TreasuryCustodian
        //      - liquid, stable, reserves
        console2.log("Adding sDAI to TRSRY");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(TreasuryConfig.addAsset.selector, sdai, locations)
        );
        console2.log("    Categorizing sDAI as liquid");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("    Categorizing sDAI as stable");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("stable")
            )
        );
        console2.log("    Categorizing sDAI as reserves");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("reserves")
            )
        );

        // 9. Add and categorize WETH
        //      - liquid, volatile, strategic
        console2.log("Adding WETH to TRSRY");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(TreasuryConfig.addAsset.selector, weth, locations)
        );
        console2.log("    Categorizing WETH as liquid");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("    Categorizing WETH as volatile");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("volatile")
            )
        );
        console2.log("    Categorizing WETH as strategic");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("strategic")
            )
        );

        // 10. Add and categorize veFXS
        //      - illiquid, volatile, strategic
        address[] memory veFXSLocations = new address[](3);
        veFXSLocations[0] = veFXSAllocator;
        veFXSLocations[1] = daoMS;
        veFXSLocations[2] = daoWorkingWallet;
        console2.log("Adding veFXS to TRSRY");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(TreasuryConfig.addAsset.selector, veFXS, veFXSLocations)
        );
        console2.log("    Categorizing veFXS as illiquid");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("illiquid")
            )
        );
        console2.log("    Categorizing veFXS as volatile");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("volatile")
            )
        );
        console2.log("    Categorizing veFXS as strategic");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("strategic")
            )
        );

        // 11. Add and categorize FXS
        //      - illiquid, volatile, strategic
        console2.log("Adding FXS to TRSRY");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(TreasuryConfig.addAsset.selector, fxs, veFXSLocations)
        );
        console2.log("    Categorizing FXS as liquid");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("    Categorizing FXS as volatile");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("volatile")
            )
        );
        console2.log("    Categorizing FXS as strategic");
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("strategic")
            )
        );
```

## SPPLY Configuration

SupplyConfig (not in scope in this audit, and not in the current repository) is a permissioned policy that simply forwards on the call to the SPPLY module.

For example:

```solidity
    /// @notice Add a new category to the supply tracking system
    /// @param category_ The category to add
    function addSupplyCategory(
        SupplyCategory category_,
        bool useSubmodules_,
        bytes4 submoduleSelector_,
        bytes4 submoduleReservesSelector_
    ) external onlyRole("supplyconfig_policy") {
        SPPLY.addCategory(
            category_,
            useSubmodules_,
            submoduleSelector_,
            submoduleReservesSelector_
        );
    }
```

Here is how SPPLY will be configured:

```solidity
        // 1. Install the OlympusSupply module
        console2.log("Installing OlympusSupply module");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, spply)
        );

        // 2. Install the SupplyConfig policy
        console2.log("Installing SupplyConfig policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                supplyConfig
            )
        );

        // 3. Set roles for policy access control
        //  - Give DAO MS the supplyconfig_admin role
        //  - Give policy MS and DAO MS the supplyconfig_policy role
        console2.log("Granting admin role for SupplyConfig policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("supplyconfig_admin"),
                daoMS
            )
        );
        console2.log("Granting policy role for SupplyConfig policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("supplyconfig_policy"),
                daoMS
            )
        );
        console2.log("Granting policy role for SupplyConfig policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("supplyconfig_policy"),
                policyMS
            )
        );

        // 4. Install the BLVaultSupply submodule on the OlympusSupply module
        //  - The Lido and LUSD BLVaultManagers were already added as managers at deployment-time
        console2.log("Installing BLVaultSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.installSubmodule.selector,
                BLVaultSupply(blVaultSupply)
            )
        );

        // 5. Install the BunniSupply submodule on the OlympusSupply module
        // No configuration needed - will be performed by BunniManager
        console2.log("Installing BunniSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(SupplyConfig.installSubmodule.selector, BunniSupply(bunniSupply))
        );

        // 6. Install the MigrationOffsetSupply submodule on the OlympusSupply module
        // No configuration needed - already done at deployment
        console2.log("Installing MigrationOffsetSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.installSubmodule.selector,
                MigrationOffsetSupply(migrationOffsetSupply)
            )
        );

        // 7. Install the BrickedSupply submodule on the OlympusSupply module
        // No configuration needed - already done at deployment
        console2.log("Installing BrickedSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.installSubmodule.selector,
                BrickedSupply(brickedSupply)
            )
        );

        // 8. Categorize protocol-owned-treasury supply
        console2.log("Categorizing DAO MS as protocol-owned-treasury supply");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.categorizeSupply.selector,
                daoMS,
                SupplyCategory.wrap("protocol-owned-treasury")
            )
        );

        // 9. Categorize DAO supply
        console2.log("Categorizing DAO working wallet as DAO supply");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.categorizeSupply.selector,
                daoWorkingWallet,
                SupplyCategory.wrap("dao")
            )
        );

        // 10. Deactivate the old CrossChainBridge policy
        console2.log("Deactivating old CrossChainBridge policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                crossChainBridgeV1
            )
        );

        // 11. Activate the new CrossChainBridge policy
        //  - No need to set the admin role, as it was already set when the first version of the policy was installed
        console2.log("Activating new CrossChainBridge policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                crossChainBridgeV1_1
            )
        );

        // 12. Set trusted remotes on the new CrossChainBridge policy
        console2.log("Setting Arbitrum bridge as trusted remote on new CrossChainBridge policy");
        addToBatch(
            crossChainBridgeV1_1,
            abi.encodeWithSelector(
                CrossChainBridge.setTrustedRemoteAddress.selector,
                110,
                abi.encode(arbBridge)
            )
        );
        console2.log("Setting Optimism bridge as trusted remote on new CrossChainBridge policy");
        addToBatch(
            crossChainBridgeV1_1,
            abi.encodeWithSelector(
                CrossChainBridge.setTrustedRemoteAddress.selector,
                111,
                abi.encode(opBridge)
            )
        );
```
