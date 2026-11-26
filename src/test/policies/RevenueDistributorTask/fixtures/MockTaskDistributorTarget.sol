// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

contract MockTaskDistributorTarget is Policy, IERC165 {
    bool internal immutable _SUPPORTS_DISTRIBUTOR;
    bool internal immutable _SUPPORTS_ENABLER;
    bool public isEnabled;

    constructor(Kernel kernel_, bool supportsDistributor_, bool supportsEnabler_) Policy(kernel_) {
        _SUPPORTS_DISTRIBUTOR = supportsDistributor_;
        _SUPPORTS_ENABLER = supportsEnabler_;
    }

    function setEnabled(bool enabled_) external {
        isEnabled = enabled_;
    }

    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](0);
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    function supportsInterface(bytes4 interfaceId_) external view returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            (_SUPPORTS_DISTRIBUTOR && interfaceId_ == type(IRevenueDistributor).interfaceId) ||
            (_SUPPORTS_ENABLER && interfaceId_ == type(IEnabler).interfaceId);
    }
}
