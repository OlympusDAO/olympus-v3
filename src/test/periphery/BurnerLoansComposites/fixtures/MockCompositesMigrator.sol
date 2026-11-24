// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract MockCompositesMigrator {
    MockERC20 public immutable dai;
    MockERC20 public immutable usds;
    uint256 internal _outputShortfall;

    constructor(MockERC20 dai_, MockERC20 usds_) {
        dai = dai_;
        usds = usds_;
    }

    function setOutputShortfall(uint256 shortfall_) external {
        _outputShortfall = shortfall_;
    }

    function daiToUsds(address recipient_, uint256 amount_) external {
        dai.burnFrom(msg.sender, amount_);
        usds.mint(recipient_, amount_ - _outputShortfall);
    }

    function usdsToDai(address recipient_, uint256 amount_) external {
        usds.burnFrom(msg.sender, amount_);
        dai.mint(recipient_, amount_);
    }
}
