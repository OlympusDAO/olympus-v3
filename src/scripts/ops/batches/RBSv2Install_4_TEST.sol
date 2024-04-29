// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Scripts
import {RBSv2Install_1_TRSRY} from "src/scripts/ops/batches/RBSv2Install_1_TRSRY.sol";
import {RBSv2Install_2_SPPLY} from "src/scripts/ops/batches/RBSv2Install_2_SPPLY.sol";
import {RBSv2Install_3_RBS} from "src/scripts/ops/batches/RBSv2Install_3_RBS.sol";

import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";
import {MigrationOffsetSupply} from "modules/SPPLY/submodules/MigrationOffsetSupply.sol";
import {BrickedSupply} from "modules/SPPLY/submodules/BrickedSupply.sol";

import {toCategory as toSupplyCategory, SPPLYv1} from "modules/SPPLY/SPPLY.v1.sol";

// Bophades policies
import {OlympusHeart} from "policies/RBS/Heart.sol";
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";

/// @notice     This is a batch script for RBSv2 that combines the three steps (TRSRY, SPPLY, RBS)
/// @notice     into one batch script for testing purposes.
contract RBSv2Install_4_TEST is OlyBatch {
    address heartV2;
    address appraiser;
    address spply;
    address migrationOffsetSupply;
    address brickedSupply;

    function loadEnv() internal override {
        heartV2 = envAddress("current", "olympus.policies.OlympusHeartV2");
        appraiser = envAddress("current", "olympus.policies.Appraiser");
        spply = envAddress("current", "olympus.modules.OlympusSupply");
        migrationOffsetSupply = envAddress(
            "current",
            "olympus.submodules.SPPLY.MigrationOffsetSupply"
        );
        brickedSupply = envAddress("current", "olympus.submodules.SPPLY.BrickedSupply");
    }

    function RBSv2Install_4(bool send_) external isDaoBatch(send_) {
        RBSv2Install_1_TRSRY trsryScript = new RBSv2Install_1_TRSRY();
        trsryScript.initTestBatch();
        trsryScript.withdrawAllAssets();
        trsryScript.setupTreasury();
        trsryScript.deposit();

        RBSv2Install_2_SPPLY spplyScript = new RBSv2Install_2_SPPLY();
        spplyScript.initTestBatch();
        spplyScript.disable_crosschainbridge();
        spplyScript.install();

        RBSv2Install_3_RBS rbsScript = new RBSv2Install_3_RBS();
        rbsScript.initTestBatch();
        rbsScript.install();

        console2.log("\n");
        console2.log("*** Additional testing");

        {
            console2.log("Testing supply metrics");
            console2.log(
                "    Total supply",
                OlympusSupply(spply).getMetric(SPPLYv1.Metric.TOTAL_SUPPLY)
            );
            console2.log(
                "    Migration offset",
                MigrationOffsetSupply(migrationOffsetSupply).getProtocolOwnedTreasuryOhm()
            );
            console2.log(
                "    Bricked OHM",
                BrickedSupply(brickedSupply).getProtocolOwnedTreasuryOhm()
            );
            console2.log(
                "    Minus: protocol-owned-treasury",
                OlympusSupply(spply).getSupplyByCategory(
                    toSupplyCategory("protocol-owned-treasury")
                )
            );
            console2.log(
                "    Minus: dao",
                OlympusSupply(spply).getSupplyByCategory(toSupplyCategory("dao"))
            );
            console2.log(
                "    Circulating supply",
                OlympusSupply(spply).getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY)
            );
            console2.log(
                "    Minus: protocol-owned-liquidity",
                OlympusSupply(spply).getSupplyByCategory(
                    toSupplyCategory("protocol-owned-liquidity")
                )
            );
            console2.log(
                "    Minus: protocol-owned-borrowable",
                OlympusSupply(spply).getSupplyByCategory(
                    toSupplyCategory("protocol-owned-borrowable")
                )
            );
            console2.log(
                "    Floating supply",
                OlympusSupply(spply).getMetric(SPPLYv1.Metric.FLOATING_SUPPLY)
            );
            console2.log(
                "    Backed supply",
                OlympusSupply(spply).getMetric(SPPLYv1.Metric.BACKED_SUPPLY)
            );
        }

        // Warp forward to beyond the next heartbeat and test the output again
        // This catches any issues with MA storage
        {
            uint48 warpBlock = uint48(block.timestamp + OlympusHeart(heartV2).frequency() + 1);
            console2.log("Warping forward to block %s", warpBlock);
            vm.warp(warpBlock);

            console2.log("Triggering heartbeat");
            OlympusHeart(heartV2).beat();

            console2.log(
                "    Backing (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.BACKING)
            );
            console2.log(
                "    Liquid backing (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.LIQUID_BACKING)
            );
            console2.log(
                "    LBBO (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM)
            );
        }
    }
}
