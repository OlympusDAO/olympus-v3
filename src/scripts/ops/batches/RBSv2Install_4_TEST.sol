// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Scripts
import {RBSv2Install_1_TRSRY} from "src/scripts/ops/batches/RBSv2Install_1_TRSRY.sol";
import {RBSv2Install_2_SPPLY} from "src/scripts/ops/batches/RBSv2Install_2_SPPLY.sol";
import {RBSv2Install_3_RBS} from "src/scripts/ops/batches/RBSv2Install_3_RBS.sol";

// Bophades policies
import {OlympusHeart} from "policies/RBS/Heart.sol";
import {Appraiser} from "policies/OCA/Appraiser.sol";
import {IAppraiser} from "policies/OCA/interfaces/IAppraiser.sol";

/// @notice     This is a batch script for RBSv2 that combines the three steps (TRSRY, SPPLY, RBS)
/// @notice     into one batch script for testing purposes.
contract RBSv2Install_4_TEST is OlyBatch {
    address heartV2;
    address appraiser;

    function loadEnv() internal override {
        heartV2 = envAddress("current", "olympus.policies.OlympusHeartV2");
        appraiser = envAddress("current", "olympus.policies.Appraiser");
    }

    function RBSv2Install_4(bool send_) external isDaoBatch(send_) {
        RBSv2Install_1_TRSRY trsry = new RBSv2Install_1_TRSRY();
        trsry.initTestBatch();
        trsry.install();

        RBSv2Install_2_SPPLY spply = new RBSv2Install_2_SPPLY();
        spply.initTestBatch();
        spply.install();

        RBSv2Install_3_RBS rbs = new RBSv2Install_3_RBS();
        rbs.initTestBatch();
        rbs.install();

        console2.log("\n");
        console2.log("*** Additional testing");

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
                "    LBBO (18dp)",
                Appraiser(appraiser).getMetric(IAppraiser.Metric.LIQUID_BACKING_PER_BACKED_OHM)
            );
        }
    }
}
