// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {IBLVaultManager} from "src/modules/SPPLY/submodules/BLVaultSupply.sol";

contract MockVaultManager is IBLVaultManager {
    uint256 public poolOhmShare;
    bool public poolOhmShareReverts;

    constructor(uint256 poolOhmShare_) {
        poolOhmShare = poolOhmShare_;
    }

    function setPoolOhmShareReverts(bool reverts_) external {
        poolOhmShareReverts = reverts_;
    }

    function setPoolOhmShare(uint256 poolOhmShare_) external {
        poolOhmShare = poolOhmShare_;
    }

    function getPoolOhmShare() external view override returns (uint256) {
        if (poolOhmShareReverts) revert();

        return poolOhmShare;
    }
}
