// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IOracle} from "src/interfaces/morpho/IOracle.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IOraclePriceCache} from "src/policies/interfaces/price/IOraclePriceCache.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {Clone} from "@clones-with-immutable-args-1.1.2/Clone.sol";
import {String} from "src/libraries/String.sol";

/// @title  MorphoOracleCloneable
/// @author OlympusDAO
/// @notice Oracle adapter that implements Morpho's IOracle interface from cached collateral/loan pair snapshots
/// @dev    Returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36 as required by Morpho's IOracle interface.
///         The price precision is 36 + loan_token_decimals - collateral_token_decimals.
///         This contract is deployed as a clone with immutable args.
contract MorphoOracleCloneable is IMorphoOracle, IOraclePriceCache, Clone {
    using FullMath for uint256;

    // ========== IMMUTABLE ARGS LAYOUT ========== //

    // 0x00: factory address (20 bytes)
    // 0x14: collateral token address (20 bytes)
    // 0x28: loan token address (20 bytes)
    // 0x3C: max age (8 bytes, stored as uint64)
    // 0x44: scale factor (32 bytes)
    // 0x64: name (32 bytes)

    // ========== IMMUTABLE ARGS GETTERS ========== //

    /// @notice The factory address
    /// @dev    Does not revert.
    ///
    /// @return The factory address stored in immutable args
    function factory() public pure returns (IOracleFactory) {
        return IOracleFactory(_getArgAddress(0x00));
    }

    /// @notice The collateral token address
    /// @dev    Does not revert.
    ///
    /// @return address The collateral token address stored in immutable args
    function collateralToken() public pure returns (address) {
        return _getArgAddress(0x14);
    }

    /// @notice The loan token address
    /// @dev    Does not revert.
    ///
    /// @return address The loan token address stored in immutable args
    function loanToken() public pure returns (address) {
        return _getArgAddress(0x28);
    }

    /// @notice The scale factor for the oracle
    /// @dev    Does not revert.
    ///
    /// @return uint256 The scale factor stored in immutable args
    function scaleFactor() public pure returns (uint256) {
        return _getArgUint256(0x44);
    }

    /// @notice The maximum allowed age for cached prices
    /// @dev    Does not revert.
    ///
    /// @return uint48 The max age stored in immutable args
    function maxAge() public pure override returns (uint48) {
        return uint48(_getArgUint64(0x3C));
    }

    /// @notice The name of the oracle
    /// @dev    Does not revert.
    ///
    /// @return string The name stored in immutable args
    function name() public pure returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x64))));
    }

    // ========== MORPHO ORACLE INTERFACE ========== //

    /// @inheritdoc IOracle
    /// @notice     Returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
    /// @dev        This function uses cached pair snapshots only.
    ///
    ///             This function will revert if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled (checked via factory.isOracleEnabled())
    ///             - The collateral/loan pair is invalid for the configured cache policy
    ///             - Either the collateral or loan token cached price is zero
    ///             - The cached timestamp is stale
    ///
    ///             If callers encounter a feed-state revert, they should cache prices then retry.
    ///             A caller can alternatively call `isStale()`, call `cachePrice()` (if the result is true), and then this function.
    function price() external view override returns (uint256) {
        // Check if oracle is enabled via factory
        IOracleFactory factory_ = factory();
        if (!factory_.isOracleEnabled(address(this))) {
            revert MorphoOracle_NotEnabled();
        }

        IPriceCache.CachedPrice memory cachedPrice = IPriceCache(factory_.getPriceCache())
            .getCachedPrice(collateralToken(), loanToken());
        uint48 pairTimestamp = cachedPrice.updatedAt;

        // Price validity is checked separately from staleness so callers can distinguish zero-price cache failures.
        if (cachedPrice.assetPriceUsd == 0 || cachedPrice.quotePriceUsd == 0) {
            revert MorphoOracle_InvalidPrice();
        }

        // Check staleness of the direct collateral/loan pair cache.
        uint48 maxAge_ = maxAge();
        if (_isStaleFromTimestamp(pairTimestamp, maxAge_)) {
            revert MorphoOracle_Stale(pairTimestamp, _latestPermissibleTimestamp(maxAge_));
        }

        return cachedPrice.assetPriceUsd.mulDiv(scaleFactor(), cachedPrice.quotePriceUsd);
    }

    function _isStaleFromTimestamp(uint48 timestamp_, uint48 maxAge_) internal view returns (bool) {
        if (timestamp_ == 0) return true;
        unchecked {
            return block.timestamp > uint256(timestamp_) + uint256(maxAge_);
        }
    }

    function _latestPermissibleTimestamp(uint48 maxAge_) internal view returns (uint256) {
        if (block.timestamp <= uint256(maxAge_)) return 0;
        unchecked {
            return block.timestamp - uint256(maxAge_);
        }
    }

    /// @inheritdoc IMorphoOracle
    /// @dev        Reverts if the configured pair is invalid for the active cache policy.
    function isStale() external view override returns (bool) {
        return
            IPriceCache(factory().getPriceCache()).isStale(
                collateralToken(),
                loanToken(),
                maxAge()
            );
    }

    /// @inheritdoc IMorphoOracle
    /// @dev        Reverts if the configured pair is invalid for the active cache policy.
    function timestamp() external view override returns (uint48) {
        IPriceCache.CachedPrice memory cachedPrice = IPriceCache(factory().getPriceCache())
            .getCachedPrice(collateralToken(), loanToken());
        return cachedPrice.updatedAt;
    }

    // ========== CACHE INTERFACE ========== //

    /// @inheritdoc IOraclePriceCache
    /// @dev        Unconditionally asks the factory to cache the configured pair.
    ///             The factory validates caller/oracle/factory enabled state.
    ///             Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not a deployed oracle from this factory
    ///             - The caller oracle is disabled
    ///             - The configured pair is invalid in the active cache policy
    ///             - The active cache policy reverts while evaluating staleness or caching
    function cachePrice() external override {
        factory().cachePrice(collateralToken(), loanToken());
    }

    /// @inheritdoc IOraclePriceCache
    /// @dev        Defers staleness checks to the factory using this oracle's configured maxAge.
    ///             Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not a deployed oracle from this factory
    ///             - The caller oracle is disabled
    ///             - The configured pair is invalid in the active cache policy
    ///             - The active cache policy reverts while evaluating staleness or caching
    function cachePriceIfNecessary() external override {
        factory().cachePriceIfNecessary(collateralToken(), loanToken());
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_    The interface identifier, as specified in ERC-165
    /// @return bool            true if the contract implements interfaceId_ and false otherwise
    function supportsInterface(bytes4 interfaceId_) public pure returns (bool) {
        return
            interfaceId_ == type(IMorphoOracle).interfaceId ||
            interfaceId_ == type(IOracle).interfaceId ||
            interfaceId_ == type(IOraclePriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
