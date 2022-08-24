// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {RangeSim, SimIO} from "test/sim/RangeSim.sol";

contract Seed253Test is RangeSim {

    function SEED() internal pure override returns (uint32) {
        return 253;
    }

    function test_Seed_253_Key_0() public {
        simulate(0);
    }

}
