// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
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

// Bophades policies
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {TreasuryConfig} from "policies/OCA/TreasuryConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

/// @notice     Migrates to TRSRY v1.1
contract RBSv2Install_1_TRSRY is OlyBatch, StdAssertions {
    // Existing Olympus contracts
    address kernel;
    address rolesAdmin;
    address treasuryV1;
    address treasuryCustodian;
    address treasuryConfig;
    address clearinghouseV1;
    address clearinghouseV1_1;
    address veFXSAllocator;
    address dsrAllocator;

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

    // New contracts
    address treasuryV1_1;

    // Wallets
    address daoWorkingWallet;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");

        treasuryV1 = envAddress("current", "olympus.modules.OlympusTreasuryV1");
        treasuryV1_1 = envAddress("current", "olympus.modules.OlympusTreasuryV1_1");
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

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");

        // Make sure TRSRY addresses are correct
        assertFalse(
            treasuryV1_1 == treasuryV1,
            "New TRSRY address should be different from old TRSRY address"
        );
    }

    /// @notice     This function is separate from the DAO batch, so it can be called externally while testing
    function install() public {
        // This DAO MS batch:
        // 1. Transfers all tokens from the old treasury to the new treasury
        // 2. Records the current debt of the old treasury
        // 3. Upgrades the OlympusTreasury contract to the new version
        // 4. Sets debt on the new treasury contract
        // 5. Installs the new TreasuryCustodian
        // 6. Set roles for policy access control
        // 7. Add and categorize DAI in TRSRY
        // 8. Add and categorize sDAI in TRSRY
        // 9. Add and categorize WETH in TRSRY
        // 10. Add and categorize veFXS in TRSRY
        // 11. Add and categorize FXS in TRSRY

        // 1. Transfer all tokens from the old treasury to the new treasury
        // DAI
        {
            uint256 daiBalance = ERC20(dai).balanceOf(treasuryV1);
            console2.log("Transferring DAI from TRSRY v1 to v1.1");
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.grantWithdrawerApproval.selector,
                    treasuryCustodian,
                    dai,
                    daiBalance
                )
            );
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.withdrawReservesTo.selector,
                    treasuryV1_1,
                    dai,
                    daiBalance
                )
            );
            console2.log("    Transfered DAI: %s", daiBalance);
        }

        // sDAI
        {
            uint256 sdaiBalance = ERC20(sdai).balanceOf(treasuryV1);
            console2.log("Transferring sDAI from TRSRY v1 to v1.1");
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.grantWithdrawerApproval.selector,
                    treasuryCustodian,
                    sdai,
                    sdaiBalance
                )
            );
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.withdrawReservesTo.selector,
                    treasuryV1_1,
                    sdai,
                    sdaiBalance
                )
            );
            console2.log("    Transfered sDAI: %s", sdaiBalance);
        }

        // The following assets exist in TRSRY, but will be swapped for DAI

        // uint256 lusdBalance = ERC20(lusd).balanceOf(treasuryV1);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, lusd, lusdBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, lusd, lusdBalance));
        // console2.log("Transfered LUSD: %s", lusdBalance);

        // uint256 wstethBalance = ERC20(wsteth).balanceOf(treasuryV1);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, wsteth, wstethBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, wsteth, wstethBalance));
        // console2.log("Transfered wstETH: %s", wstethBalance);

        // uint256 balBalance = ERC20(bal).balanceOf(treasuryV1);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, bal, balBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, bal, balBalance));
        // console2.log("Transfered BAL: %s", balBalance);

        // uint256 auraBalance = ERC20(aura).balanceOf(treasuryV1);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, aura, auraBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, aura, auraBalance));
        // console2.log("Transfered AURA: %s", auraBalance);

        // 2. Record the current debt of the old treasury
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
            // TODO add assertion that this is 0, post-sDAI migration
            console2.log("    DSRAllocator DAI debt: %s", dsrAllocatorDebt);

            assertEq(
                daiTotalDebt,
                daiClearinghouseV1Debt + daiClearinghouseV1_1Debt + dsrAllocatorDebt,
                "Clearinghouse DAI debt should equal total debt"
            );
            console2.log("    Total DAI debt matches clearinghouse + DSR allocator debt");
        }

        // sDAI
        {
            console2.log("Getting sDAI debt");

            ERC20 sdaiToken = ERC20(sdai);
            uint256 sdaiTotalDebt = trsryModule.totalDebt(sdaiToken);
            assertEq(sdaiTotalDebt, 0, "sDAI debt should be 0");
        }

        // FXS
        {
            console2.log("Getting FXS debt");

            ERC20 fxsToken = ERC20(fxs);
            uint256 fxsTotalDebt = trsryModule.totalDebt(fxsToken);
            assertEq(fxsTotalDebt, 0, "FXS debt should be 0");

            assertEq(fxsToken.balanceOf(treasuryV1), 0, "FXS balance in treasury v1.0 should be 0");
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
            assertEq(vefxsTotalDebt, 0, "veFXS debt should be 0");

            assertEq(
                vefxsToken.balanceOf(treasuryV1),
                0,
                "veFXS balance in treasury v1.0 should be 0"
            );
        }

        // 3. Upgrade the OlympusTreasury contract to the new version
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

        // 4. Transfer debt over to the new treasury
        // TreasuryCustodian.increaseDebt can be used as the existing debt is 0

        // DAI
        {
            console2.log("Setting DAI debt on new TRSRY");

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

        // FXS: no debt

        // veFXS
        {
            console2.log("Setting veFXS debt on new TRSRY");

            ERC20 vefxsToken = ERC20(veFXS);
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.increaseDebt.selector,
                    vefxsToken,
                    veFXSAllocator,
                    vefxsAllocatorBalance
                )
            );
        }

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
        //      - excludes the veFXS allocator balance, since the deployed amount is accounted for in debt
        address[] memory veFXSLocations = new address[](2);
        veFXSLocations[0] = daoMS;
        veFXSLocations[1] = daoWorkingWallet;
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

        // Reporting
        console2.log("Testing TRSRY");
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
    }

    function RBSv2Install_1_1(bool send_) external isDaoBatch(send_) {
        install();
    }
}
