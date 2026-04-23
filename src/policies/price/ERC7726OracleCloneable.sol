// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IPriceOracle} from "src/policies/interfaces/price/IPriceOracle.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IERC7726OraclePriceCache} from "src/policies/interfaces/price/IERC7726OraclePriceCache.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {Clone} from "@clones-with-immutable-args-1.1.2/Clone.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {String} from "src/libraries/String.sol";

/// @title  ERC7726OracleCloneable
/// @author OlympusDAO
/// @notice Cloneable ERC7726 oracle that quotes any base/quote pair from cached pair snapshots
contract ERC7726OracleCloneable is IERC7726Oracle, IERC7726OraclePriceCache, Clone {
    using FullMath for uint256;

    // ========== IMMUTABLE ARGS LAYOUT ========== //

    // 0x00: factory address (20 bytes)
    // 0x14: max age (8 bytes, stored as uint64)
    // 0x1C: name (32 bytes)

    /// @notice The factory address
    /// @dev    Does not revert.
    function factory() public pure returns (IERC7726OracleFactory) {
        return IERC7726OracleFactory(_getArgAddress(0x00));
    }

    /// @notice The maximum allowed age for cached prices
    /// @dev    Does not revert.
    function maxAge() public pure override returns (uint48) {
        return uint48(_getArgUint64(0x14));
    }

    /// @inheritdoc IPriceOracle
    /// @dev        Does not revert.
    function name() external pure override returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x1C))));
    }

    function _checkEnabled() internal view {
        if (!factory().isOracleEnabled(address(this))) {
            revert ERC7726Oracle_NotEnabled();
        }
    }

    /// @inheritdoc IPriceOracle
    /// @dev        Uses cached pair snapshots only.
    ///
    ///             Reverts if:
    ///             - The oracle is disabled in the factory
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - The shared cached timestamp is stale
    ///             - Base/quote cached prices are zero
    ///             - Either token does not implement `decimals()`
    ///
    ///             If callers encounter a feed-state revert, they should cache prices then retry.
    ///             A caller can alternatively call `isStale()`, call `cachePrice()` (if the result is true), and then this function.
    function getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) external view override returns (uint256 outAmount) {
        return _getQuoteInternal(inAmount, base, quote);
    }

    function _getQuoteInternal(
        uint256 inAmount_,
        address base_,
        address quote_
    ) internal view returns (uint256 outAmount_) {
        _checkEnabled();
        IPriceCache.CachedPrice memory cachedPrice = IPriceCache(factory().getPriceCache())
            .getCachedPrice(base_, quote_);
        uint48 pairTimestamp = cachedPrice.updatedAt;

        // Check for staleness
        uint48 maxAge_ = maxAge();
        if (
            cachedPrice.assetPriceUsd == 0 ||
            cachedPrice.quotePriceUsd == 0 ||
            _isStaleFromTimestamp(pairTimestamp, maxAge_)
        ) {
            revert ERC7726Oracle_Stale(pairTimestamp, _latestPermissibleTimestamp(maxAge_));
        }

        outAmount_ = inAmount_.mulDiv(cachedPrice.assetPriceUsd, cachedPrice.quotePriceUsd).mulDiv(
            10 ** IERC20(quote_).decimals(),
            10 ** IERC20(base_).decimals()
        );
    }

    /// @inheritdoc IPriceOracle
    /// @dev        Returns symmetric bid/ask using the same quote value.
    ///             Reverts if:
    ///             - The oracle is disabled in the factory
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - The shared cached timestamp is stale
    ///             - Base/quote cached prices are zero
    ///             - Either token does not implement `decimals()`
    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    ) external view override returns (uint256 bidOutAmount, uint256 askOutAmount) {
        uint256 outAmount = _getQuoteInternal(inAmount, base, quote);
        return (outAmount, outAmount);
    }

    /// @inheritdoc IERC7726OraclePriceCache
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - This contract is not a deployed oracle from the factory
    ///             - This contract is not enabled in the factory
    ///             - The active price cache rejects the pair
    function cachePrice(address base_, address quote_) external override {
        factory().cachePrice(base_, quote_);
    }

    /// @inheritdoc IERC7726OraclePriceCache
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - This contract is not a deployed oracle from the factory
    ///             - This contract is not enabled in the factory
    ///             - The active price cache rejects the pair
    ///             - The active price cache reverts while evaluating staleness or caching
    function cachePriceIfNecessary(address base_, address quote_) external override {
        factory().cachePriceIfNecessary(base_, quote_);
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

    /// @inheritdoc IERC7726Oracle
    /// @dev        Reverts if the active cache policy rejects `(base, quote)`.
    function isStale(address base, address quote) external view override returns (bool) {
        return IPriceCache(factory().getPriceCache()).isStale(base, quote, maxAge());
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        Returns 0 if the pair price has not been cached.
    ///             Reverts if the active cache policy rejects `(base, quote)`.
    function timestamp(address base, address quote) external view override returns (uint48) {
        IPriceCache.CachedPrice memory cachedPrice = IPriceCache(factory().getPriceCache())
            .getCachedPrice(base, quote);
        return cachedPrice.updatedAt;
    }

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_    The interface identifier, as specified in ERC-165
    /// @return bool            True if the contract implements `interfaceId_`
    function supportsInterface(bytes4 interfaceId_) public pure returns (bool) {
        return
            interfaceId_ == type(IPriceOracle).interfaceId ||
            interfaceId_ == type(IERC7726Oracle).interfaceId ||
            interfaceId_ == type(IERC7726OraclePriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
