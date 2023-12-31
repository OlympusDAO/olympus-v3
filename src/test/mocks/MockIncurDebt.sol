// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {IIncurDebt} from "src/modules/SPPLY/submodules/IncurDebtSupply.sol";

contract MockIncurDebt is IIncurDebt {
    uint256 public totalDebt;

    constructor(uint256 totalDebt_) {
        totalDebt = totalDebt_;
    }

    function totalOutstandingGlobalDebt() external view override returns (uint256) {
        return totalDebt;
    }

    function setTotalDebt(uint256 totalDebt_) external {
        totalDebt = totalDebt_;
    }
}
