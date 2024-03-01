// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IPOLY, IGenesisClaim} from "policies/interfaces/IPOLY.sol";

contract MockGenesisClaim is IGenesisClaim {
    mapping(address => IPOLY.GenesisTerm) public accountTerms;

    constructor() {}

    function setTerms(
        address account_,
        uint256 percent_,
        uint256 claimed_,
        uint256 gClaimed_,
        uint256 max_
    ) external {
        accountTerms[account_] = IPOLY.GenesisTerm(percent_, claimed_, gClaimed_, max_);
    }

    function terms(address account_) external view returns (IPOLY.GenesisTerm memory) {
        return accountTerms[account_];
    }
}