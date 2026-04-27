// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {AggregatorV2V3Interface, AggregatorInterface, AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IOraclePriceCache} from "src/policies/interfaces/price/IOraclePriceCache.sol";

// Libraries
import {Clone} from "@clones-with-immutable-args-1.1.2/Clone.sol";
import {SafeCast} from "@openzeppelin-4.8.0/utils/math/SafeCast.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {String} from "src/libraries/String.sol";

/// @title  ChainlinkOracleCloneable
/// @author OlympusDAO
/// @notice Oracle adapter that implements Chainlink's AggregatorV2V3Interface from cached base/quote pair snapshots
contract ChainlinkOracleCloneable is IChainlinkOracle, IOraclePriceCache, Clone {
    uint8 internal constant _VERSION = 1;

    // ========== IMMUTABLE ARGS LAYOUT ========== //

    // 0x00: factory address (20 bytes)
    // 0x14: base token address (20 bytes)
    // 0x28: quote token address (20 bytes)
    // 0x3C: cache decimals at creation (1 byte, stored as uint8)
    // 0x3D: max age (8 bytes, stored as uint64)
    // 0x45: name (32 bytes)

    // ========== IMMUTABLE ARGS GETTERS ========== //

    /// @notice The factory address
    /// @dev    Does not revert.
    ///
    /// @return The factory address stored in immutable args
    function factory() public pure returns (IOracleFactory) {
        return IOracleFactory(_getArgAddress(0x00));
    }

    /// @notice The base token address
    /// @dev    Does not revert.
    ///
    /// @return address The base token address stored in immutable args
    function baseToken() public pure override returns (address) {
        return _getArgAddress(0x14);
    }

    /// @notice The quote token address
    /// @dev    Does not revert.
    ///
    /// @return address The quote token address stored in immutable args
    function quoteToken() public pure override returns (address) {
        return _getArgAddress(0x28);
    }

    /// @notice The cache decimal scale captured at creation time
    /// @dev    This value is intentionally immutable per oracle instance.
    ///
    /// @return uint8 The cache decimal scale stored in immutable args
    function _priceDecimals() internal pure returns (uint8) {
        return _getArgUint8(0x3C);
    }

    /// @notice The maximum allowed age for cached prices
    /// @dev    Does not revert.
    ///
    /// @return uint48 The max age stored in immutable args
    function maxAge() public pure override returns (uint48) {
        return uint48(_getArgUint64(0x3D));
    }

    /// @notice The name of the oracle
    /// @dev    Does not revert.
    ///
    /// @return string The name stored in immutable args
    function name() public pure override returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x45))));
    }

    // ========== AGGREGATOR V3 INTERFACE ========== //

    /// @inheritdoc AggregatorV3Interface
    /// @dev        Does not revert.
    ///
    /// @return uint8   The number of decimals
    function decimals() external pure override returns (uint8) {
        return _priceDecimals();
    }

    /// @inheritdoc AggregatorV3Interface
    /// @dev        Does not revert.
    ///
    /// @return string  The oracle name
    function description() external pure override returns (string memory) {
        return name();
    }

    /// @inheritdoc AggregatorV3Interface
    /// @dev        Does not revert.
    ///
    /// @return uint256 The version number
    function version() external pure override returns (uint256) {
        return _VERSION;
    }

    /// @dev        This function uses cached pair snapshots only (round-style semantics).
    ///             It does not fallback to live pricing when caches are stale.
    ///
    ///             This function will revert if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
    ///
    ///             If callers encounter a revert due to feed state, they should cache prices then retry.
    ///
    /// @return roundId          The cached pair round ID
    /// @return answer           The price of 1 base token in quote tokens, scaled by 10^decimals()
    /// @return startedAt        The timestamp when the round started (same as updatedAt)
    /// @return updatedAt        The timestamp when the round was updated (from the cached pair snapshot)
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

        IPriceCache.CachedPrice memory cachedPrice = IPriceCache(factory_.getPriceCache())
            .getCachedPrice(baseToken(), quoteToken());
        uint256 assetPriceUsd = cachedPrice.assetPriceUsd;
        uint256 quotePriceUsd = cachedPrice.quotePriceUsd;
        uint48 updatedAt_ = cachedPrice.updatedAt;

        // Handle no cached data or rounding down to zero.
        if (assetPriceUsd == 0 || quotePriceUsd == 0 || updatedAt_ == 0) {
            revert ChainlinkOracle_NoDataPresent();
        }

        // Calculate pair quote in configured decimal scale from cached USD legs.
        uint256 price = FullMath.mulDiv(assetPriceUsd, 10 ** _priceDecimals(), quotePriceUsd);

        roundId = cachedPrice.roundId;
        answer = SafeCast.toInt256(price);
        startedAt = updatedAt_;
        updatedAt = updatedAt_;
        answeredInRound = roundId;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @inheritdoc AggregatorV3Interface
    /// @dev        Reverts if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
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

    /// @inheritdoc IChainlinkOracle
    /// @dev        Chainlink-style round readers may consume stale rounds. This flag allows
    ///             consumers to detect stale or missing cached state before reading.
    ///             Reverts if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The configured pair is invalid for the active cache policy
    function isStale() external view override returns (bool) {
        IOracleFactory factory_ = factory();
        if (!factory_.isOracleEnabled(address(this))) {
            revert ChainlinkOracle_NotEnabled();
        }

        return IPriceCache(factory_.getPriceCache()).isStale(baseToken(), quoteToken(), maxAge());
    }

    /// @inheritdoc AggregatorV3Interface
    /// @dev        Only supports the latest round. For any other round ID, reverts with ChainlinkOracle_NoDataPresent().
    ///
    ///             This function will revert if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
    ///
    /// @param  roundId_         The round ID to query
    /// @return roundId          The round ID
    /// @return answer           The price of 1 base token in quote tokens, scaled by 10^decimals()
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
    /// @dev        Reverts if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
    ///
    /// @return int256  The latest price
    function latestAnswer() external view override returns (int256) {
        (, int256 answer, , , ) = _latestRoundDataInternal();
        return answer;
    }

    /// @inheritdoc AggregatorInterface
    /// @dev        Reverts if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
    ///
    /// @return uint256 The latest timestamp
    function latestTimestamp() external view override returns (uint256) {
        (, , , uint256 updatedAt, ) = _latestRoundDataInternal();
        return updatedAt;
    }

    /// @inheritdoc AggregatorInterface
    /// @dev        Reverts if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
    ///
    /// @return uint256 The latest round ID
    function latestRound() external view override returns (uint256) {
        (uint80 roundId, , , , ) = _latestRoundDataInternal();
        return uint256(roundId);
    }

    /// @inheritdoc AggregatorInterface
    /// @dev        Reverts if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
    ///             - `roundId_` is not the latest round ID
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
    /// @dev        Reverts if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled or deactivated in Kernel (checked via factory.isOracleEnabled())
    ///             - The cache policy is deactivated in Kernel
    ///             - The base/quote pair is invalid for the configured cache policy
    ///             - Either cached USD leg is zero
    ///             - No cached pair observation is present (`updatedAt == 0`)
    ///             - `roundId_` is not the latest round ID
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
    ///             Reverts if:
    ///             - The factory is disabled
    ///             - This contract is not a deployed oracle from the factory
    ///             - This contract is not enabled in the factory
    ///             - The configured pair is invalid in the active cache policy
    function cachePrice() external override {
        factory().cachePrice(baseToken(), quoteToken());
    }

    /// @inheritdoc IOraclePriceCache
    /// @dev        Defers staleness checks to the factory using this oracle's configured maxAge.
    ///             Reverts if:
    ///             - The factory is disabled
    ///             - This contract is not a deployed oracle from the factory
    ///             - This contract is not enabled in the factory
    ///             - The configured pair is invalid in the active cache policy
    function cachePriceIfNecessary() external override {
        factory().cachePriceIfNecessary(baseToken(), quoteToken());
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
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
