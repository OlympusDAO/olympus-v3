// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {RangeSim, SimIO} from "test/lib/sim/RangeSim.sol";

contract Seed{SEED}Test is RangeSim {

    function SEED() internal pure override returns (uint32) {
        return {SEED};
    }

    function KEYS() internal pure override returns (uint32) {
        return {KEYS};
    }

    function EPOCHS() internal pure override returns (uint32) {
        return {EPOCHS};
    }

    function EPOCH_DURATION() internal pure override returns (uint32) {
        return {EPOCH_DURATION};
    }