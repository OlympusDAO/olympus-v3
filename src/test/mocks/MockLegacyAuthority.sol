// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IOlympusAuthority} from "src/external/OlympusERC20.sol";

contract MockLegacyAuthority is IOlympusAuthority {
    address internal kernel;

    constructor(address kernel_) {
        kernel = kernel_;
    }

    function governor() external view returns (address) {
        return kernel;
    }

    function guardian() external view returns (address) {
        return kernel;
    }

    function policy() external view returns (address) {
        return kernel;
    }

    function vault() external view returns (address) {
        return kernel;
    }
}

contract MockLegacyAuthorityV2 is IOlympusAuthority {
    address internal governorAddr;
    address internal guardianAddr;
    address internal policyAddr;
    address internal vaultAddr;

    constructor(
        address governor_,
        address guardian_,
        address policy_,
        address vault_
    ) {
        governorAddr = governor_;
        guardianAddr = guardian_;
        policyAddr = policy_;
        vaultAddr = vault_;
    }

    function governor() external view returns (address) {
        return governorAddr;
    }

    function guardian() external view returns (address) {
        return guardianAddr;
    }

    function policy() external view returns (address) {
        return policyAddr;
    }

    function vault() external view returns (address) {
        return vaultAddr;
    }

    function setVault(address newVault_) external {
        vaultAddr = newVault_;
    }
}
