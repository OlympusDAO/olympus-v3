// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// TODO see if there is a standard interface for this

interface IConvertibleDebtToken is IERC20 {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function convertFor(uint256 amount) external view returns (uint256);

    function expiry() external view returns (uint256);

    function totalSupply() external view returns (uint256);
}
