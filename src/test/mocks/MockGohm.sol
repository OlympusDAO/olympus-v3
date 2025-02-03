// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

interface IDelegate {
    function delegate(address) external;
    function delegates(address) external view returns (address);
}

contract MockGohm is MockERC20, IDelegate {
    uint256 public constant index = 10000;
    
    mapping(address => address) public override delegates;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) MockERC20(name_, symbol_, decimals_) {}

    function delegate(address delegatee_) public {
        delegates[msg.sender] = delegatee_;
    }

    function balanceFrom(uint256 amount_) public view returns (uint256) {
        return (amount_ * index) / 10 ** decimals;
    }

    function balanceTo(uint256 amount_) public view returns (uint256) {
        return (amount_ * 10 ** decimals) / index;
    }
}
