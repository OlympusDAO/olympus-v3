// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEmissionManager} from "src/policies/interfaces/IEmissionManager.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

contract MockEmissionManager is IEmissionManager, IPeriodicTask {
    uint256 public count;
    bool internal _revert;

    error MockEmissionManager_Revert();

    constructor() {}

    function execute() external override {
        if (_revert) revert MockEmissionManager_Revert();

        count++;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IEmissionManager).interfaceId ||
            interfaceId == type(IPeriodicTask).interfaceId;
    }
}
