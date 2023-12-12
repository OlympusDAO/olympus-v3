// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {Category as AssetCategory} from "modules/TRSRY/TRSRY.v1.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";

import {IFXSAllocator} from "interfaces/IFXSAllocator.sol";

/// @notice     Migrates to TRSRY v1.1
contract RBSv2Install_1_TRSRY is OlyBatch, StdAssertions {
    // Existing Olympus contracts
    address kernel;
    address treasuryV1;
    address treasuryCustodianV1;
    address treasuryCustodianV1_1;
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
        treasuryV1 = envAddress("current", "olympus.modules.OlympusTreasuryV1");
        treasuryV1_1 = envAddress("current", "olympus.modules.OlympusTreasuryV1_1");
        treasuryCustodianV1 = envAddress("current", "olympus.policies.TreasuryCustodianV1");
        treasuryCustodianV1_1 = envAddress("current", "olympus.policies.TreasuryCustodianV1_1");
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

    function RBSv2Install_1_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Transfers all tokens from the old treasury to the new treasury
        // 2. Records the current debt of the old treasury
        // 3. Disable the old TreasuryCustodian
        // 4. Upgrades the OlympusTreasury contract to the new version
        // 5. Installs the new TreasuryCustodian
        // 6. Sets debt on the new treasury contract
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
                treasuryCustodianV1,
                abi.encodeWithSelector(
                    TreasuryCustodian.grantWithdrawerApproval.selector,
                    treasuryCustodianV1,
                    dai,
                    daiBalance
                )
            );
            addToBatch(
                treasuryCustodianV1,
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
                treasuryCustodianV1,
                abi.encodeWithSelector(
                    TreasuryCustodian.grantWithdrawerApproval.selector,
                    treasuryCustodianV1,
                    sdai,
                    sdaiBalance
                )
            );
            addToBatch(
                treasuryCustodianV1,
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
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodianV1, lusd, lusdBalance));
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, lusd, lusdBalance));
        // console2.log("Transfered LUSD: %s", lusdBalance);

        // uint256 wstethBalance = ERC20(wsteth).balanceOf(treasuryV1);
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodianV1, wsteth, wstethBalance));
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, wsteth, wstethBalance));
        // console2.log("Transfered wstETH: %s", wstethBalance);

        // uint256 balBalance = ERC20(bal).balanceOf(treasuryV1);
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodianV1, bal, balBalance));
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, bal, balBalance));
        // console2.log("Transfered BAL: %s", balBalance);

        // uint256 auraBalance = ERC20(aura).balanceOf(treasuryV1);
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodianV1, aura, auraBalance));
        // addToBatch(treasuryCustodianV1, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, treasuryV1_1, aura, auraBalance));
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
        }

        // veFXS is in an allocator, have no balance in the current treasury, but also don't have any debt value set
        uint256 vefxsBalance;
        {
            console2.log("Getting veFXS debt");

            IFXSAllocator vefxsAllocatorContract = IFXSAllocator(veFXSAllocator);
            ERC20 vefxsToken = ERC20(veFXS);
            vefxsBalance = vefxsAllocatorContract.totalAmountDeployed();

            uint256 vefxsTotalDebt = trsryModule.totalDebt(vefxsToken);
            assertEq(vefxsTotalDebt, 0, "FXS debt should be 0");
        }

        // 3. Disable the old TreasuryCustodian
        {
            console2.log("Disabling old TreasuryCustodian");

            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.DeactivatePolicy,
                    treasuryCustodianV1
                )
            );
            console2.log("    Deactivated old TreasuryCustodian");
        }

        // 4. Upgrade the OlympusTreasury contract to the new version
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

        // 5. Install the new TreasuryCustodian
        {
            console2.log("Installing new TreasuryCustodian");

            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.ActivatePolicy,
                    treasuryCustodianV1_1
                )
            );
            console2.log("    Installed new TreasuryCustodian");
        }

        // 6. Transfer debt over to the new treasury
        // TreasuryCustodian.increaseDebt can be used as the existing debt is 0

        // DAI
        {
            console2.log("Setting DAI debt on new TRSRY");

            ERC20 daiToken = ERC20(dai);
            addToBatch(
                treasuryCustodianV1_1,
                abi.encodeWithSelector(
                    TreasuryCustodian.increaseDebt.selector,
                    daiToken,
                    clearinghouseV1,
                    daiClearinghouseV1Debt
                )
            );
            addToBatch(
                treasuryCustodianV1_1,
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
                treasuryCustodianV1_1,
                abi.encodeWithSelector(
                    TreasuryCustodian.increaseDebt.selector,
                    vefxsToken,
                    veFXSAllocator,
                    vefxsBalance
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
            treasuryCustodianV1_1,
            abi.encodeWithSelector(TreasuryCustodian.addAsset.selector, dai, locations)
        );
        console2.log("Categorizing DAI as liquid");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("Categorizing DAI as stable");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("stable")
            )
        );
        console2.log("Categorizing DAI as reserves");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                dai,
                AssetCategory.wrap("reserves")
            )
        );

        // 8. Add and categorize sDAI on TreasuryCustodian
        //      - liquid, stable, reserves
        console2.log("Adding sDAI to TRSRY");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(TreasuryCustodian.addAsset.selector, sdai, locations)
        );
        console2.log("Categorizing sDAI as liquid");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("Categorizing sDAI as stable");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("stable")
            )
        );
        console2.log("Categorizing sDAI as reserves");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                sdai,
                AssetCategory.wrap("reserves")
            )
        );

        // 9. Add and categorize WETH
        //      - liquid, volatile, strategic
        console2.log("Adding WETH to TRSRY");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(TreasuryCustodian.addAsset.selector, weth, locations)
        );
        console2.log("Categorizing WETH as liquid");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("Categorizing WETH as volatile");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                weth,
                AssetCategory.wrap("volatile")
            )
        );
        console2.log("Categorizing WETH as strategic");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
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
            treasuryCustodianV1_1,
            abi.encodeWithSelector(TreasuryCustodian.addAsset.selector, veFXS, veFXSLocations)
        );
        console2.log("Categorizing veFXS as illiquid");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("illiquid")
            )
        );
        console2.log("Categorizing veFXS as volatile");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("volatile")
            )
        );
        console2.log("Categorizing veFXS as strategic");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                veFXS,
                AssetCategory.wrap("strategic")
            )
        );

        // 11. Add and categorize FXS
        //      - illiquid, volatile, strategic
        console2.log("Adding FXS to TRSRY");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(TreasuryCustodian.addAsset.selector, fxs, veFXSLocations)
        );
        console2.log("Categorizing FXS as liquid");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("liquid")
            )
        );
        console2.log("Categorizing FXS as volatile");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("volatile")
            )
        );
        console2.log("Categorizing FXS as strategic");
        addToBatch(
            treasuryCustodianV1_1,
            abi.encodeWithSelector(
                TreasuryCustodian.categorizeAsset.selector,
                fxs,
                AssetCategory.wrap("strategic")
            )
        );
    }
}
