// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {LQREGv1} from "src/modules/LQREG/LQREG.v1.sol";
import "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

/// @title  Olympus Liquidity Vault Registry
/// @notice Olympus Liquidity Vault Registry (Module) Contract
/// @dev    The Olympus Liquidity Vault Registry Module tracks the single-sided liquidity vaults
///         that are approved to be used by the Olympus protocol. This allows for a single-soure
///         of truth for reporting purposes around total OHM deployed and net emissions.
contract OlympusLiquidityRegistry is LQREGv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Module(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("LQREG");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc LQREGv1
    function addVault(address vault_) external override permissioned {
        activeVaults.push(vault_);
        ++activeVaultCount;

        emit VaultAdded(vault_);
    }

    /// @inheritdoc LQREGv1
    function removeVault(uint256 index_, address vault_) external override permissioned {
        // Sanity check that the vault at index_ is the same as vault_
        if (activeVaults[index_] != vault_) revert LQREG_RemovalMismatch();

        // Delete vault from array by swapping with last element and popping
        activeVaults[index_] = activeVaults[activeVaults.length - 1];
        activeVaults.pop();
        --activeVaultCount;

        emit VaultRemoved(vault_);
    }
}
