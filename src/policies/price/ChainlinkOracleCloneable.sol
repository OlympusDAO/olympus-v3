// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {AggregatorV2V3Interface, AggregatorInterface, AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IOraclePriceCache} from "src/policies/interfaces/price/IOraclePriceCache.sol";

// Libraries
import {Clone} from "@clones-with-immutable-args-1.1.2/Clone.sol";
import {String} from "src/libraries/String.sol";

/// @title  ChainlinkOracleCloneable
/// @author OlympusDAO
/// @notice Oracle adapter that implements Chainlink's AggregatorV2V3Interface by calling PRICE.getPrice() for base and quote tokens
contract ChainlinkOracleCloneable is IChainlinkOracle, IOraclePriceCache, Clone {
    uint8 internal constant _VERSION = 1;

    // ========== IMMUTABLE ARGS LAYOUT ========== //

    // 0x00: factory address (20 bytes)
    // 0x14: base token address (20 bytes)
    // 0x28: quote token address (20 bytes)
    // 0x3C: PRICE decimals at creation (1 byte, stored as uint8)
    // 0x3D: max age (8 bytes, stored as uint64)
    // 0x45: name (32 bytes)

    // ========== IMMUTABLE ARGS GETTERS ========== //

    /// @notice The factory address
    ///
    /// @return The factory address stored in immutable args
    function factory() public pure returns (IOracleFactory) {
        return IOracleFactory(_getArgAddress(0x00));
    }

    /// @notice The base token address
    ///
    /// @return address The base token address stored in immutable args
    function baseToken() public pure override returns (address) {
        return _getArgAddress(0x14);
    }

    /// @notice The quote token address
    ///
    /// @return address The quote token address stored in immutable args
    function quoteToken() public pure override returns (address) {
        return _getArgAddress(0x28);
    }

    /// @notice The PRICE decimals captured at creation time
    ///
    /// @return uint8 The PRICE decimals stored in immutable args
    function _priceDecimals() internal pure returns (uint8) {
        return _getArgUint8(0x3C);
    }

    /// @notice The maximum allowed age for cached prices
    ///
    /// @return uint48 The max age stored in immutable args
    function maxAge() public pure override returns (uint48) {
        return uint48(_getArgUint64(0x3D));
    }

    /// @notice The name of the oracle
    ///
    /// @return string The name stored in immutable args
    function name() public pure override returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x45))));
    }

    // ========== AGGREGATOR V3 INTERFACE ========== //

    /// @inheritdoc AggregatorV3Interface
    ///
    /// @return uint8   The number of decimals
    function decimals() external pure override returns (uint8) {
        return _priceDecimals();
    }

    /// @inheritdoc AggregatorV3Interface
    ///
    /// @return string  The oracle name
    function description() external pure override returns (string memory) {
        return name();
    }

    /// @inheritdoc AggregatorV3Interface
    ///
    /// @return uint256 The version number
    function version() external pure override returns (uint256) {
        return _VERSION;
    }

    /// @dev        This function uses cached LAST prices only (round-style semantics).
    ///             It does not fallback to live pricing when caches are stale.
    ///
    ///             This function will revert if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled (checked via factory.isOracleEnabled())
    ///             - Either the base or quote token is not configured in the PRICE module
    ///             - Either the base or quote token cached price is zero
    ///             - The base/quote cached timestamps are inconsistent
    ///
    ///             If callers encounter a revert due to feed state, they should cache prices then retry.
    ///
    /// @return roundId          The round ID (timestamp of the observation, cast to uint80)
    /// @return answer           The price of 1 base token in quote tokens, scaled by 10^PRICE_DECIMALS
    /// @return startedAt        The timestamp when the round started (same as updatedAt)
    /// @return updatedAt        The timestamp when the round was updated (from PRICE module's lastObservationTime)
    /// @return answeredInRound  The round ID (same as roundId)
    function _latestRoundDataInternal()
        internal
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Check if oracle is enabled via factory
        IOracleFactory factory_ = factory();
        if (!factory_.isOracleEnabled(address(this))) {
            revert ChainlinkOracle_NotEnabled();
        }

        // Get the cached direct base/quote price snapshot.
        (uint256 price, uint48 updatedAt_) = IPRICEv2(factory_.getPriceModule()).getPriceIn(
            baseToken(),
            quoteToken(),
            IPRICEv2.Variant.LAST
        );

        // Handle no cached data or rounding down to zero.
        if (price == 0 || updatedAt_ == 0) revert ChainlinkOracle_NoDataPresent();

        // Use timestamp as synthetic round ID.
        roundId = uint80(updatedAt_);
        /// forge-lint: disable-next-line(unsafe-typecast)
        answer = int256(price);
        startedAt = updatedAt_;
        updatedAt = updatedAt_;
        answeredInRound = roundId;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return _latestRoundDataInternal();
    }

    function _isStaleFromTimestamp(uint48 timestamp_) internal view returns (bool) {
        // If there's no timestamp, consider it stale to force caching before use
        if (timestamp_ == 0) return true;

        return block.timestamp > uint256(timestamp_) + uint256(maxAge());
    }

    /// @inheritdoc IChainlinkOracle
    /// @dev        Chainlink-style round readers may consume stale rounds. This flag allows
    ///             consumers to detect stale or inconsistent cached state before reading.
    function isStale() external view override returns (bool) {
        IPRICEv2 PRICE = IPRICEv2(factory().getPriceModule());
        (, uint48 pairTimestamp) = PRICE.getPriceIn(
            baseToken(),
            quoteToken(),
            IPRICEv2.Variant.LAST
        );

        return _isStaleFromTimestamp(pairTimestamp);
    }

    /// @inheritdoc AggregatorV3Interface
    /// @dev        Only supports the latest round. For any other round ID, reverts with ChainlinkOracle_NoDataPresent().
    ///
    ///             This function will revert if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled (checked via factory.isOracleEnabled())
    ///             - Either the base or quote token is not configured in the PRICE module
    ///             - Either the base or quote token returns a price of zero
    ///             - The timestamp of the base or quote token is not consistent
    ///
    /// @param  roundId_         The round ID to query
    /// @return roundId          The round ID
    /// @return answer           The price of 1 base token in quote tokens, scaled by 10^PRICE_DECIMALS
    /// @return startedAt        The timestamp when the round started
    /// @return updatedAt        The timestamp when the round was updated
    /// @return answeredInRound  The round ID
    function getRoundData(
        uint80 roundId_
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Get latest round data
        (roundId, answer, startedAt, updatedAt, answeredInRound) = _latestRoundDataInternal();

        // Only support the latest round
        if (roundId_ != roundId) {
            revert ChainlinkOracle_NoDataPresent();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    // ========== AGGREGATOR V2 INTERFACE ========== //

    /// @inheritdoc AggregatorInterface
    ///
    /// @return int256  The latest price
    function latestAnswer() external view override returns (int256) {
        (, int256 answer, , , ) = _latestRoundDataInternal();
        return answer;
    }

    /// @inheritdoc AggregatorInterface
    ///
    /// @return uint256 The latest timestamp
    function latestTimestamp() external view override returns (uint256) {
        (, , , uint256 updatedAt, ) = _latestRoundDataInternal();
        return updatedAt;
    }

    /// @inheritdoc AggregatorInterface
    ///
    /// @return uint256 The latest round ID
    function latestRound() external view override returns (uint256) {
        (uint80 roundId, , , , ) = _latestRoundDataInternal();
        return uint256(roundId);
    }

    /// @inheritdoc AggregatorInterface
    /// @dev        Only supports the latest round. For any other round ID, reverts with ChainlinkOracle_NoDataPresent().
    ///
    /// @param      roundId_    The round ID to query
    /// @return int256  The answer for the given round ID
    function getAnswer(uint256 roundId_) external view override returns (int256) {
        (uint80 roundId, int256 answer, , , ) = _latestRoundDataInternal();
        if (roundId_ != uint256(roundId)) {
            revert ChainlinkOracle_NoDataPresent();
        }
        return answer;
    }

    /// @inheritdoc AggregatorInterface
    /// @dev        Only supports the latest round. For any other round ID, reverts with ChainlinkOracle_NoDataPresent().
    ///
    /// @param      roundId_    The round ID to query
    /// @return uint256 The timestamp for the given round ID
    function getTimestamp(uint256 roundId_) external view override returns (uint256) {
        (uint80 roundId, , , uint256 updatedAt, ) = _latestRoundDataInternal();
        if (roundId_ != uint256(roundId)) {
            revert ChainlinkOracle_NoDataPresent();
        }
        return updatedAt;
    }

    // ========== CACHE INTERFACE ========== //

    /// @inheritdoc IOraclePriceCache
    /// @dev        Unconditionally asks the factory to cache the configured pair.
    ///             The factory enforces that:
    ///             - The factory is enabled
    ///             - The caller is a deployed oracle from this factory
    ///             - The oracle is currently enabled
    function cachePrice() external override {
        factory().cachePrice(baseToken(), quoteToken());
    }

    /// @inheritdoc IOraclePriceCache
    /// @dev        Defers staleness checks to the factory using this oracle's configured maxAge.
    function cachePriceIfNecessary() external override {
        factory().cachePriceIfNecessary(baseToken(), quoteToken(), maxAge());
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    ///
    /// @param  interfaceId_    The interface identifier, as specified in ERC-165
    /// @return bool            true if the contract implements interfaceId_ and false otherwise
    function supportsInterface(bytes4 interfaceId_) public pure returns (bool) {
        return
            interfaceId_ == type(IChainlinkOracle).interfaceId ||
            interfaceId_ == type(AggregatorV2V3Interface).interfaceId ||
            interfaceId_ == type(AggregatorInterface).interfaceId ||
            interfaceId_ == type(AggregatorV3Interface).interfaceId ||
            interfaceId_ == type(IOraclePriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
