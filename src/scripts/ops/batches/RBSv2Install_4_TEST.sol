// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Scripts
import {RBSv2Install_1_TRSRY} from "src/scripts/ops/batches/RBSv2Install_1_TRSRY.sol";
import {RBSv2Install_2_SPPLY} from "src/scripts/ops/batches/RBSv2Install_2_SPPLY.sol";
import {RBSv2Install_3_RBS} from "src/scripts/ops/batches/RBSv2Install_3_RBS.sol";

/// @notice     This is a batch script for RBSv2 that combines the three steps (TRSRY, SPPLY, RBS)
/// @notice     into one batch script for testing purposes.
contract RBSv2Install_4_TEST is OlyBatch {
    function loadEnv() internal override {
        //
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
    }
}
