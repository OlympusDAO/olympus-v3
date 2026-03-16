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
import {FullMath} from "src/libraries/FullMath.sol";
import {Clone} from "@clones-with-immutable-args-1.1.2/Clone.sol";
import {String} from "src/libraries/String.sol";
import {SafeCastLib} from "@solmate-6.2.0/utils/SafeCastLib.sol";

/// @title  ChainlinkOracleCloneable
/// @author OlympusDAO
/// @notice Oracle adapter that implements Chainlink's AggregatorV2V3Interface by calling PRICE.getPrice() for base and quote tokens
contract ChainlinkOracleCloneable is IChainlinkOracle, IOraclePriceCache, Clone {
    using FullMath for uint256;
    using SafeCastLib for uint256;

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
    function _maxAge() internal pure returns (uint48) {
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

    /// @inheritdoc AggregatorV3Interface
    /// @dev        This function will revert if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled (checked via factory.isOracleEnabled())
    ///             - Either the base or quote token is not configured in the PRICE module
    ///             - Either the base or quote token returns a price of zero
    ///             - The timestamp of the base or quote token is not consistent
    ///
    ///             The oracle queries the factory on each call to get the current PRICE module address.
    ///             This allows the PRICE module to be upgraded in the factory without redeploying oracles.
    ///
    /// @return roundId          The round ID (timestamp of the observation, cast to uint80)
    /// @return answer           The price of 1 base token in quote tokens, scaled by 10^PRICE_DECIMALS
    /// @return startedAt        The timestamp when the round started (same as updatedAt)
    /// @return updatedAt        The timestamp when the round was updated (from PRICE module's lastObservationTime)
    /// @return answeredInRound  The round ID (same as roundId)
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
        // Check if oracle is enabled via factory
        IOracleFactory factory_ = factory();
        if (!factory_.isOracleEnabled(address(this))) {
            revert ChainlinkOracle_NotEnabled();
        }

        // Get PRICE module from factory dynamically
        // This allows PRICE module upgrades without oracle redeployment
        IPRICEv2 PRICE = IPRICEv2(factory_.getPriceModule());

        uint48 maxAge = _maxAge();
        (uint256 basePrice, uint48 baseTimestamp) = _resolvePriceAndTimestamp(
            PRICE,
            baseToken(),
            maxAge
        );
        (uint256 quotePrice, uint48 quoteTimestamp) = _resolvePriceAndTimestamp(
            PRICE,
            quoteToken(),
            maxAge
        );

        // Revert if the last timestamp is not consistent
        if (baseTimestamp != quoteTimestamp) {
            revert ChainlinkOracle_InconsistentTimestamps(baseTimestamp, quoteTimestamp);
        }

        // Calculate: 1 base token = (basePrice / quotePrice) * 10^PRICE_DECIMALS quote tokens
        // Result is in PRICE_DECIMALS scale
        uint256 price = FullMath.mulDiv(basePrice, 10 ** _priceDecimals(), quotePrice);

        // Cast timestamp to uint80 for round ID
        roundId = uint80(baseTimestamp);
        /// forge-lint: disable-next-line(unsafe-typecast)
        answer = int256(price);
        startedAt = baseTimestamp;
        updatedAt = baseTimestamp;
        answeredInRound = roundId;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function _resolvePriceAndTimestamp(
        IPRICEv2 PRICE_,
        address asset_,
        uint48 maxAge_
    ) internal view returns (uint256 price_, uint48 timestamp_) {
        // PRICE.getPrice(asset, maxAge) returns a cached value when cache age <= maxAge,
        // otherwise it falls back to live/current pricing.
        price_ = PRICE_.getPrice(asset_, maxAge_);

        // Resolve timestamp from the same source variant used by maxAge semantics.
        (, uint48 lastTimestamp) = PRICE_.getPrice(asset_, IPRICEv2.Variant.LAST);
        bool cacheFresh = lastTimestamp != 0 &&
            uint256(lastTimestamp) + uint256(maxAge_) >= block.timestamp;

        if (cacheFresh) {
            timestamp_ = lastTimestamp;
        } else {
            (, timestamp_) = PRICE_.getPrice(asset_, IPRICEv2.Variant.CURRENT);
        }
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
        (roundId, answer, startedAt, updatedAt, answeredInRound) = this.latestRoundData();

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
        (, int256 answer, , , ) = this.latestRoundData();
        return answer;
    }

    /// @inheritdoc AggregatorInterface
    ///
    /// @return uint256 The latest timestamp
    function latestTimestamp() external view override returns (uint256) {
        (, , , uint256 updatedAt, ) = this.latestRoundData();
        return updatedAt;
    }

    /// @inheritdoc AggregatorInterface
    ///
    /// @return uint256 The latest round ID
    function latestRound() external view override returns (uint256) {
        (uint80 roundId, , , , ) = this.latestRoundData();
        return uint256(roundId);
    }

    /// @inheritdoc AggregatorInterface
    /// @dev        Only supports the latest round. For any other round ID, reverts with ChainlinkOracle_NoDataPresent().
    ///
    /// @param      roundId_    The round ID to query
    /// @return int256  The answer for the given round ID
    function getAnswer(uint256 roundId_) external view override returns (int256) {
        (, int256 answer, , , ) = this.getRoundData(roundId_.safeCastTo80());
        return answer;
    }

    /// @inheritdoc AggregatorInterface
    /// @dev        Only supports the latest round. For any other round ID, reverts with ChainlinkOracle_NoDataPresent().
    ///
    /// @param      roundId_    The round ID to query
    /// @return uint256 The timestamp for the given round ID
    function getTimestamp(uint256 roundId_) external view override returns (uint256) {
        (, , , uint256 updatedAt, ) = this.getRoundData(roundId_.safeCastTo80());
        return updatedAt;
    }

    // ========== CACHE INTERFACE ========== //

    /// @inheritdoc IOraclePriceCache
    /// @dev        Unconditionally asks the factory to cache both configured assets.
    ///             The factory enforces that:
    ///             - The factory is enabled
    ///             - The caller is a deployed oracle from this factory
    ///             - The oracle is currently enabled
    function cachePrices() external override {
        factory().cachePrices(baseToken(), quoteToken());
    }

    /// @inheritdoc IOraclePriceCache
    /// @dev        Defers staleness checks to the factory using this oracle's configured maxAge.
    function cachePricesIfNecessary() external override {
        factory().cachePricesIfNecessary(baseToken(), quoteToken(), _maxAge());
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
