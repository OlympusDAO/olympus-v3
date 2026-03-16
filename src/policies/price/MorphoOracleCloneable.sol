// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IOracle} from "src/interfaces/morpho/IOracle.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
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
/// @notice Oracle adapter that implements Morpho's IOracle interface by calling PRICE.getPrice() for collateral and loan tokens
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
    ///
    /// @return The factory address stored in immutable args
    function factory() public pure returns (IOracleFactory) {
        return IOracleFactory(_getArgAddress(0x00));
    }

    /// @notice The collateral token address
    ///
    /// @return address The collateral token address stored in immutable args
    function collateralToken() public pure returns (address) {
        return _getArgAddress(0x14);
    }

    /// @notice The loan token address
    ///
    /// @return address The loan token address stored in immutable args
    function loanToken() public pure returns (address) {
        return _getArgAddress(0x28);
    }

    /// @notice The scale factor for the oracle
    ///
    /// @return uint256 The scale factor stored in immutable args
    function scaleFactor() public pure returns (uint256) {
        return _getArgUint256(0x44);
    }

    /// @notice The maximum allowed age for cached prices
    ///
    /// @return uint48 The max age stored in immutable args
    function _maxAge() internal pure returns (uint48) {
        return uint48(_getArgUint64(0x3C));
    }

    /// @notice The name of the oracle
    ///
    /// @return string The name stored in immutable args
    function name() public pure returns (string memory) {
        return String.bytes32ToString(bytes32(abi.encodePacked(_getArgUint256(0x64))));
    }

    // ========== MORPHO ORACLE INTERFACE ========== //

    /// @inheritdoc IOracle
    /// @notice     Returns the price of 1 collateral token quoted in loan tokens, scaled by 1e36
    /// @dev        This function will revert if:
    ///             - The oracle is not enabled (checked via factory)
    ///             - The factory is disabled (checked via factory.isOracleEnabled())
    ///             - The PRICE module is not initialized in the factory (factory.getPriceModule() returns address(0))
    ///             - Either the collateral or loan token is not configured in the PRICE module
    ///
    ///             The oracle queries the factory on each price call to get the current PRICE module address.
    ///             This allows the PRICE module to be upgraded in the factory without redeploying oracles.
    ///             If the factory is disabled or PRICE is unset, this function will revert.
    ///
    ///             For each asset, PRICE.getPrice(asset, maxAge) uses cached pricing when fresh
    ///             and falls back to live/current pricing when the cache is stale.
    ///             PRICE reverts with PRICE_PriceZero(asset) if a zero price is encountered,
    ///             so loanPriceUsd is expected to be non-zero before scaleFactor().mulDiv(..., loanPriceUsd).
    function price() external view override returns (uint256) {
        // Check if oracle is enabled via factory
        IOracleFactory factory_ = factory();
        if (!factory_.isOracleEnabled(address(this))) {
            revert MorphoOracle_NotEnabled();
        }

        // Get PRICE module from factory dynamically
        // This allows PRICE module upgrades without oracle redeployment
        IPRICEv2 PRICE = IPRICEv2(factory_.getPriceModule());

        // Get prices in USD
        // Scale: PRICE_DECIMALS
        uint48 maxAge = _maxAge();
        uint256 collateralPriceUsd = PRICE.getPrice(collateralToken(), maxAge);
        uint256 loanPriceUsd = PRICE.getPrice(loanToken(), maxAge);

        // Adjust to the correct scale
        // Denominator safety: PRICE.getPrice(...) reverts on zero price (PRICE_PriceZero),
        // so loanPriceUsd should be non-zero here.
        return scaleFactor().mulDiv(collateralPriceUsd, loanPriceUsd);
    }

    // ========== CACHE INTERFACE ========== //

    /// @inheritdoc IOraclePriceCache
    /// @dev        Unconditionally asks the factory to cache both configured assets.
    ///             The factory validates caller/oracle/factory enabled state.
    function cachePrices() external override {
        factory().cachePrices(collateralToken(), loanToken());
    }

    /// @inheritdoc IOraclePriceCache
    /// @dev        Defers staleness checks to the factory using this oracle's configured maxAge.
    function cachePricesIfNecessary() external override {
        factory().cachePricesIfNecessary(collateralToken(), loanToken(), _maxAge());
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
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
