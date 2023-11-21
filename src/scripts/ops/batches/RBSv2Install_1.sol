// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";

contract RBSv2Install_1 is OlyBatch {
    // Existing Olympus contracts
    address kernel;
    address trsry;
    address treasuryCustodian;

    // Tokens
    address sdai;
    address lusd;
    address wsteth;
    address bal;
    address aura;

    // New contracts
    address new_trsry;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        trsry = envAddress("last", "olympus.modules.OlympusTreasury");
        treasuryCustodian = envAddress("current", "olympus.policies.TreasuryCustodian");

        sdai = envAddress("current", "external.tokens.sDAI");
        lusd = envAddress("current", "external.tokens.LUSD");
        wsteth = envAddress("current", "external.tokens.wstETH");
        bal = envAddress("current", "external.tokens.BAL");
        aura = envAddress("current", "external.tokens.AURA");

        new_trsry = envAddress("current", "olympus.modules.OlympusTreasury");
    }

    function RBSv2Install_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Transfers all tokens from the old treasury to the new treasury
        // 2. Upgrades the OlympusTreasury contract to the new version

        // 1. Transfer all tokens from the old treasury to the new treasury
        uint256 sdaiBalance = ERC20(sdai).balanceOf(trsry);
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, sdai, sdaiBalance));
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, new_trsry, sdai, sdaiBalance));

        uint256 lusdBalance = ERC20(lusd).balanceOf(trsry);
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, lusd, lusdBalance));
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, new_trsry, lusd, lusdBalance));

        uint256 wstethBalance = ERC20(wsteth).balanceOf(trsry);
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, wsteth, wstethBalance));
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, new_trsry, wsteth, wstethBalance));

        uint256 balBalance = ERC20(bal).balanceOf(trsry);
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, bal, balBalance));
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, new_trsry, bal, balBalance));

        uint256 auraBalance = ERC20(aura).balanceOf(trsry);
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.grantWithdrawerApproval.selector, treasuryCustodian, aura, auraBalance));
        addToBatch(treasuryCustodian, abi.encodeWithSelector(TreasuryCustodian.withdrawReservesTo.selector, new_trsry, aura, auraBalance));

        // 2. Upgrade the OlympusTreasury contract to the new version
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.UpgradeModule, new_trsry));
    }
}
