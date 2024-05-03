// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IFXSAllocator} from "interfaces/IFXSAllocator.sol";

// Bophades
import "src/Kernel.sol";

// Bophades modules
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {TRSRYv1_1} from "modules/TRSRY/TRSRY.v1.sol";
import {Category as AssetCategory} from "modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";

// Bophades policies
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {TreasuryConfig} from "policies/OCA/TreasuryConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Operator} from "policies/RBS/Operator.sol";

/// @notice     Migrates to TRSRY v1.1
contract RBSv2Install_1_TRSRY is OlyBatch, StdAssertions {
    using stdJson for string;

    // Existing Olympus contracts
    address kernel;
    address rolesAdmin;
    address operator;
    address treasuryV1;
    address treasuryCustodian;
    address treasuryConfig;
    address clearinghouseV1;
    address clearinghouseV1_1;
    address veFXSAllocator;
    address dsrAllocator;
    address roles;

    // Tokens
    address dai;
    address sdai;
    address lusd;
    address wsteth;
    address bal;
    address aura;
    address fxs;
    address veFXS;
    address weth;
    address btrfly;

    // New contracts
    address treasuryV1_1;

    // Wallets
    address daoWorkingWallet;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        operator = envAddress("current", "olympus.policies.Operator");

        treasuryV1 = envAddress("current", "olympus.modules.OlympusTreasuryV1");
        treasuryV1_1 = envAddress("current", "olympus.modules.OlympusTreasuryV1_1");
        roles = envAddress("current", "olympus.modules.OlympusRoles");
        treasuryCustodian = envAddress("current", "olympus.policies.TreasuryCustodian");
        treasuryConfig = envAddress("current", "olympus.policies.TreasuryConfig");
        clearinghouseV1 = envAddress("current", "olympus.policies.ClearinghouseV1");
        clearinghouseV1_1 = envAddress("current", "olympus.policies.ClearinghouseV1_1");
        veFXSAllocator = envAddress("current", "olympus.legacy.veFXSAllocator");
        dsrAllocator = envAddress("current", "olympus.legacy.dsrAllocator");

        dai = envAddress("current", "external.tokens.DAI");
        sdai = envAddress("current", "external.tokens.sDAI");
        lusd = envAddress("current", "external.tokens.LUSD");
        wsteth = envAddress("current", "external.tokens.WSTETH");
        bal = envAddress("current", "external.tokens.BAL");
        aura = envAddress("current", "external.tokens.AURA");
        fxs = envAddress("current", "external.tokens.FXS");
        veFXS = envAddress("current", "external.tokens.veFXS");
        weth = envAddress("current", "external.tokens.WETH");
        btrfly = envAddress("current", "external.tokens.BTRFLY");

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");

        // Make sure TRSRY addresses are correct
        assertFalse(
            treasuryV1_1 == treasuryV1,
            "New TRSRY address should be different from old TRSRY address"
        );
    }

    function RBSv2Install_1_TRSRY_1(bool send_) public isDaoBatch(send_) {
        withdrawAllAssets();
    }

    function RBSv2Install_1_TRSRY_2(bool send_) public isDaoBatch(send_) {
        setupTreasury();
    }

    function RBSv2Install_1_TRSRY_3(bool send_) public isDaoBatch(send_) {
        deposit();
    }

    function _withdrawToDaoMs(string memory assetName_, address asset_) internal {
        uint256 trsryBefore = ERC20(asset_).balanceOf(treasuryV1);
        uint256 daoMSBefore = ERC20(asset_).balanceOf(daoMS);
        console2.log("Transferring %s from TRSRY v1 to DAO MS", assetName_);
        if (trsryBefore == 0) {
            console2.log("    %s balance in TRSRY v1 is 0. Skipping.", assetName_);
            return;
        }

        console2.log("    %s balance in DAO MS before: %s (18dp)", assetName_, daoMSBefore);

        // Approval
        addToBatch(
            treasuryCustodian,
            abi.encodeWithSelector(
                TreasuryCustodian.grantWithdrawerApproval.selector,
                treasuryCustodian,
                asset_,
                trsryBefore
            )
        );

        // Withdraw
        addToBatch(
            treasuryCustodian,
            abi.encodeWithSelector(
                TreasuryCustodian.withdrawReservesTo.selector,
                daoMS,
                asset_,
                trsryBefore
            )
        );
        console2.log("    Transfered %s: %s (18dp)", assetName_, trsryBefore);

        // Validate
        uint256 trsryAfter = ERC20(asset_).balanceOf(treasuryV1);
        uint256 daoMSAfter = ERC20(asset_).balanceOf(daoMS);

        console2.log("    %s balance in TRSRY v1 after: %s (18dp)", assetName_, trsryAfter);
        console2.log("    %s balance in DAO MS: %s (18dp)", assetName_, daoMSAfter);
        console2.log(
            "    Difference in %s balance in DAO MS: %s (18dp)",
            assetName_,
            daoMSAfter - daoMSBefore
        );

        if (trsryAfter > 0) {
            revert("%s balance in TRSRY v1 is not 0");
        }
    }

    function _depositToTrsry(string memory assetName_, address asset_) internal {
        uint256 balance = ERC20(asset_).balanceOf(daoMS);
        console2.log("Depositing %s to TRSRY v1.1", assetName_);
        console2.log("    %s balance in DAO MS: %s (18dp)", assetName_, balance);

        if (balance == 0) {
            console2.log("    %s balance in DAO MS is 0. Skipping.", assetName_);
            return;
        }

        console2.log("    Approving withdrawn %s for transfer to TRSRY v1.1", assetName_);
        addToBatch(asset_, abi.encodeWithSelector(ERC20.approve.selector, treasuryV1_1, balance));

        console2.log("    Depositing withdrawn %s from DAO MS to TRSRY v1.1", assetName_);
        addToBatch(asset_, abi.encodeWithSelector(ERC20.transfer.selector, treasuryV1_1, balance));
        console2.log("    Deposited %s: %s (18dp)", assetName_, balance);

        // Validate
        uint256 balanceAfter = ERC20(asset_).balanceOf(treasuryV1_1);
        if (balanceAfter != balance) {
            revert("%s balance in TRSRY v1.1 does not match the deposited amount");
        }
    }

    function _addTreasuryAsset(
        string memory assetName_,
        address asset_,
        string memory category1_,
        string memory category2_,
        string memory category3_,
        address[] memory locations_
    ) internal {
        console2.log("Adding %s (%s) to TRSRY", assetName_, asset_);
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(TreasuryConfig.addAsset.selector, asset_, locations_)
        );
        console2.log("    Categorizing %s as %s", assetName_, category1_);
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                asset_,
                AssetCategory.wrap(bytes32(bytes(category1_)))
            )
        );
        console2.log("    Categorizing %s as %s", assetName_, category2_);
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                asset_,
                AssetCategory.wrap(bytes32(bytes(category2_)))
            )
        );
        console2.log("    Categorizing %s as %s", assetName_, category3_);
        addToBatch(
            treasuryConfig,
            abi.encodeWithSelector(
                TreasuryConfig.categorizeAsset.selector,
                asset_,
                AssetCategory.wrap(bytes32(bytes(category3_)))
            )
        );
    }

    function withdrawAllAssets() public {
        // This DAO MS batch:
        // 1. Transfers all tokens from the old treasury to the DAO MS
        // 2. Disables the Operator

        console2.log("*** TRSRY v1 withdraw");
        console2.log("TRSRY v1: %s", treasuryV1);
        console2.log("TRSRY v1.1: %s", treasuryV1_1);
        console2.log("DAO MS: %s", daoMS);

        // 1. Transfers all tokens from the old treasury to the DAO MS
        // DAI
        _withdrawToDaoMs("DAI", dai);

        // sDAI
        _withdrawToDaoMs("sDAI", sdai);

        // LUSD
        _withdrawToDaoMs("LUSD", lusd);

        // wstETH
        _withdrawToDaoMs("wstETH", wsteth);

        // Balancer
        _withdrawToDaoMs("BAL", bal);

        // Aura
        _withdrawToDaoMs("AURA", aura);

        // 2. Disables the Operator
        // This is to avoid having any bond markets open while TRSRY v1 and v1.1 is without funds
        {
            if (!ROLESv1(roles).hasRole(daoMS, bytes32("operator_policy"))) {
                console2.log("Granting the operator_policy role to the DAO MS");
                addToBatch(
                    rolesAdmin,
                    abi.encodeWithSelector(
                        RolesAdmin.grantRole.selector,
                        bytes32("operator_policy"),
                        daoMS
                    )
                );

                console2.log("Disabling the Operator");
                addToBatch(operator, abi.encodeWithSelector(Operator.deactivate.selector));
            } else {
                console2.log("DAO MS already has the operator_policy role");
            }
        }

        console2.log("*** Complete\n\n");
    }

    /// @notice     This function is separate from the DAO batch, so it can be called externally while testing
    function setupTreasury() public {
        // This DAO MS batch:
        // 1. Records the current debt of the old treasury
        // 2. Upgrades the OlympusTreasury contract to the new version
        // 3. Sets debt on the new treasury contract
        // 4. Installs the new TreasuryCustodian
        // 5. Set roles for policy access control
        // 6. Add and categorize DAI in TRSRY
        // 7. Add and categorize sDAI in TRSRY
        // 8. Add and categorize WETH in TRSRY
        // 9. Add and categorize veFXS in TRSRY
        // 10. Add and categorize FXS in TRSRY
        // 11. Add and categorize BTRFLY in TRSRY

        string memory argData = vm.readFile("./src/scripts/ops/batches/RBSv2Install_1_TRSRY.json");

        console2.log("*** TRSRY v1.1 setup");
        console2.log("TRSRY v1.1: %s", treasuryV1_1);
        console2.log("DAI: %s", dai);
        console2.log("sDAI: %s", sdai);
        console2.log("WETH: %s", weth);
        console2.log("veFXS: %s", veFXS);
        console2.log("FXS: %s", fxs);
        console2.log("BTRFLY: %s", btrfly);

        // 1. Record the current debt of the old treasury
        OlympusTreasury trsryModule = OlympusTreasury(treasuryV1);

        // DAI
        // - Clearinghouse debt is denominated in DAI
        // - This currently excludes the DSRAllocator, as it is assumed that DAI in the DSR will be migrated to sDAI before activation
        uint256 daiClearinghouseV1Debt;
        uint256 daiClearinghouseV1_1Debt;
        {
            console2.log("Getting DAI debt");

            ERC20 daiToken = ERC20(dai);
            uint256 daiTotalDebt = trsryModule.totalDebt(daiToken);
            console2.log("    Total DAI debt: %s", daiTotalDebt);

            daiClearinghouseV1Debt = trsryModule.reserveDebt(daiToken, clearinghouseV1);
            console2.log("    ClearinghouseV1 DAI debt: %s", daiClearinghouseV1Debt);

            daiClearinghouseV1_1Debt = trsryModule.reserveDebt(daiToken, clearinghouseV1_1);
            console2.log("    ClearinghouseV1_1 DAI debt: %s", daiClearinghouseV1_1Debt);

            uint256 dsrAllocatorDebt = trsryModule.reserveDebt(daiToken, dsrAllocator);
            console2.log("    DSRAllocator DAI debt: %s", dsrAllocatorDebt);
            if (dsrAllocatorDebt > 0) {
                revert("DSRAllocator DAI debt is not 0");
            }
            if (daiToken.balanceOf(treasuryV1) > 0) {
                revert("DAI balance in TRSRY v1 is not 0");
            }

            if (
                daiClearinghouseV1Debt + daiClearinghouseV1_1Debt + dsrAllocatorDebt != daiTotalDebt
            ) {
                revert("Clearinghouse DAI debt does not equal total debt");
            }
            console2.log("    Total DAI debt matches clearinghouse + DSR allocator debt");
        }

        // sDAI
        {
            console2.log("Getting sDAI debt");

            ERC20 sdaiToken = ERC20(sdai);
            uint256 sdaiTotalDebt = trsryModule.totalDebt(sdaiToken);
            console2.log("    Total sDAI debt: %s", sdaiTotalDebt);
            if (sdaiTotalDebt > 0) {
                revert("sDAI debt is not 0");
            }
            if (sdaiToken.balanceOf(treasuryV1) > 0) {
                revert("sDAI balance in TRSRY v1 is not 0");
            }
        }

        // wETH
        {
            console2.log("Getting WETH debt");

            ERC20 wethToken = ERC20(weth);
            uint256 wethTotalDebt = trsryModule.totalDebt(wethToken);
            console2.log("    Total WETH debt: %s", wethTotalDebt);
            if (wethTotalDebt > 0) {
                revert("WETH debt is not 0");
            }
            if (wethToken.balanceOf(treasuryV1) > 0) {
                revert("WETH balance in TRSRY v1 is not 0");
            }
        }

        // FXS
        {
            console2.log("Getting FXS debt");

            ERC20 fxsToken = ERC20(fxs);
            uint256 fxsTotalDebt = trsryModule.totalDebt(fxsToken);
            console2.log("    Total FXS debt: %s", fxsTotalDebt);
            if (fxsTotalDebt > 0) {
                revert("FXS debt is not 0");
            }
            if (fxsToken.balanceOf(treasuryV1) > 0) {
                revert("FXS balance in TRSRY v1 is not 0");
            }
        }

        // veFXS is in an allocator, have no balance in the current treasury, but also don't have any debt value set
        uint256 vefxsAllocatorBalance;
        {
            console2.log("Getting veFXS debt");

            IFXSAllocator vefxsAllocatorContract = IFXSAllocator(veFXSAllocator);
            ERC20 vefxsToken = ERC20(veFXS);

            vefxsAllocatorBalance = vefxsAllocatorContract.totalAmountDeployed();
            console2.log("    veFXS allocator balance: %s", vefxsAllocatorBalance);

            uint256 vefxsTotalDebt = trsryModule.totalDebt(vefxsToken);
            console2.log("    Total veFXS debt: %s", vefxsTotalDebt);
            if (vefxsTotalDebt > 0) {
                revert("veFXS debt is not 0");
            }
            if (vefxsToken.balanceOf(treasuryV1) > 0) {
                revert("veFXS balance in TRSRY v1 is not 0");
            }
        }

        // 2. Upgrade the OlympusTreasury contract to the new version
        {
            console2.log("Upgrading TRSRY module to new version at %s", treasuryV1_1);

            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.UpgradeModule,
                    treasuryV1_1
                )
            );
            console2.log("    Upgraded OlympusTreasury to new version");
        }

        // 3. Transfer debt over to the new treasury
        // TreasuryCustodian.increaseDebt can be used as the existing debt is 0

        // DAI
        {
            console2.log("Setting DAI debt on new TRSRY");
            console2.log("    ClearinghouseV1 DAI debt: %s", daiClearinghouseV1Debt);
            console2.log("    ClearinghouseV1_1 DAI debt: %s", daiClearinghouseV1_1Debt);
            console2.log(
                "    Total DAI debt: %s",
                daiClearinghouseV1Debt + daiClearinghouseV1_1Debt
            );

            ERC20 daiToken = ERC20(dai);
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.increaseDebt.selector,
                    daiToken,
                    clearinghouseV1,
                    daiClearinghouseV1Debt
                )
            );
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.increaseDebt.selector,
                    daiToken,
                    clearinghouseV1_1,
                    daiClearinghouseV1_1Debt
                )
            );
        }

        // sDAI: no debt
        {
            console2.log("No sDAI debt");
        }

        // wETH
        {
            console2.log("Setting wETH debt on new TRSRY");
            ERC20 wEthToken = ERC20(weth);

            {
                // Quantity deployed in mainnet POL
                uint256 polMainnetQuantity = argData.readUint("ethPolMainnetQuantity");
                console2.log("    Mainnet POL debt: %s (18dp)", polMainnetQuantity);

                addToBatch(
                    treasuryCustodian,
                    abi.encodeWithSelector(
                        TreasuryCustodian.increaseDebt.selector,
                        wEthToken,
                        daoMS, // Withdrawn by DAO MS before depositing into LP
                        polMainnetQuantity
                    )
                );
            }

            {
                // Quantity deployed in Arbitrum POL
                // TX: https://arbiscan.io/tx/0x16ac1ba3fb9806a01f5fe2e1601d4df55a22379b2d07e52938e77b9a34080d56
                uint256 polArbitrumQuantity = argData.readUint("ethPolArbitrumQuantity");
                address polArbitrumLocation = argData.readAddress("ethPolArbitrumLocation");
                console2.log("    Arbitrum POL debt: %s (18dp)", polArbitrumQuantity);

                addToBatch(
                    treasuryCustodian,
                    abi.encodeWithSelector(
                        TreasuryCustodian.increaseDebt.selector,
                        wEthToken,
                        polArbitrumLocation, // Arbitrum MS
                        polArbitrumQuantity
                    )
                );
            }

            {
                // Quantity deployed in Base POL
                // TX: TBC
                uint256 polBaseQuantity = argData.readUint("ethPolBaseQuantity");
                address polBaseLocation = argData.readAddress("ethPolBaseLocation");
                console2.log("    Base POL debt: %s (18dp)", polBaseQuantity);

                addToBatch(
                    treasuryCustodian,
                    abi.encodeWithSelector(
                        TreasuryCustodian.increaseDebt.selector,
                        wEthToken,
                        polBaseLocation, // Base MS
                        polBaseQuantity
                    )
                );
            }
        }

        // FXS: no debt
        {
            console2.log("No FXS debt");
        }

        // veFXS
        {
            console2.log(
                "Setting veFXS debt on new TRSRY is being skipped, as veFXS is not being tracked."
            );
            // console2.log("Setting veFXS debt on new TRSRY: %s (18dp)", vefxsAllocatorBalance);

            // ERC20 vefxsToken = ERC20(veFXS);
            // addToBatch(
            //     treasuryCustodian,
            //     abi.encodeWithSelector(
            //         TreasuryCustodian.increaseDebt.selector,
            //         vefxsToken,
            //         veFXSAllocator,
            //         vefxsAllocatorBalance
            //     )
            // );
        }

        // 4. Install the new TreasuryConfig
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

        // 5. Set roles for policy access control
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

        // 6. Add and categorize DAI on TreasuryCustodian
        //      - liquid, stable, reserves
        //      - Clearinghouse policies use the debt functionality, so don't need to be explicitly added
        address[] memory locations = new address[](2);
        locations[0] = daoWorkingWallet;
        locations[1] = daoMS;

        _addTreasuryAsset("DAI", dai, "liquid", "stable", "reserves", locations);

        // 7. Add and categorize sDAI on TreasuryCustodian
        //      - liquid, stable, reserves
        _addTreasuryAsset("sDAI", sdai, "liquid", "stable", "reserves", locations);

        // 8. Add and categorize WETH
        //      - liquid, volatile, strategic
        //      - disabled, as a TRSRY asset without a PRICE configuration will cause Appraiser to revert
        _addTreasuryAsset("WETH", weth, "liquid", "volatile", "strategic", locations);

        // 9. Add and categorize veFXS
        //      - illiquid, volatile, strategic
        //      - excludes the veFXS allocator balance, since the deployed amount is accounted for in debt
        //      - disabled, as a TRSRY asset without a PRICE configuration will cause Appraiser to revert
        // address[] memory veFXSLocations = new address[](2);
        // veFXSLocations[0] = daoMS;
        // veFXSLocations[1] = daoWorkingWallet;

        // _addTreasuryAsset("veFXS", veFXS, "illiquid", "volatile", "strategic", veFXSLocations);

        // 10. Add and categorize FXS
        //      - liquid, volatile, strategic
        //      - disabled, as a TRSRY asset without a PRICE configuration will cause Appraiser to revert
        // _addTreasuryAsset("FXS", fxs, "liquid", "volatile", "strategic", veFXSLocations);

        // 11. Add and categorize BTRFLY
        //      - liquid, volatile, strategic
        //      - disabled, as a TRSRY asset without a PRICE configuration will cause Appraiser to revert
        // _addTreasuryAsset("BTRFLY", btrfly, "liquid", "volatile", "strategic", locations);

        // Reporting
        console2.log("Testing TRSRY v1.1 (pre-deposit)");
        OlympusTreasury trsry = OlympusTreasury(treasuryV1_1);
        address[] memory assets = trsry.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            console2.log("    Asset: %s", asset);
            (uint256 totalBalance, ) = trsry.getAssetBalance(asset, TRSRYv1_1.Variant.CURRENT);
            uint256 debt = trsry.totalDebt(ERC20(asset));
            console2.log("        Total balance: %s", totalBalance);
            console2.log("        Balance: %s", totalBalance - debt);
            console2.log("        Debt: %s", debt);
        }

        console2.log("*** Complete\n\n");
    }

    function deposit() public {
        // This DAO MS batch:
        // 1. Deposits assets from the DAO MS into TRSRY v1.1
        // 2. Activates the Operator

        console2.log("*** TRSRY v1.1 deposit");
        console2.log("DAO MS: %s", daoMS);
        console2.log("TRSRY v1.1: %s", treasuryV1_1);

        // 1a. DAI
        _depositToTrsry("DAI", dai);

        // 1b. sDAI
        _depositToTrsry("sDAI", sdai);

        // Other assets are not deposited and remain in the DAO MS

        // 2. Activates the Operator
        {
            console2.log("Activating the Operator");
            addToBatch(operator, abi.encodeWithSelector(Operator.activate.selector));

            console2.log("Revoking the operator_policy role from the DAO MS");
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.revokeRole.selector,
                    bytes32("operator_policy"),
                    daoMS
                )
            );
        }

        // Reporting
        console2.log("Testing TRSRY v1.1 (post-deposit)");
        OlympusTreasury trsry = OlympusTreasury(treasuryV1_1);
        address[] memory assets = trsry.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            console2.log("    Asset: %s", asset);
            (uint256 totalBalance, ) = trsry.getAssetBalance(asset, TRSRYv1_1.Variant.CURRENT);
            uint256 debt = trsry.totalDebt(ERC20(asset));
            console2.log("        Total balance: %s", totalBalance);
            console2.log("        Balance: %s", totalBalance - debt);
            console2.log("        Debt: %s", debt);
        }

        console2.log("*** Complete\n\n");
    }

    function RBSv2Install_1_TRSRY_TEST(bool) external {
        // For testing purposes only
        initTestBatch();
        withdrawAllAssets();
        setupTreasury();
        deposit();
    }
}
