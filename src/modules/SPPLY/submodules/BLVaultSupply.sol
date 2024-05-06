// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";
import {VaultReentrancyLib} from "src/libraries/Balancer/contracts/VaultReentrancyLib.sol";
import {IVault} from "src/libraries/Balancer/interfaces/IVault.sol";

interface IBLVaultManager {
    function getPoolOhmShare() external view returns (uint256);
}

/// @title      BLVaultSupply
/// @author     Oighty
/// @notice     A SPPLY submodule that provides data on OHM deployed into the specified BLVaults
/// @dev        The pools underlying BLV are open to reserves manipulation, which can in turn affect this submodule's data.
///             The issue is not being fixed, as BLV is discontinued and the submodule will not be deployed.
///             In case BLV is re-activated, the issue would need to be addressed: https://github.com/OlympusDAO/bophades/issues/316
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

    /// @notice     Emitted when a BLVaultManager is added to the list of managers
    event VaultManagerAdded(address vaultManager_);

    /// @notice     Emitted when a BLVaultManager is removed from the list of managers
    event VaultManagerRemoved(address vaultManager_);

    // ========== STATE VARIABLES ========== //

    /// @notice     The addresses of the BLVaultManager contracts
    IBLVaultManager[] public vaultManagers;

    /// @notice     The Balancer vault
    IVault public balVault;

    // ========== CONSTRUCTOR ========== //

    /// @notice                 Initialize the BLVaultSupply submodule
    ///
    /// @param parent_          The parent module (SPPLY)
    /// @param vaultManagers_   The addresses of the BLVaultManager contracts
    constructor(
        Module parent_,
        address balVault_,
        address[] memory vaultManagers_
    ) Submodule(parent_) {
        balVault = IVault(balVault_);

        uint256 len = vaultManagers_.length;

        for (uint256 i = 0; i < len; i++) {
            address vaultManager = vaultManagers_[i];

            if (vaultManager == address(0) || _inArray(vaultManager))
                revert BLVaultSupply_InvalidParams();

            vaultManagers.push(IBLVaultManager(vaultManager));

            emit VaultManagerAdded(vaultManager);
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
    /// @dev        All OHM in the BLVault is collateralized, since it is paired with the user's collateral
    ///
    /// @dev        As this function accesses `getPoolOhmShare()` on each BLVaultManager, it is susceptible to
    /// @dev        reentrancy attacks. The Balancer VaultReentrancyLib is used to mitigate this.
    function getCollateralizedOhm() external view override returns (uint256) {
        // Prevent re-entrancy attacks
        VaultReentrancyLib.ensureNotInVaultContext(balVault);

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

    /// @inheritdoc SupplySubmodule
    function getProtocolOwnedTreasuryOhm() external pure override returns (uint256) {
        // POTO is always zero for BLVaults
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Protocol-owned liquidity OHM is always zero for BLVaults.
    ///
    ///             This function returns an array with the same length as `getSourceCount()`, but with empty values.
    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        uint256 len = vaultManagers.length;
        SPPLYv1.Reserves[] memory reserves = new SPPLYv1.Reserves[](len);
        for (uint256 i; i < len; ) {
            reserves[i] = SPPLYv1.Reserves({
                source: address(vaultManagers[i]),
                tokens: new address[](0),
                balances: new uint256[](0)
            });

            unchecked {
                ++i;
            }
        }

        return reserves;
    }

    /// @inheritdoc SupplySubmodule
    function getSourceCount() external view override returns (uint256) {
        return vaultManagers.length;
    }

    /// @inheritdoc SupplySubmodule
    function storeObservations() external virtual override onlyParent {
        // Do nothing
    }

    // =========== ADMIN FUNCTIONS =========== //

    /// @notice                 Add a BLVaultManager to the list of managers
    /// @dev                    Reverts if:
    /// @dev                    - The address is the zero address
    /// @dev                    - The address is already in the list
    /// @dev                    - The caller is not the parent module
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
    /// @dev                    - The address is the zero address
    /// @dev                    - The address is not in the list
    /// @dev                    - The caller is not the parent module
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

    /// @notice             Set the Balancer vault
    /// @dev                Reverts if:
    /// @dev                - The caller is not the parent module
    /// @dev                - The address is the zero address
    ///
    /// @param balVault_    The address of the Balancer vault
    function setBalancerVault(address balVault_) external onlyParent {
        if (balVault_ == address(0)) revert BLVaultSupply_InvalidParams();

        balVault = IVault(balVault_);
    }

    // =========== HELPER FUNCTIONS =========== //

    /// @notice     Determines if `vaultManager_` is contained in the `vaultManagers` array
    ///
    /// @param      vaultManager_  The address of a vault manager
    /// @return     True if the address is in the array, false otherwise
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
