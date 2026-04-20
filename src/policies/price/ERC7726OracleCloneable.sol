// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IPriceOracle} from "src/policies/interfaces/price/IPriceOracle.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IERC7726OraclePriceCache} from "src/policies/interfaces/price/IERC7726OraclePriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {Clone} from "@clones-with-immutable-args-1.1.2/Clone.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {String} from "src/libraries/String.sol";

/// @title  ERC7726OracleCloneable
/// @author OlympusDAO
/// @notice Cloneable ERC7726 oracle that quotes any base/quote pair using the PRICE module
contract ERC7726OracleCloneable is IERC7726Oracle, IERC7726OraclePriceCache, Clone {
    using FullMath for uint256;

    // ========== IMMUTABLE ARGS LAYOUT ========== //

    // 0x00: factory address (20 bytes)
    // 0x14: max age (8 bytes, stored as uint64)
    // 0x1C: name (32 bytes)

    /// @notice The factory address
    function factory() public pure returns (IERC7726OracleFactory) {
        return IERC7726OracleFactory(_getArgAddress(0x00));
    }

    /// @notice The maximum allowed age for cached prices
    function maxAge() public pure override returns (uint48) {
        return uint48(_getArgUint64(0x14));
    }

    /// @inheritdoc IPriceOracle
    function name() external pure override returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x1C))));
    }

    function _checkEnabled() internal view {
        if (!factory().isOracleEnabled(address(this))) {
            revert ERC7726Oracle_NotEnabled();
        }
    }

    /// @inheritdoc IPriceOracle
    /// @dev        Uses cached LAST prices only.
    ///
    ///             Reverts if:
    ///             - The oracle is disabled in the factory
    ///             - Base/quote cached timestamps are inconsistent
    ///             - The shared cached timestamp is stale
    ///             - Base/quote cached prices are zero
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
        IPRICEv2 PRICE = IPRICEv2(factory().getPriceModule());

        (uint256 baseAssetPriceUsd, uint256 quoteAssetPriceUsd, uint48 pairTimestamp, ) = PRICE
            .getCachedPrice(base_, quote_);
        uint256 pairPrice = 0;
        if (baseAssetPriceUsd != 0 && quoteAssetPriceUsd != 0) {
            pairPrice = FullMath.mulDiv(
                baseAssetPriceUsd,
                10 ** PRICE.decimals(),
                quoteAssetPriceUsd
            );
        }

        // `getCachedPrice()` is requested in the same base/quote orientation as `getQuote()`.
        // The returned USD legs are then combined into a direct base/quote price.

        // Check for staleness
        uint48 maxAge_ = maxAge();
        if (pairPrice == 0 || _isStaleFromTimestamp(pairTimestamp, maxAge_)) {
            revert ERC7726Oracle_Stale(pairTimestamp, maxAge_);
        }

        outAmount_ = inAmount_.mulDiv(pairPrice, 10 ** PRICE.decimals()).mulDiv(
            10 ** IERC20(quote_).decimals(),
            10 ** IERC20(base_).decimals()
        );
    }

    /// @inheritdoc IPriceOracle
    /// @dev        Returns symmetric bid/ask using the same quote value.
    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    ) external view override returns (uint256 bidOutAmount, uint256 askOutAmount) {
        uint256 outAmount = _getQuoteInternal(inAmount, base, quote);
        return (outAmount, outAmount);
    }

    /// @inheritdoc IERC7726OraclePriceCache
    function cachePrice(address base_, address quote_) external override {
        factory().cachePrice(base_, quote_);
    }

    /// @inheritdoc IERC7726OraclePriceCache
    function cachePriceIfNecessary(address base_, address quote_) external override {
        factory().cachePriceIfNecessary(base_, quote_, maxAge());
    }

    function _isStaleFromTimestamp(uint48 timestamp_, uint48 maxAge_) internal view returns (bool) {
        if (timestamp_ == 0) return true;
        unchecked {
            return block.timestamp > uint256(timestamp_) + uint256(maxAge_);
        }
    }

    /// @inheritdoc IERC7726Oracle
    function isStale(address base, address quote) external view override returns (bool) {
        IPRICEv2 PRICE = IPRICEv2(factory().getPriceModule());
        (, , uint48 pairTimestamp, ) = PRICE.getCachedPrice(base, quote);
        return _isStaleFromTimestamp(pairTimestamp, maxAge());
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        Returns 0 if the pair price has not been cached.
    function timestamp(address base, address quote) external view override returns (uint48) {
        IPRICEv2 PRICE = IPRICEv2(factory().getPriceModule());
        (, , uint48 pairTimestamp, ) = PRICE.getCachedPrice(base, quote);
        return pairTimestamp;
    }

    /// @notice Query if a contract implements an interface
    function supportsInterface(bytes4 interfaceId_) public pure returns (bool) {
        return
            interfaceId_ == type(IPriceOracle).interfaceId ||
            interfaceId_ == type(IERC7726Oracle).interfaceId ||
            interfaceId_ == type(IERC7726OraclePriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
