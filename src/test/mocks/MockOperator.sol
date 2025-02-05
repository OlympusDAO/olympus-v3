// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Kernel, Policy, Keycode, Permissions} from "src/Kernel.sol";

/**
 * @notice Mock Operator to test Heart
 */
contract MockOperator is Policy {
    bool public result;
    address public ohm;
    error Operator_CustomError();

    constructor(Kernel kernel_, address ohm_) Policy(kernel_) {
        result = true;
        ohm = ohm_;
    }

    // =========  FRAMEWORK CONFIFURATION ========= //
    function configureDependencies() external override returns (Keycode[] memory dependencies) {}

    function requestPermissions() external view override returns (Permissions[] memory requests) {}

    // =========  HEART FUNCTIONS ========= //
    function operate() external view {
        if (!result) revert Operator_CustomError();
    }

    function setResult(bool result_) external {
        result = result_;
    }
}
