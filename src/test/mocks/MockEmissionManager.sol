// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEmissionManager} from "../../policies/interfaces/IEmissionManager.sol";

contract MockEmissionManager is IEmissionManager {
    uint256 internal _premium;
    uint256 internal _minimumPremium;

    constructor() {}

    function execute() external override {
        // do nothing
    }

    function getPremium() external view returns (uint256) {
        return _premium;
    }
    function minimumPremium() external view returns (uint256) {
        return _minimumPremium;
    }

    function setPremium(uint256 premium_) external {
        _premium = premium_;
    }

    function setMinimumPremium(uint256 minimumPremium_) external {
        _minimumPremium = minimumPremium_;
    }
}
