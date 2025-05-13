// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

contract MockCCIPRouter {
    address public onRamp;
    address public offRamp;

    function getOnRamp(uint64) external view returns (address) {
        return onRamp;
    }

    function setOnRamp(address onRamp_) external {
        onRamp = onRamp_;
    }

    function isOffRamp(uint64, address offRamp_) external view returns (bool) {
        return offRamp == offRamp_;
    }

    function setOffRamp(address offRamp_) external {
        offRamp = offRamp_;
    }
}
