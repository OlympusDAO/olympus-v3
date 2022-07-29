// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import { OlympusAuthority } from "modules/AUTHR.sol";
import { Kernel, Policy } from "src/Kernel.sol";

/**
 * @notice Mock policy to give authorizations to address for testing
 */
contract MockAuthGiver is Policy {
    OlympusAuthority internal AUTHR;

    constructor(Kernel kernel_) Policy(kernel_) {}

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureReads() external override {
        AUTHR = OlympusAuthority(getModuleAddress("AUTHR"));
    }

    function requestRoles() external view override returns (Role[] memory roles) {
        roles = new Role[](1);
        roles[0] = AUTHR.ADMIN();
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
