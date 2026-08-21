// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

// Interfaces
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

import {console2} from "@forge-std-1.16.2/console2.sol";

/// @notice Batch script for deploying new oracles via factory policies
/// @dev    Requires oracle_manager role (held by DAO MS and Timelock)
///
///         Prerequisites:
///         - Oracle factories must be deployed and enabled
///         - PRICE module must have tokens configured
///         - Caller must have oracle_manager role
///         - minPrice and maxPrice are base/quote pair-price bounds, normalized to 18 decimals
///
///         Args file format:
///         {
///           "functions": [{
///             "name": "deployChainlinkOracle",
///             "args": {
///               "baseToken": "0x...",
///               "quoteToken": "0x...",
///               "maxAge": "3600",                    // seconds
///               "minPrice": "1000000000000000000",  // pair price, 18 decimals
///               "maxPrice": "10000000000000000000"  // pair price, 18 decimals
///             }
///           }]
///         }
contract DeployOracles is BatchScriptV2 {
    using FullMath for uint256;

    // ========== STATE ========== //

    /// @notice Chainlink oracle factory address
    address internal _chainlinkFactory;

    /// @notice Morpho oracle factory address
    address internal _morphoFactory;

    /// @notice Base token address (loaded from args)
    address internal _baseToken;

    /// @notice Quote token address (loaded from args)
    address internal _quoteToken;

    /// @notice Minimum expected base/quote pair price in 18 decimals (loaded from args)
    uint256 internal _minPrice;

    /// @notice Maximum expected base/quote pair price in 18 decimals (loaded from args)
    uint256 internal _maxPrice;

    /// @notice Oracle max age (seconds) loaded from args
    uint48 internal _maxAge;

    /// @notice Which factory type is being used (for validation)
    bool internal _isChainlinkFactory;

    // ========== DEPLOYMENT FUNCTIONS ========== //

    /// @notice Deploy a single Chainlink oracle for a token pair
    /// @param useDaoMS_ Whether to use the DAO multisig
    /// @param signOnly_ Whether to only sign the batch
    /// @param argsFilePath_ Path to args file with baseToken, quoteToken, maxAge, minPrice, maxPrice
    function deployChainlinkOracle(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath, signature_) {
        console2.log("=== Deploying Chainlink Oracle ===");

        _loadFactoryAddresses();
        _loadOracleParams("deployChainlinkOracle");

        _isChainlinkFactory = true;

        console2.log("Base token:", _baseToken);
        console2.log("Quote token:", _quoteToken);
        console2.log("Max age:", _maxAge);
        console2.log("Min price:", _minPrice);
        console2.log("Max price:", _maxPrice);
        console2.log("Chainlink factory:", _chainlinkFactory);

        // Deploy Chainlink oracle
        _deployChainlinkOracle(_baseToken, _quoteToken);

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this.validateOraclePrice.selector);

        console2.log("\n=== Chainlink Oracle Batch Prepared ===");
        proposeBatch();
    }

    /// @notice Deploy a single Morpho oracle for a token pair
    /// @param useDaoMS_ Whether to use the DAO multisig
    /// @param signOnly_ Whether to only sign the batch
    /// @param argsFilePath_ Path to args file with baseToken, quoteToken, maxAge, minPrice, maxPrice
    function deployMorphoOracle(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFilePath_,
        string calldata ledgerDerivationPath,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFilePath_, ledgerDerivationPath, signature_) {
        console2.log("=== Deploying Morpho Oracle ===");

        _loadFactoryAddresses();
        _loadOracleParams("deployMorphoOracle");

        _isChainlinkFactory = false;

        console2.log("Base token (collateral):", _baseToken);
        console2.log("Quote token (loan):", _quoteToken);
        console2.log("Max age:", _maxAge);
        console2.log("Min price:", _minPrice);
        console2.log("Max price:", _maxPrice);
        console2.log("Morpho factory:", _morphoFactory);

        // Deploy Morpho oracle
        _deployMorphoOracle(_baseToken, _quoteToken);

        // Set post-batch validation selector
        _setPostBatchValidateSelector(this.validateOraclePrice.selector);

        console2.log("\n=== Morpho Oracle Batch Prepared ===");
        proposeBatch();
    }

    // ========== POST-BATCH VALIDATION ========== //

    /// @notice Validates that the deployed oracle price is within expected bounds
    /// @dev    Checks that the deployed oracle returns a base/quote pair price
    ///         that falls within the 18-decimal min/max range specified in the args file
    ///         Also verifies the oracle was deployed and enabled
    function validateOraclePrice() external view {
        console2.log("\n=== Validating Oracle Price ===");

        console2.log("Base token:", _baseToken);
        console2.log("Quote token:", _quoteToken);
        console2.log("Expected pair price range:", _minPrice, "-", _maxPrice);

        // Get the factory being used
        address factory = _isChainlinkFactory ? _chainlinkFactory : _morphoFactory;
        string memory factoryName = _isChainlinkFactory ? "Chainlink" : "Morpho";

        // Verify oracle was deployed
        address oracle = IOracleFactory(factory).getOracle(_baseToken, _quoteToken, _maxAge);
        require(oracle != address(0), string.concat(factoryName, " oracle not deployed"));
        console2.log(factoryName, " oracle deployed:", oracle);

        // Verify oracle is enabled
        require(
            IOracleFactory(factory).isOracleEnabled(oracle),
            string.concat(factoryName, " oracle not enabled")
        );
        console2.log(factoryName, " oracle enabled");

        uint256 price = _getOraclePairPrice(oracle);
        console2.log("Actual pair price:", price);

        // Validate price is within bounds
        if (price < _minPrice) {
            revert(string.concat("Price below minimum. Actual: ", vm.toString(price)));
        }
        if (price > _maxPrice) {
            revert(string.concat("Price above maximum. Actual: ", vm.toString(price)));
        }

        console2.log("Oracle price validation passed");
    }

    // ========== INTERNAL HELPERS ========== //

    function _getOraclePairPrice(address oracle_) internal view returns (uint256 price_) {
        if (_isChainlinkFactory) return _getChainlinkOraclePairPrice(oracle_);

        return _getMorphoOraclePairPrice(oracle_);
    }

    function _getChainlinkOraclePairPrice(address oracle_) internal view returns (uint256 price_) {
        IChainlinkOracle oracle = IChainlinkOracle(oracle_);

        require(!oracle.isStale(), "Chainlink oracle is stale");

        (, int256 answer, , , ) = oracle.latestRoundData();
        require(answer > 0, "Chainlink oracle price is not positive");

        // forge-lint: disable-next-line(unsafe-typecast)
        return _normalizeTo18Decimals(uint256(answer), oracle.decimals());
    }

    function _getMorphoOraclePairPrice(address oracle_) internal view returns (uint256 price_) {
        IMorphoOracle oracle = IMorphoOracle(oracle_);

        require(!oracle.isStale(), "Morpho oracle is stale");

        uint256 scaleFactor = oracle.scaleFactor();
        require(scaleFactor != 0, "Morpho oracle scale factor is zero");

        return oracle.price().mulDiv(1e18, scaleFactor);
    }

    function _normalizeTo18Decimals(
        uint256 price_,
        uint8 decimals_
    ) internal pure returns (uint256 price18_) {
        if (decimals_ == 18) return price_;
        if (decimals_ < 18) return price_ * 10 ** (18 - decimals_);

        return price_ / 10 ** (decimals_ - 18);
    }

    /// @notice Load factory addresses from environment
    function _loadFactoryAddresses() internal {
        _chainlinkFactory = _envAddressNotZero("olympus.policies.ChainlinkOracleFactory");
        _morphoFactory = _envAddressNotZero("olympus.policies.MorphoOracleFactory");
    }

    /// @notice Load oracle parameters from args file
    /// @param functionName_ Name of the function to read args for
    function _loadOracleParams(string memory functionName_) internal {
        _baseToken = _readBatchArgAddress(functionName_, "baseToken");
        _quoteToken = _readBatchArgAddress(functionName_, "quoteToken");
        uint256 maxAge = _readBatchArgUint256(functionName_, "maxAge");
        _minPrice = _readBatchArgUint256(functionName_, "minPrice");
        _maxPrice = _readBatchArgUint256(functionName_, "maxPrice");

        // maxAge is encoded as uint48 in oracle immutable args
        if (maxAge > type(uint48).max) {
            revert("DeployOracles: maxAge exceeds uint48");
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        _maxAge = uint48(maxAge);

        // Validate that minPrice does not exceed maxPrice
        if (_minPrice > _maxPrice) {
            revert("DeployOracles: minPrice cannot exceed maxPrice");
        }
    }

    /// @notice Deploy a Chainlink oracle for a token pair
    /// @param baseToken_ The base token address
    /// @param quoteToken_ The quote token address
    function _deployChainlinkOracle(address baseToken_, address quoteToken_) internal {
        console2.log("\nAdding Chainlink oracle to batch");

        addToBatch(
            _chainlinkFactory,
            abi.encodeWithSelector(
                IOracleFactory.createOracle.selector,
                baseToken_,
                quoteToken_,
                _maxAge,
                "" // customParams (empty for default)
            )
        );
    }

    /// @notice Deploy a Morpho oracle for a token pair
    /// @param baseToken_ The base token address (used as collateral)
    /// @param quoteToken_ The quote token address (used as loan)
    function _deployMorphoOracle(address baseToken_, address quoteToken_) internal {
        console2.log("\nAdding Morpho oracle to batch");

        addToBatch(
            _morphoFactory,
            abi.encodeWithSelector(
                IOracleFactory.createOracle.selector,
                baseToken_,
                quoteToken_,
                _maxAge,
                "" // customParams (empty for default)
            )
        );
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
