// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";

contract MockBurnerLoansPolicy is Policy {
    address internal immutable _OHM;

    constructor(Kernel kernel_, address ohm_) Policy(kernel_) {
        _OHM = ohm_;
    }

    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansLifecycle).interfaceId ||
            interfaceId_ == type(IBurnerLoansView).interfaceId;
    }

    function inventory() external pure returns (address) {
        return address(0);
    }

    function ohm() external view returns (address) {
        return _OHM;
    }
}
