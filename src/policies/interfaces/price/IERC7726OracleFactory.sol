// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IERC7726OracleFactory
/// @author OlympusDAO
/// @notice  Interface for deploying and managing ERC7726 clone oracles parameterized by maxAge
interface IERC7726OracleFactory {
    // ========== EVENTS ========== //

    /// @notice  Emitted when a new oracle is created
    /// @param   oracle The created oracle address
    /// @param   maxAge The max age configured for this oracle
    event OracleCreated(address indexed oracle, uint48 indexed maxAge);

    /// @notice  Emitted when oracle creation is enabled
    event CreationEnabled();

    /// @notice  Emitted when oracle creation is disabled
    event CreationDisabled();

    /// @notice  Emitted when an oracle is enabled
    /// @param   oracle The enabled oracle address
    event OracleEnabled(address indexed oracle);

    /// @notice  Emitted when an oracle is disabled
    /// @param   oracle The disabled oracle address
    event OracleDisabled(address indexed oracle);

    // ========== ERRORS ========== //

    /// @notice  Thrown when module version is not supported
    /// @param   keycode The keycode of the module
    /// @param   major The major version of the module
    /// @param   minor The minor version of the module
    error ERC7726OracleFactory_UnsupportedModuleVersion(bytes5 keycode, uint8 major, uint8 minor);

    /// @notice  Thrown when module does not support interface
    /// @param   keycode The keycode of the module
    /// @param   interfaceId The interface identifier, as specified in ERC-165
    error ERC7726OracleFactory_UnsupportedModuleInterface(bytes5 keycode, bytes4 interfaceId);

    /// @notice  Thrown when oracle creation is disabled
    error ERC7726OracleFactory_CreationDisabled();

    /// @notice  Thrown when trying to create an oracle that already exists for maxAge
    /// @param   maxAge The maxAge that already has an oracle
    error ERC7726OracleFactory_OracleAlreadyExists(uint48 maxAge);

    /// @notice  Thrown when creation is already enabled
    error ERC7726OracleFactory_CreationAlreadyEnabled();

    /// @notice  Thrown when creation is already disabled
    error ERC7726OracleFactory_CreationAlreadyDisabled();

    /// @notice  Thrown when an invalid oracle address is provided
    /// @param   oracle The invalid oracle address
    error ERC7726OracleFactory_InvalidOracle(address oracle);

    /// @notice  Thrown when an oracle is already enabled
    /// @param   oracle The already enabled oracle address
    error ERC7726OracleFactory_OracleAlreadyEnabled(address oracle);

    /// @notice  Thrown when an oracle is already disabled
    /// @param   oracle The already disabled oracle address
    error ERC7726OracleFactory_OracleAlreadyDisabled(address oracle);

    /// @notice  Thrown when custom params are malformed
    /// @param   length The custom params length
    error ERC7726OracleFactory_InvalidCustomParams(uint256 length);

    // ========== FUNCTIONS ========== //

    /// @notice  Creates a new oracle for a specific maxAge
    ///
    /// @param   maxAge_ The maximum age (in seconds) of cached prices used by the oracle
    /// @param   customParams_ Optional params for factory-specific customization
    /// @return  oracle The address of the created oracle
    function createOracle(
        uint48 maxAge_,
        bytes calldata customParams_
    ) external returns (address oracle);

    /// @notice  Gets the oracle address for a maxAge
    ///
    /// @param   maxAge_ The maximum age used by the oracle
    /// @return  oracle The oracle address, or address(0) if not found
    function getOracle(uint48 maxAge_) external view returns (address oracle);

    /// @notice  Gets all deployed oracle addresses
    ///
    /// @return  oracles Array of all oracle addresses
    function getOracles() external view returns (address[] memory oracles);

    /// @notice  Gets the current PRICE module address
    ///
    /// @return  module The PRICE module address
    function getPriceModule() external view returns (address module);

    /// @notice  Enables a specific oracle
    ///
    /// @param   oracle_ The oracle address to enable
    function enableOracle(address oracle_) external;

    /// @notice  Disables a specific oracle
    ///
    /// @param   oracle_ The oracle address to disable
    function disableOracle(address oracle_) external;

    /// @notice  Checks if a specific oracle is enabled
    ///
    /// @param   oracle_ The oracle address to check
    /// @return  enabled true if the oracle is enabled, false otherwise
    function isOracleEnabled(address oracle_) external view returns (bool enabled);

    /// @notice  Enables oracle creation
    function enableCreation() external;

    /// @notice  Disables oracle creation
    function disableCreation() external;
}
