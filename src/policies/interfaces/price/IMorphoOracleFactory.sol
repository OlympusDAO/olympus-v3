// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

/// @title  IMorphoOracleFactory
/// @author OlympusDAO
/// @notice Interface for a Morpho oracle factory
interface IMorphoOracleFactory {
    // ========== EVENTS ========== //

    /// @notice Emitted when a new oracle is created
    ///
    /// @param  oracle           The address of the created oracle
    /// @param  collateralToken  The collateral token address
    /// @param  loanToken        The loan token address
    event OracleCreated(
        address indexed oracle,
        address indexed collateralToken,
        address indexed loanToken
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
    error MorphoOracleFactory_InvalidToken(address token);

    /// @notice Thrown when PRICE module version is not supported (must be v1.2+ or v2+)
    error MorphoOracleFactory_UnsupportedPRICEVersion(uint8 major, uint8 minor);

    /// @notice Thrown when PRICE module does not support IPRICEv2 interface
    error MorphoOracleFactory_PRICEInterfaceNotSupported();

    /// @notice Thrown when oracle creation is disabled
    error MorphoOracleFactory_CreationDisabled();

    /// @notice Thrown when trying to create an oracle that already exists
    ///
    /// @param  collateralToken The collateral token address
    /// @param  loanToken       The loan token address
    error MorphoOracleFactory_OracleAlreadyExists(address collateralToken, address loanToken);

    /// @notice Thrown when creation is already enabled
    error MorphoOracleFactory_CreationAlreadyEnabled();

    /// @notice Thrown when creation is already disabled
    error MorphoOracleFactory_CreationAlreadyDisabled();

    /// @notice Thrown when an invalid oracle address is provided
    ///
    /// @param  oracle The invalid oracle address
    error MorphoOracleFactory_InvalidOracle(address oracle);

    /// @notice Thrown when an oracle is already enabled
    ///
    /// @param  oracle The already enabled oracle address
    error MorphoOracleFactory_OracleAlreadyEnabled(address oracle);

    /// @notice Thrown when an oracle is already disabled
    ///
    /// @param  oracle The already disabled oracle address
    error MorphoOracleFactory_OracleAlreadyDisabled(address oracle);

    /// @notice Thrown when token decimals result in invalid scale factor (overflow or negative)
    ///
    /// @param  collateralToken The collateral token address
    /// @param  loanToken       The loan token address
    error MorphoOracleFactory_TokenDecimalsOutOfBounds(address collateralToken, address loanToken);

    // ========== STATE FUNCTIONS ========== //

    /// @notice Gets the current PRICE module address
    ///
    /// @return module The PRICE module address
    function getPriceModule() external view returns (address module);

    // ========== FUNCTIONS ========== //

    /// @notice Creates a new oracle for a collateral/loan token pair
    ///
    /// @param  collateralToken_    The collateral token address
    /// @param  loanToken_          The loan token address
    /// @return oracle              The address of the created oracle
    function createOracle(
        address collateralToken_,
        address loanToken_
    ) external returns (address oracle);

    /// @notice Gets the oracle address for a collateral/loan token pair
    ///
    /// @param  collateralToken_    The collateral token address
    /// @param  loanToken_          The loan token address
    /// @return oracle              The address of the oracle, or address(0) if not found
    function getOracle(
        address collateralToken_,
        address loanToken_
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

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Enables oracle creation
    function enableCreation() external;

    /// @notice Disables oracle creation
    function disableCreation() external;
}
