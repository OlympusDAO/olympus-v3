// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
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
contract ERC7726OracleCloneable is IERC7726Oracle, IPriceCache, Clone {
    using FullMath for uint256;

    // ========== ERRORS ========== //

    /// @notice Thrown when the oracle is not enabled in the factory
    error ERC7726OracleCloneable_NotEnabled();

    /// @notice Thrown when base/quote timestamps resolve to different sources/times
    /// @param  baseTimestamp_ The resolved base timestamp
    /// @param  quoteTimestamp_ The resolved quote timestamp
    error ERC7726OracleCloneable_InconsistentTimestamps(
        uint48 baseTimestamp_,
        uint48 quoteTimestamp_
    );

    // ========== IMMUTABLE ARGS LAYOUT ========== //

    // 0x00: factory address (20 bytes)
    // 0x14: max age (8 bytes, stored as uint64)
    // 0x1C: name (32 bytes)

    /// @notice The factory address
    function factory() public pure returns (IERC7726OracleFactory) {
        return IERC7726OracleFactory(_getArgAddress(0x00));
    }

    /// @notice The maximum allowed age for cached prices
    function maxAge() public pure returns (uint48) {
        return uint48(_getArgUint64(0x14));
    }

    /// @inheritdoc IERC7726Oracle
    function name() external pure override returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x1C))));
    }

    function _checkEnabled() internal view {
        if (!factory().isOracleEnabled(address(this))) {
            revert ERC7726OracleCloneable_NotEnabled();
        }
    }

    function _resolvePriceAndTimestamp(
        IPRICEv2 PRICE_,
        address asset_,
        uint48 maxAge_
    ) internal view returns (uint256 price_, uint48 timestamp_) {
        price_ = PRICE_.getPrice(asset_, maxAge_);
        (, uint48 lastTimestamp) = PRICE_.getPrice(asset_, IPRICEv2.Variant.LAST);
        bool cacheFresh = lastTimestamp != 0 &&
            uint256(lastTimestamp) + uint256(maxAge_) >= block.timestamp;
        if (cacheFresh) {
            timestamp_ = lastTimestamp;
            return (price_, timestamp_);
        }

        (, timestamp_) = PRICE_.getPrice(asset_, IPRICEv2.Variant.CURRENT);
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        Uses PRICE.getPrice(asset, maxAge) for both base and quote:
    ///             - returns cached values when cache age <= maxAge
    ///             - falls back to live/current pricing when cache is stale
    ///
    ///             Reverts if the oracle is disabled in the factory.
    function getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) external view override returns (uint256 outAmount) {
        _checkEnabled();

        IPRICEv2 PRICE = IPRICEv2(factory().getPriceModule());
        uint48 maxAge_ = maxAge();
        (uint256 basePriceUsd, uint48 baseTimestamp) = _resolvePriceAndTimestamp(
            PRICE,
            base,
            maxAge_
        );
        (uint256 quotePriceUsd, uint48 quoteTimestamp) = _resolvePriceAndTimestamp(
            PRICE,
            quote,
            maxAge_
        );
        if (baseTimestamp != quoteTimestamp) {
            revert ERC7726OracleCloneable_InconsistentTimestamps(baseTimestamp, quoteTimestamp);
        }

        uint256 baseTokenScale = 10 ** IERC20(base).decimals();
        uint256 quoteTokenScale = 10 ** IERC20(quote).decimals();

        return inAmount.mulDiv(basePriceUsd * quoteTokenScale, quotePriceUsd * baseTokenScale);
    }

    /// @inheritdoc IERC7726Oracle
    /// @dev        Returns symmetric bid/ask using the same quote value.
    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    ) external view override returns (uint256 bidOutAmount, uint256 askOutAmount) {
        uint256 outAmount = this.getQuote(inAmount, base, quote);
        return (outAmount, outAmount);
    }

    /// @inheritdoc IPriceCache
    function cachePrice(address asset_) external override {
        IPriceCache(address(factory())).cachePrice(asset_);
    }

    /// @notice Caches the given asset through the factory only when stale for this oracle's maxAge
    /// @param  asset_ The asset to cache if necessary
    function cachePriceIfNecessary(address asset_) external {
        this.cachePriceIfNecessary(asset_, false);
    }

    /// @inheritdoc IPriceCache
    function cachePriceIfNecessary(address asset_, bool forceUpdate_) external override {
        IPriceCache(address(factory())).cachePriceIfNecessary(asset_, forceUpdate_);
    }

    /// @notice Query if a contract implements an interface
    function supportsInterface(bytes4 interfaceId_) public pure returns (bool) {
        return
            interfaceId_ == type(IERC7726Oracle).interfaceId ||
            interfaceId_ == type(IPriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
