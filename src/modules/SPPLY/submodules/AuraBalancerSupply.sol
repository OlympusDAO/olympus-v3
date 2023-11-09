// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";

/// @dev    Interface for the Aura base reward pool
///         Example contract: https://etherscan.io/address/0xB9D6ED734Ccbdd0b9CadFED712Cf8AC6D0917EcD
interface IAuraPool {
    function balanceOf(address account_) external view returns (uint256);

    function asset() external view returns (address);
}

interface IBalancerPool {
    function balanceOf(address account_) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function getPoolId() external view returns (bytes32);
}

interface IVault {
    function getPoolTokens(
        bytes32 poolId
    )
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

/// @title      AuraBalancerSupply
/// @author     Oighty
/// @notice     Calculates the amount of protocol-owned liquidity OHM in Balancer pools, including BPTs staked in Aura
contract AuraBalancerSupply is SupplySubmodule {
    // Requirements
    // [X] Determine the amount of protocol-owned liquidity OHM in Balancer pools, including BPTs staked in Aura
    // Math:
    // Protocol deposits OHM-TKN liquidity into a balancer pool.
    // The protocol may stake the liquidity pool tokens in Aura.
    // Let X be the amount of BPT tokens held by the POL manager.
    // Let Y be the amount of Aura BPT tokens held by the POL manager.
    // Aura BPT tokens are 1:1 with BPT token balances.
    // Then, A = X + Y is the total amount of BPT tokens held by the POL manager.
    // If there are B BPT tokens in circulation, then the protocol owns A/B of the pool.
    // If there are C OHM tokens in the pool, then the protocol owns (A/B) * C of the OHM in the pool.
    // Therefore,
    // Protocol-owned Borrowable OHM = 0
    // Collateralized OHM = 0
    // Protocol-owned Liquidity OHM = (A/B) * C

    // ========== ERRORS ========== //

    /// @notice The Balancer pool and Aura pool have differing assets
    error AuraBalSupply_PoolMismatch();

    /// @notice The parameters provided are invalid. This is usually due to a zero address.
    error AuraBalSupply_InvalidParams();

    /// @notice                 The pool is already added
    /// @param balancerPool     Address of the Balancer pool
    /// @param auraPool         Address of the Aura pool
    error AuraBalSupply_PoolAlreadyAdded(address balancerPool, address auraPool);

    // ========== EVENTS ========== //

    /// @notice             Emitted when a pool is added
    /// @param balancerPool Address of the Balancer pool
    /// @param auraPool     Address of the Aura pool
    event PoolAdded(address balancerPool, address auraPool);

    /// @notice             Emitted when a pool is removed
    /// @param balancerPool Address of the Balancer pool
    /// @param auraPool     Address of the Aura pool
    event PoolRemoved(address balancerPool, address auraPool);

    // ========== STATE VARIABLES ========== //

    struct Pool {
        IBalancerPool balancerPool;
        IAuraPool auraPool;
    }

    address public polManager;
    address internal ohm;
    IVault public balVault;
    Pool[] public pools;

    // ========== CONSTRUCTOR ========== //

    /// @notice             Constructor for the AuraBalancerSupply submodule
    /// @dev                Will revert if:
    ///                     - The `polManager_` address is 0
    ///                     - The `balVault_` address is 0
    ///                     - There is an invalid entry in the `pools_` array (see `addPool()`)
    ///                     - Calling the `Submodule` constructor fails
    ///
    /// @param parent_      Address of the parent contract, the SPPLY module
    /// @param polManager_  Address of the POL manager
    /// @param balVault_    Address of the Balancer vault
    /// @param pools_       Array of Balancer/Aura pool pairs
    constructor(
        Module parent_,
        address polManager_,
        address balVault_,
        Pool[] memory pools_
    ) Submodule(parent_) {
        // Check that the parameters are valid
        if (polManager_ == address(0) || balVault_ == address(0))
            revert AuraBalSupply_InvalidParams();

        polManager = polManager_;
        balVault = IVault(balVault_);
        ohm = address(SPPLYv1(address(parent_)).ohm());

        // Iterate through the pools and add them to the array
        // Check that the aura pool is for the associated balancer pool unless it is blank
        uint256 len = pools_.length;
        for (uint256 i; i < len; i++) {
            // Don't add address 0
            if (address(pools_[i].balancerPool) == address(0)) revert AuraBalSupply_InvalidParams();

            // Balancer pool must be the asset of the Aura pool
            if (
                address(pools_[i].auraPool) != address(0) &&
                address(pools_[i].balancerPool) != pools_[i].auraPool.asset()
            ) {
                revert AuraBalSupply_PoolMismatch();
            }

            // Don't add twice
            if (_inArray(address(pools_[i].balancerPool)))
                revert AuraBalSupply_PoolAlreadyAdded(
                    address(pools_[i].balancerPool),
                    address(pools_[i].auraPool)
                );

            pools.push(pools_[i]);
            emit PoolAdded(address(pools_[i].balancerPool), address(pools_[i].auraPool));
        }
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.AURABALANCER");
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
    /// @dev        Collateralized OHM is always zero for liquidity pools
    function getCollateralizedOhm() external pure override returns (uint256) {
        // Collateralized OHM is zero for liquidity pools (except BLV, which is a different module)
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Protocol-owned borrowable OHM is always zero for liquidity pools
    function getProtocolOwnedBorrowableOhm() external pure override returns (uint256) {
        // POBO is zero for liquidity pools
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Protocol-owned liquidity OHM is calculated as the sum of the protocol-owned OHM in each pool
    function getProtocolOwnedLiquidityOhm() external view override returns (uint256) {
        // Iterate through the pools and get the POL supply from each
        uint256 supply;
        uint256 len = pools.length;
        for (uint256 i; i < len; ) {
            // Get the balancer pool token balance of the manager
            uint256 balBalance = pools[i].balancerPool.balanceOf(polManager);
            // If an aura pool is defined, get the underlying balance and add to the balancer pool balance before adding to the total POL supply
            // We don't have to do a ERC4626 shares to assets conversion because aura pools are all 1:1 with balancer pool balances
            if (address(pools[i].auraPool) != address(0))
                balBalance += pools[i].auraPool.balanceOf(polManager);

            // Get the total supply of the balancer pool
            uint256 balTotalSupply = pools[i].balancerPool.totalSupply();

            // Continue only if total supply is not 0
            if (balTotalSupply != 0) {
                // Get the pool tokens and balances of the pool
                (address[] memory tokens, uint256[] memory balances, ) = balVault.getPoolTokens(
                    pools[i].balancerPool.getPoolId()
                );

                // Calculate the amount of OHM in the pool owned by the polManager
                // We have to iterate through the tokens array to find the index of OHM
                uint256 tokenLen = tokens.length;
                for (uint256 j; j < tokenLen; ) {
                    if (tokens[j] == ohm) {
                        // Get the amount of OHM in the pool
                        uint256 ohmBalance = balances[j];
                        // Calculate the amount of OHM owned by the polManager
                        uint256 polBalance = (ohmBalance * balBalance) / balTotalSupply;
                        // Add the amount of OHM owned by the polManager to the total POL supply
                        supply += polBalance;
                        // Break out of the loop
                        break;
                    }

                    unchecked {
                        ++j;
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        return supply;
    }

    // =========== ADMIN FUNCTIONS =========== //

    /// @notice                 Add a Balancer/Aura Pool pair to the list of pools
    /// @dev                    Will revert if:
    ///                         - The `balancerPool_` address is 0
    ///                         - The `balancerPool_` address is already added
    ///                         - The `balancerPool_` address is not the asset of the specified Aura pool
    ///                         - The caller is not the parent module
    ///
    /// @param balancerPool_    Address of the Balancer pool
    /// @param auraPool_        Address of the Aura pool
    function addPool(address balancerPool_, address auraPool_) external onlyParent {
        // Don't add address 0
        if (balancerPool_ == address(0)) revert AuraBalSupply_InvalidParams();

        // Check that the pool isn't already added
        if (_inArray(balancerPool_))
            revert AuraBalSupply_PoolAlreadyAdded(balancerPool_, auraPool_);

        // Check that the aura pool is for the associated balancer pool unless it is blank
        if (address(auraPool_) != address(0) && balancerPool_ != IAuraPool(auraPool_).asset())
            revert AuraBalSupply_PoolMismatch();

        // Add the pool to the array
        pools.push(
            Pool({balancerPool: IBalancerPool(balancerPool_), auraPool: IAuraPool(auraPool_)})
        );

        emit PoolAdded(balancerPool_, auraPool_);
    }

    /// @notice                 Remove a Balancer/Aura Pool pair from the list of pools
    /// @dev                    Will revert if:
    ///                         - The `balancerPool_` address is 0
    ///                         - The `balancerPool_` address is not already added
    ///                         - The caller is not the parent module
    ///
    /// @param balancerPool_    Address of the Balancer pool
    function removePool(address balancerPool_) external onlyParent {
        // Ignore address 0
        if (balancerPool_ == address(0)) revert AuraBalSupply_InvalidParams();

        // Check that the pool is present
        if (!_inArray(balancerPool_)) revert AuraBalSupply_InvalidParams();

        uint256 len = pools.length;
        for (uint256 i; i < len; ) {
            if (balancerPool_ == address(pools[i].balancerPool)) {
                address auraPool = address(pools[i].auraPool);
                pools[i] = pools[len - 1];
                pools.pop();
                emit PoolRemoved(balancerPool_, auraPool);
                return;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _inArray(address balancerPool_) internal view returns (bool) {
        uint256 len = pools.length;
        for (uint256 i; i < len; ) {
            if (balancerPool_ == address(pools[i].balancerPool)) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Get the list of configured pools
    function getPools() external view returns (Pool[] memory) {
        return pools;
    }
}
