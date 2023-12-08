// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";

import {IFXSAllocator} from "interfaces/IFXSAllocator.sol";

/// @notice     Migrates to TRSRY v1.1
contract RBSv2Install_1_TRSRY is OlyBatch, StdAssertions {
    // Existing Olympus contracts
    address kernel;
    address trsry;
    address treasuryCustodian;
    address clearinghouseV1;
    address clearinghouseV1_1;
    address vefxsallocator;
    address dsrAllocator;

    // Tokens
    address dai;
    address sdai;
    address lusd;
    address wsteth;
    address bal;
    address aura;
    address fxs;
    address vefxs;

    // New contracts
    address newTrsry;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        trsry = envAddress("current", "olympus.modules.OlympusTreasuryV1");
        treasuryCustodian = envAddress("current", "olympus.policies.TreasuryCustodian");
        clearinghouseV1 = envAddress("current", "olympus.policies.ClearinghouseV1");
        clearinghouseV1_1 = envAddress("current", "olympus.policies.ClearinghouseV1_1");
        vefxsallocator = envAddress("current", "olympus.legacy.veFXSAllocator");
        dsrAllocator = envAddress("current", "olympus.legacy.dsrAllocator");

        dai = envAddress("current", "external.tokens.DAI");
        sdai = envAddress("current", "external.tokens.sDAI");
        lusd = envAddress("current", "external.tokens.LUSD");
        wsteth = envAddress("current", "external.tokens.WSTETH");
        bal = envAddress("current", "external.tokens.BAL");
        aura = envAddress("current", "external.tokens.AURA");
        fxs = envAddress("current", "external.tokens.FXS");
        vefxs = envAddress("current", "external.tokens.veFXS");

        newTrsry = envAddress("current", "olympus.modules.OlympusTreasuryV1_1");

        // Make sure TRSRY addresses are correct
        assertFalse(
            newTrsry == trsry,
            "New TRSRY address should be different from old TRSRY address"
        );
    }

    function RBSv2Install_1_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Transfers all tokens from the old treasury to the new treasury
        // 2. Records the current debt of the old treasury
        // 3. Upgrades the OlympusTreasury contract to the new version
        // 4. Sets debt on the new treasury contract

        // 1. Transfer all tokens from the old treasury to the new treasury
        // DAI
        {
            uint256 daiBalance = ERC20(dai).balanceOf(trsry);
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
                    newTrsry,
                    dai,
                    daiBalance
                )
            );
            console2.log("Transfered DAI: %s", daiBalance);
        }

        // sDAI
        {
            uint256 sdaiBalance = ERC20(sdai).balanceOf(trsry);
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
                    newTrsry,
                    sdai,
                    sdaiBalance
                )
            );
            console2.log("Transfered sDAI: %s", sdaiBalance);
        }

        // The following assets exist in TRSRY, but will be swapped for DAI

        // uint256 lusdBalance = ERC20(lusd).balanceOf(trsry);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, lusd, lusdBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, newTrsry, lusd, lusdBalance));
        // console2.log("Transfered LUSD: %s", lusdBalance);

        // uint256 wstethBalance = ERC20(wsteth).balanceOf(trsry);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, wsteth, wstethBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, newTrsry, wsteth, wstethBalance));
        // console2.log("Transfered wstETH: %s", wstethBalance);

        // uint256 balBalance = ERC20(bal).balanceOf(trsry);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, bal, balBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, newTrsry, bal, balBalance));
        // console2.log("Transfered BAL: %s", balBalance);

        // uint256 auraBalance = ERC20(aura).balanceOf(trsry);
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, aura, auraBalance));
        // addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, newTrsry, aura, auraBalance));
        // console2.log("Transfered AURA: %s", auraBalance);

        // 2. Record the current debt of the old treasury
        OlympusTreasury trsryModule = OlympusTreasury(trsry);

        // DAI
        // - Clearinghouse debt is denominated in DAI
        // - This currently excludes the DSRAllocator, as it is assumed that DAI in the DSR will be migrated to sDAI before activation
        uint256 daiClearinghouseV1Debt;
        uint256 daiClearinghouseV1_1Debt;
        {
            ERC20 daiToken = ERC20(dai);
            uint256 daiTotalDebt = trsryModule.totalDebt(daiToken);
            console2.log("Total DAI debt: %s", daiTotalDebt);

            daiClearinghouseV1Debt = trsryModule.reserveDebt(daiToken, clearinghouseV1);
            console2.log("ClearinghouseV1 DAI debt: %s", daiClearinghouseV1Debt);

            daiClearinghouseV1_1Debt = trsryModule.reserveDebt(daiToken, clearinghouseV1_1);
            console2.log("ClearinghouseV1_1 DAI debt: %s", daiClearinghouseV1_1Debt);

            uint256 dsrAllocatorDebt = trsryModule.reserveDebt(daiToken, dsrAllocator);
            // TODO add assertion that this is 0, post-sDAI migration
            console2.log("DSRAllocator DAI debt: %s", dsrAllocatorDebt);

            assertEq(
                daiTotalDebt,
                daiClearinghouseV1Debt + daiClearinghouseV1_1Debt + dsrAllocatorDebt,
                "Clearinghouse DAI debt should equal total debt"
            );
        }

        // sDAI
        {
            ERC20 sdaiToken = ERC20(sdai);
            uint256 sdaiTotalDebt = trsryModule.totalDebt(sdaiToken);
            assertEq(sdaiTotalDebt, 0, "sDAI debt should be 0");
        }

        // FXS
        {
            ERC20 fxsToken = ERC20(fxs);
            uint256 fxsTotalDebt = trsryModule.totalDebt(fxsToken);
            assertEq(fxsTotalDebt, 0, "FXS debt should be 0");
        }

        // veFXS is in an allocator, have no balance in the current treasury, but also don't have any debt value set
        uint256 vefxsBalance;
        {
            IFXSAllocator vefxsAllocatorContract = IFXSAllocator(vefxsallocator);
            ERC20 vefxsToken = ERC20(vefxs);
            vefxsBalance = vefxsAllocatorContract.totalAmountDeployed();

            uint256 vefxsTotalDebt = trsryModule.totalDebt(vefxsToken);
            assertEq(vefxsTotalDebt, 0, "FXS debt should be 0");
        }

        // 3. Upgrade the OlympusTreasury contract to the new version
        {
            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.UpgradeModule,
                    newTrsry
                )
            );
            console2.log("Upgraded OlympusTreasury to new version: %s", newTrsry);
        }

        // 4. Transfer debt over to the new treasury
        // TreasuryCustodian.increaseDebt can be used as the existing debt is 0

        // DAI
        {
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
            ERC20 vefxsToken = ERC20(vefxs);
            addToBatch(
                treasuryCustodian,
                abi.encodeWithSelector(
                    TreasuryCustodian.increaseDebt.selector,
                    vefxsToken,
                    vefxsallocator,
                    vefxsBalance
                )
            );
        }

        // It would be ideal to register TRSRY assets here, however the BookKeeper policy is required for that
    }
}
