// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IYieldRepo} from "../../policies/interfaces/IYieldRepo.sol";

contract MockYieldRepo is IYieldRepo {
    uint48 public epoch;
    bool public isShutdown;

    function endEpoch() external override {
        // do nothing
    }

    function shutdown() external {
        isShutdown = true;
    }

    function getReserveBalance() external view override returns (uint256) {
        return 0;
    }

    function getNextYield() external view override returns (uint256) {
        return 0;
    }
}
