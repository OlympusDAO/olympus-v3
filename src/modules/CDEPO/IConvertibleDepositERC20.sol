// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDeposit} from "./IConvertibleDeposit.sol";

/// @title IConvertibleDepositERC20
/// @notice Defines an interface for a convertible deposit token that is an ERC20.
interface IConvertibleDepositERC20 is IERC20, IConvertibleDeposit {

}
