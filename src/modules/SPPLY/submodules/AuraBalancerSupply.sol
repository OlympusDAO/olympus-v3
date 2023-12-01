// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Balancer
import {IBalancerPool} from "src/external/balancer/interfaces/IBalancerPool.sol";
import {IVault} from "src/libraries/Balancer/interfaces/IVault.sol";
import {IAuraRewardPool} from "src/external/aura/interfaces/IAuraRewardPool.sol";
import {VaultReentrancyLib} from "src/libraries/Balancer/contracts/VaultReentrancyLib.sol";

// Bophades Modules
import "modules/SPPLY/SPPLY.v1.sol";

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

    /// @notice         Struct that represents a Balancer/Aura pool pair
    struct Pool {
        /// @notice     Balancer pool
        IBalancerPool balancerPool;
        /// @notice     Aura pool. Optional.
        IAuraRewardPool auraPool;
    }

    /// @notice     Address of the POL manager.
    address public immutable polManager;

    /// @notice     Address of the OHM token. Cached at contract creation.
    address internal immutable ohm;

    /// @notice     Address of the Balancer Vault. Cached at contract creation.
    IVault public immutable balVault;

    /// @notice     Array of Balancer/Aura pool pairs.
    /// @dev        The pools can be added and removed using the `addPool()` and `removePool()` functions.
    Pool[] public pools;

    // ========== CONSTRUCTOR ========== //

    /// @notice             Constructor for the AuraBalancerSupply submodule
    /// @dev                Will revert if:
    /// @dev                - The `polManager_` address is 0
    /// @dev                - The `balVault_` address is 0
    /// @dev                - There is an invalid entry in the `pools_` array (see `addPool()`)
    /// @dev                - Calling the `Submodule` constructor fails
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
    ///
    /// @dev        This function accesses the reserves of the monitored pools.
    /// @dev        In order to protect against re-entrancy attacks,
    /// @dev        it utilises the Balancer VaultReentrancyLib.
    function getProtocolOwnedLiquidityOhm() external view override returns (uint256) {
        // Prevent re-entrancy attacks
        VaultReentrancyLib.ensureNotInVaultContext(balVault);

        // Iterate through the pools and get the POL supply from each
        uint256 supply;
        uint256 len = pools.length;
        for (uint256 i; i < len; ) {
            SPPLYv1.Reserves memory reserve = _getReserves(pools[i]);

            // Iterate over the tokens and add the OHM balance to the total POL supply
            uint256 tokenLen = reserve.tokens.length;
            for (uint256 j; j < tokenLen; ) {
                if (reserve.tokens[j] == ohm) {
                    supply += reserve.balances[j];
                    break;
                }
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        return supply;
    }

    /// @inheritdoc SupplySubmodule
    function getProtocolOwnedTreasuryOhm() external pure override returns (uint256) {
        // POTO is always zero for liquidity pools
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        This function accesses the reserves of the monitored pools.
    /// @dev        In order to protect against re-entrancy attacks,
    /// @dev        it utilises the Balancer VaultReentrancyLib.
    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        // Prevent re-entrancy attacks
        VaultReentrancyLib.ensureNotInVaultContext(balVault);

        // Iterate through tokens and add the reserves of each pool
        uint256 len = pools.length;
        SPPLYv1.Reserves[] memory reserves = new SPPLYv1.Reserves[](len);
        for (uint256 i; i < len; ) {
            SPPLYv1.Reserves memory reserve = _getReserves(pools[i]);
            reserves[i] = reserve;

            unchecked {
                ++i;
            }
        }

        return reserves;
    }

    /// @inheritdoc SupplySubmodule
    function getSourceCount() external view override returns (uint256) {
        return pools.length;
    }

    /// @notice Get the list of configured pools
    /// @return Array of Balancer/Aura pool pairs
    function getPools() external view returns (Pool[] memory) {
        return pools;
    }

    // =========== ADMIN FUNCTIONS =========== //

    /// @notice                 Add a Balancer/Aura Pool pair to the list of pools
    /// @dev                    Will revert if:
    /// @dev                    - The `balancerPool_` address is 0
    /// @dev                    - The `balancerPool_` address is already added
    /// @dev                    - The `balancerPool_` address is not the asset of the specified Aura pool
    /// @dev                    - The caller is not the parent module
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
        if (address(auraPool_) != address(0) && balancerPool_ != IAuraRewardPool(auraPool_).asset())
            revert AuraBalSupply_PoolMismatch();

        // Add the pool to the array
        pools.push(
            Pool({balancerPool: IBalancerPool(balancerPool_), auraPool: IAuraRewardPool(auraPool_)})
        );

        emit PoolAdded(balancerPool_, auraPool_);
    }

    /// @notice                 Remove a Balancer/Aura Pool pair from the list of pools
    /// @dev                    Will revert if:
    /// @dev                    - The `balancerPool_` address is 0
    /// @dev                    - The `balancerPool_` address is not already added
    /// @dev                    - The caller is not the parent module
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

    // =========== HELPER FUNCTIONS =========== //

    /// @notice     Determines if `balancerPool_` is contained in the `pools` array
    ///
    /// @param      balancerPool_ Address of the Balancer pool
    /// @return     True if the pool is present, false otherwise
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

    /// @notice         Get the reserves of a Balancer/Aura pool pair
    /// @dev            The calling function is responsible for protecting against re-entrancy.
    ///
    /// @param pool     Balancer/Aura pool pair
    /// @return         Reserves of the pool
    function _getReserves(Pool storage pool) internal view returns (SPPLYv1.Reserves memory) {
        // Get the balancer pool token balance of the manager
        uint256 balBalance = pool.balancerPool.balanceOf(polManager);
        // If an aura pool is defined, get the underlying balance and add to the balancer pool balance before adding to the total POL supply
        // We don't have to do a ERC4626 shares to assets conversion because aura pools are all 1:1 with balancer pool balances
        if (address(pool.auraPool) != address(0)) balBalance += pool.auraPool.balanceOf(polManager);

        // Get the pool tokens and total balances of the pool
        (address[] memory _vaultTokens, uint256[] memory _vaultBalances, ) = balVault.getPoolTokens(
            pool.balancerPool.getPoolId()
        );

        // Get the total supply of the balancer pool
        uint256 balTotalSupply = pool.balancerPool.totalSupply();
        uint256[] memory balances = new uint256[](_vaultTokens.length);
        // Calculate the proportion of the pool balances owned by the polManager
        if (balTotalSupply != 0) {
            // Calculate the amount of OHM in the pool owned by the polManager
            // We have to iterate through the tokens array to find the index of OHM
            uint256 tokenLen = _vaultTokens.length;
            for (uint256 i; i < tokenLen; ) {
                uint256 balance = _vaultBalances[i];
                uint256 polBalance = (balance * balBalance) / balTotalSupply;

                balances[i] = polBalance;

                unchecked {
                    ++i;
                }
            }
        }

        SPPLYv1.Reserves memory reserves;
        reserves.source = address(pool.balancerPool);
        reserves.tokens = _vaultTokens;
        reserves.balances = balances;
        return reserves;
    }
}
