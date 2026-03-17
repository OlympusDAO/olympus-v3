// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
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

    /// @inheritdoc IERC7726Oracle
    function name() external pure override returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x1C))));
    }

    function _checkEnabled() internal view {
        if (!factory().isOracleEnabled(address(this))) {
            revert ERC7726Oracle_NotEnabled();
        }
    }

    /// @inheritdoc IERC7726Oracle
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

        // Get the cached prices
        // PRICE will revert if either price is 0, so we don't need to check that here
        (uint256 basePriceUsd, uint48 baseTimestamp) = PRICE.getPrice(base_, IPRICEv2.Variant.LAST);
        (uint256 quotePriceUsd, uint48 quoteTimestamp) = PRICE.getPrice(
            quote_,
            IPRICEv2.Variant.LAST
        );

        if (baseTimestamp != quoteTimestamp) {
            revert ERC7726Oracle_InconsistentTimestamps(baseTimestamp, quoteTimestamp);
        }

        // Check for staleness
        uint48 maxAge_ = maxAge();
        if (_isStaleFromTimestamp(baseTimestamp, maxAge_)) {
            revert ERC7726Oracle_Stale(baseTimestamp, maxAge_);
        }

        // basePriceUsd and quotePriceUsd are USD prices in 10^18 scale from PRICE.
        // baseTokenScale and quoteTokenScale are token unit scales: 10 ** IERC20(token).decimals().
        uint256 baseTokenScale = 10 ** IERC20(base_).decimals();
        uint256 quoteTokenScale = 10 ** IERC20(quote_).decimals();

        // Step 1: Convert inAmount from base token units into quote units at USD price ratio.
        uint256 intermediate = inAmount_.mulDiv(basePriceUsd, quotePriceUsd);
        // Step 2: Convert between token decimal scales (baseTokenScale -> quoteTokenScale).
        outAmount_ = intermediate.mulDiv(quoteTokenScale, baseTokenScale);
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        Returns symmetric bid/ask using the same quote value.
    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    ) external view override returns (uint256 bidOutAmount, uint256 askOutAmount) {
        uint256 outAmount = _getQuoteInternal(inAmount, base, quote);
        return (outAmount, outAmount);
    }

    /// @notice Caches both base and quote assets through the factory in a single call
    /// @param  base_ The base asset to cache
    /// @param  quote_ The quote asset to cache
    function cachePrices(address base_, address quote_) external override {
        factory().cachePrices(base_, quote_);
    }

    /// @notice Caches both base and quote assets through the factory only when stale
    /// @param  base_ The base asset to conditionally cache
    /// @param  quote_ The quote asset to conditionally cache
    function cachePricesIfNecessary(address base_, address quote_) external override {
        factory().cachePricesIfNecessary(base_, quote_, maxAge());
    }

    function _isStaleFromTimestamp(uint48 timestamp_, uint48 maxAge_) internal view returns (bool) {
        if (timestamp_ == 0) return true;
        return block.timestamp > uint256(timestamp_) + uint256(maxAge_);
    }

    /// @inheritdoc IERC7726Oracle
    function isStale(address base, address quote) external view override returns (bool) {
        IPRICEv2 PRICE = IPRICEv2(factory().getPriceModule());
        (, uint48 baseTimestamp) = PRICE.getPrice(base, IPRICEv2.Variant.LAST);
        (, uint48 quoteTimestamp) = PRICE.getPrice(quote, IPRICEv2.Variant.LAST);

        if (baseTimestamp != quoteTimestamp) return true;
        return _isStaleFromTimestamp(baseTimestamp, maxAge());
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        Reverts if base/quote timestamps are inconsistent.
    function timestamp(address base, address quote) external view override returns (uint48) {
        IPRICEv2 PRICE = IPRICEv2(factory().getPriceModule());
        (, uint48 baseTimestamp) = PRICE.getPrice(base, IPRICEv2.Variant.LAST);
        (, uint48 quoteTimestamp) = PRICE.getPrice(quote, IPRICEv2.Variant.LAST);

        if (baseTimestamp != quoteTimestamp) {
            revert ERC7726Oracle_InconsistentTimestamps(baseTimestamp, quoteTimestamp);
        }

        return baseTimestamp;
    }

    /// @notice Query if a contract implements an interface
    function supportsInterface(bytes4 interfaceId_) public pure returns (bool) {
        return
            interfaceId_ == type(IERC7726Oracle).interfaceId ||
            interfaceId_ == type(IERC7726OraclePriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
