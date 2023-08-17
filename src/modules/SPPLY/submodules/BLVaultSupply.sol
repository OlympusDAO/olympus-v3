// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";

interface IBLVaultManager {
    function getPoolOhmShare() external view returns (uint256);
}

/// @title      BLVaultSupply
/// @author     Oighty
/// @notice     A SPPLY submodule that provides data on OHM deployed into the specified BLVaults
contract BLVaultSupply is SupplySubmodule {
    // Requirements
    // [X] All OHM in the BLVault is circulating supply since it's in an LP pool
    // [X] Get amount of circulating OHM minted against collateral from pool
    // Math:
    // AMO mints X amount of OHM into pool.
    // Y amount is deposited or withdrawn (can be negative).
    // Z amount is OHM in the pool at any given time. Z = X + Y
    // Since it's a LP pool, all of the OHM in the pool is circulating supply.
    // Therefore,
    // Protocol-owned Borrowable OHM = 0
    // Collateralized OHM = Z
    // Protocol-owned Liquidity OHM = 0

    // ========== ERRORS ========== //

    /// @notice     Invalid parameters were passed to a function
    error BLVaultSupply_InvalidParams();

    // ========== EVENTS ========== //

    event VaultManagerAdded(address vaultManager_);

    event VaultManagerRemoved(address vaultManager_);

    // ========== STATE VARIABLES ========== //

    IBLVaultManager[] public vaultManagers;

    // ========== CONSTRUCTOR ========== //

    /// @notice                 Initialize the BLVaultSupply submodule
    /// 
    /// @param parent_          The parent module (SPPLY)
    /// @param vaultManagers_   The addresses of the BLVaultManager contracts
    constructor(Module parent_, address[] memory vaultManagers_) Submodule(parent_) {
        uint256 len = vaultManagers_.length;

        for (uint256 i = 0; i < len; i++) {
            vaultManagers.push(IBLVaultManager(vaultManagers_[i]));

            emit VaultManagerAdded(vaultManagers_[i]);
        }
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.BLV");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========== DATA FUNCTIONS ========== //

    /// @inheritdoc SupplySubmodule
    /// @dev        All OHM in the BLVault is collateralized, since it is paired with the user's collateral.
    function getCollateralizedOhm() external view override returns (uint256) {
        // Iterate through BLVaultManagers and total up the pool OHM share as the collateralized supply
        uint256 len = vaultManagers.length;
        uint256 total;
        for (uint256 i; i < len; ) {
            total += vaultManagers[i].getPoolOhmShare();
            unchecked {
                ++i;
            }
        }

        return total;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Not applicable to BLVaults
    function getProtocolOwnedBorrowableOhm() external pure override returns (uint256) {
        // POBO is always zero for BLVaults
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Not applicable to BLVaults
    function getProtocolOwnedLiquidityOhm() external pure override returns (uint256) {
        // POLO is always zero for BLVaults
        return 0;
    }

    // =========== ADMIN FUNCTIONS =========== //

    /// @notice                 Add a BLVaultManager to the list of managers
    /// @dev                    Reverts if:
    ///                         - The address is the zero address
    ///                         - The address is already in the list
    ///                         - The caller is not the parent module
    ///
    /// @param vaultManager_    The address of the BLVaultManager contract
    function addVaultManager(address vaultManager_) external onlyParent {
        if (vaultManager_ == address(0) || _inArray(vaultManager_))
            revert BLVaultSupply_InvalidParams();
        vaultManagers.push(IBLVaultManager(vaultManager_));

        emit VaultManagerAdded(vaultManager_);
    }

    /// @notice                 Remove a BLVaultManager from the list of managers
    /// @dev                    Reverts if:
    ///                         - The address is the zero address
    ///                         - The address is not in the list
    ///                         - The caller is not the parent module
    ///
    /// @param vaultManager_    The address of the BLVaultManager contract
    function removeVaultManager(address vaultManager_) external onlyParent {
        if (vaultManager_ == address(0) || !_inArray(vaultManager_))
            revert BLVaultSupply_InvalidParams();

        uint256 len = vaultManagers.length;
        for (uint256 i; i < len; ) {
            if (vaultManager_ == address(vaultManagers[i])) {
                vaultManagers[i] = vaultManagers[len - 1];
                vaultManagers.pop();
                emit VaultManagerRemoved(vaultManager_);
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _inArray(address vaultManager_) internal view returns (bool) {
        uint256 len = vaultManagers.length;
        for (uint256 i; i < len; ) {
            if (vaultManager_ == address(vaultManagers[i])) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }
}
