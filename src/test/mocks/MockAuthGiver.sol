// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {OlympusAuthority} from "modules/AUTHR.sol";
import {Kernel, Policy} from "../../Kernel.sol";

/**
 * @notice Mock policy to give authorizations to address for testing
 */
contract MockAuthGiver is Policy {
    OlympusAuthority internal AUTHR;

    constructor(Kernel kernel_) Policy(kernel_) {}

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureReads() external override onlyKernel {
        AUTHR = OlympusAuthority(getModuleAddress("AUTHR"));
    }

    function requestWrites()
        external
        view
        override
        onlyKernel
        returns (bytes5[] memory permissions)
    {
        permissions = new bytes5[](1);
        permissions[0] = "AUTHR";
    }

    /* ========== USER FUNCTIONS ========== */
    function setUserRole(address user_, uint8 role_) external {
        AUTHR.setUserRole(user_, role_, true);
    }

    function setRoleCapability(
        uint8 role_,
        address target_,
        bytes4 functionSig_
    ) external {
        AUTHR.setRoleCapability(role_, target_, functionSig_, true);
    }
}
