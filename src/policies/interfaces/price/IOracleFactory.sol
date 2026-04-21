// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IOracleFactory
/// @author OlympusDAO
/// @notice Oracle-agnostic interface for oracle factories
interface IOracleFactory {
    // ========== EVENTS ========== //

    /// @notice Emitted when a new oracle is created
    ///
    /// @param  oracle      The address of the created oracle
    /// @param  baseToken   The base token address
    /// @param  quoteToken  The quote token address
    event OracleCreated(
        address indexed oracle,
        address indexed baseToken,
        address indexed quoteToken
    );

    /// @notice Emitted when oracle creation is enabled
    event CreationEnabled();

    /// @notice Emitted when oracle creation is disabled
    event CreationDisabled();

    /// @notice Emitted when an oracle is enabled
    ///
    /// @param  oracle The address of the enabled oracle
    event OracleEnabled(address indexed oracle);

    /// @notice Emitted when an oracle is disabled
    ///
    /// @param  oracle The address of the disabled oracle
    event OracleDisabled(address indexed oracle);

    // ========== ERRORS ========== //

    /// @notice Thrown when a token address is invalid (zero address or not a contract)
    ///
    /// @param  token The invalid token address
    error OracleFactory_InvalidToken(address token);

    /// @notice Thrown when module version is not supported
    ///
    /// @param  keycode     The keycode of the module
    /// @param  major       The major version of the module
    /// @param  minor       The minor version of the module
    error OracleFactory_UnsupportedModuleVersion(bytes5 keycode, uint8 major, uint8 minor);

    /// @notice Thrown when module does not support interface
    ///
    /// @param  keycode     The keycode of the module
    /// @param  interfaceId The interface identifier, as specified in ERC-165
    error OracleFactory_UnsupportedModuleInterface(bytes5 keycode, bytes4 interfaceId);

    /// @notice Thrown when oracle creation is disabled
    error OracleFactory_CreationDisabled();

    /// @notice Thrown when trying to create an oracle that already exists
    ///
    /// @param  baseToken  The base token address
    /// @param  quoteToken The quote token address
    error OracleFactory_OracleAlreadyExists(address baseToken, address quoteToken);

    /// @notice Thrown when a token pair is invalid
    ///
    /// @param  baseToken  The base token address
    /// @param  quoteToken The quote token address
    error OracleFactory_InvalidTokenPair(address baseToken, address quoteToken);

    /// @notice Thrown when creation is already enabled
    error OracleFactory_CreationAlreadyEnabled();

    /// @notice Thrown when creation is already disabled
    error OracleFactory_CreationAlreadyDisabled();

    /// @notice Thrown when an invalid oracle address is provided
    ///
    /// @param  oracle The invalid oracle address
    error OracleFactory_InvalidOracle(address oracle);

    /// @notice Thrown when an oracle is already enabled
    ///
    /// @param  oracle The already enabled oracle address
    error OracleFactory_OracleAlreadyEnabled(address oracle);

    /// @notice Thrown when an oracle is already disabled
    ///
    /// @param  oracle The already disabled oracle address
    error OracleFactory_OracleAlreadyDisabled(address oracle);

    /// @notice Thrown when an oracle is disabled and attempts an operation that requires enabled state
    ///
    /// @param  oracle The disabled oracle address
    error OracleFactory_OracleDisabled(address oracle);

    // ========== STATE FUNCTIONS ========== //

    /// @notice Gets the current PRICE module address
    ///
    /// @return module The PRICE module address
    function getPriceModule() external view returns (address module);

    /// @notice Gets the configured price cache policy
    ///
    /// @return policy The price cache policy address
    function getPriceCache() external view returns (address policy);

    // ========== FUNCTIONS ========== //

    /// @notice Creates a new oracle for a base/quote token pair
    ///
    /// @param  baseToken_     The base token address
    /// @param  quoteToken_    The quote token address
    /// @param  maxAge_        The maximum age (in seconds) of cached prices used by the oracle
    /// @param  customParams_  Service-specific custom parameters (can be empty)
    /// @return oracle         The address of the created oracle
    function createOracle(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_,
        bytes calldata customParams_
    ) external returns (address oracle);

    /// @notice Gets the oracle address for a base/quote token pair
    ///
    /// @param  baseToken_     The base token address
    /// @param  quoteToken_    The quote token address
    /// @param  maxAge_        The maximum age (in seconds) of cached prices used by the oracle
    /// @return oracle         The address of the oracle, or address(0) if not found
    function getOracle(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_
    ) external view returns (address oracle);

    /// @notice Gets all deployed oracle addresses
    ///
    /// @return oracles Array of all oracle addresses
    function getOracles() external view returns (address[] memory oracles);

    // ========== ORACLE STATE FUNCTIONS ========== //

    /// @notice Enables a specific oracle
    ///
    /// @param  oracle_ The oracle address to enable
    function enableOracle(address oracle_) external;

    /// @notice Disables a specific oracle
    ///
    /// @param  oracle_ The oracle address to disable
    function disableOracle(address oracle_) external;

    /// @notice Checks if a specific oracle is enabled
    ///
    /// @param  oracle_ The oracle address to check
    /// @return enabled true if the oracle is enabled, false otherwise
    function isOracleEnabled(address oracle_) external view returns (bool enabled);

    /// @notice Caches prices for the calling oracle's configured assets
    ///
    /// @dev    Intended to be called by oracle contracts created by this factory
    function cacheOraclePrices() external;

    /// @notice Caches the provided base/quote pair
    /// @dev    Intended to be called by oracle contracts created by this factory
    ///
    /// @param  baseToken_ The base token address
    /// @param  quoteToken_ The quote token address
    function cachePrice(address baseToken_, address quoteToken_) external;

    /// @notice Caches the provided base/quote pair only when stale
    /// @dev    Intended to be called by oracle contracts created by this factory
    ///
    /// @param  baseToken_  The base token address
    /// @param  quoteToken_ The quote token address
    /// @param  maxAge_     Maximum accepted cache age in seconds
    function cachePriceIfNecessary(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_
    ) external;

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Enables oracle creation
    function enableCreation() external;

    /// @notice Disables oracle creation
    function disableCreation() external;

    /// @notice Sets the configured price cache policy
    ///
    /// @param  policy_ The price cache policy address
    function setPriceCache(address policy_) external;
}
