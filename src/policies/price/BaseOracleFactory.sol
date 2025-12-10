// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Bophades
import {Kernel, Policy, Keycode, toKeycode, Permissions, Module} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ORACLE_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Libraries
import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";

/// @title  BaseOracleFactory
/// @author OlympusDAO
/// @notice Abstract base contract for oracle factories with common functionality
/// @dev    Uses ClonesWithImmutableArgs for gas-efficient oracle deployment
abstract contract BaseOracleFactory is Policy, PolicyEnabler, IOracleFactory, IVersioned {
    using ClonesWithImmutableArgs for address;

    // ========== STATE ========== //

    /// @notice The PRICE module
    IPRICEv2 public PRICE;

    /// @notice The PRICE module decimals
    uint8 public PRICE_DECIMALS;

    /// @notice Mapping from collateral token to loan token to oracle address
    mapping(address collateralToken => mapping(address loanToken => address oracle))
        internal _tokensToOracle;

    /// @notice Internal array of all deployed oracles
    address[] internal _oracles;

    /// @notice Mapping to validate deployed oracles
    mapping(address => bool) public isOracle;

    /// @notice Mapping to track if an oracle is enabled
    mapping(address => bool) public _isOracleEnabled;

    /// @notice Whether new oracle creation is enabled
    bool public isCreationEnabled;

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new BaseOracleFactory
    ///
    /// @param  kernel_ The Kernel address
    constructor(Kernel kernel_) Policy(kernel_) {
        // Creation is enabled by default
        isCreationEnabled = true;

        // Disabled by default from PolicyEnabler
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("PRICE");
        dependencies[1] = toKeycode("ROLES");

        address priceModule = getModuleAddress(dependencies[0]);

        // Require PRICE v1.2+ (major=1, minor>=2) or v2+ (major>=2)
        // Cast to Module to access VERSION() function
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if (major == 1 && minor < 2) {
            revert OracleFactory_UnsupportedPRICEVersion(major, minor);
        }

        // Verify the PRICE module supports IPRICEv2 interface
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert OracleFactory_PRICEInterfaceNotSupported();
        }

        PRICE = IPRICEv2(priceModule);
        PRICE_DECIMALS = PRICE.decimals();

        // Set ROLES module (required by PolicyEnabler)
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        // No permissions needed - only reading from PRICE module
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure virtual override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ACCESS CONTROL ========== //

    /// @notice Checks if the caller has the oracle_manager, manager, or admin role
    function _onlyOracleManagerOrManagerOrAdminRole() internal view {
        if (
            !ROLES.hasRole(msg.sender, ORACLE_MANAGER_ROLE) &&
            !_isManager(msg.sender) &&
            !_isAdmin(msg.sender)
        ) {
            revert NotAuthorised();
        }
    }

    /// @notice Checks if the caller has the oracle_manager, manager, admin, or emergency role
    function _onlyOracleManagerOrManagerOrAdminOrEmergencyRole() internal view {
        if (
            !ROLES.hasRole(msg.sender, ORACLE_MANAGER_ROLE) &&
            !_isManager(msg.sender) &&
            !_isAdmin(msg.sender) &&
            !_isEmergency(msg.sender)
        ) {
            revert NotAuthorised();
        }
    }

    /// @notice Modifier that reverts if the caller does not have the oracle_manager, manager, or admin role
    modifier onlyOracleManagerOrManagerOrAdminRole() {
        _onlyOracleManagerOrManagerOrAdminRole();
        _;
    }

    /// @notice Modifier that reverts if the caller does not have the oracle_manager, manager, admin, or emergency role
    modifier onlyOracleManagerOrManagerOrAdminOrEmergencyRole() {
        _onlyOracleManagerOrManagerOrAdminOrEmergencyRole();
        _;
    }

    // ========== ABSTRACT METHODS ========== //

    /// @notice Returns the oracle implementation address for cloning
    ///
    /// @return address The address of the oracle implementation contract to be cloned
    function _getOracleImplementation() internal view virtual returns (address);

    /// @notice Encodes oracle-specific data for cloning
    /// @dev    This function should perform service-specific validation, calculate parameters,
    ///         and encode the immutable args for the clone
    ///
    /// @param  collateralToken_    The collateral token address
    /// @param  loanToken_          The loan token address
    /// @param  customParams_       Service-specific custom parameters (can be empty)
    /// @return bytes               The encoded bytes for cloning
    function _encodeOracleData(
        address collateralToken_,
        address loanToken_,
        bytes calldata customParams_
    ) internal view virtual returns (bytes memory);

    // ========== FACTORY FUNCTIONS ========== //

    /// @inheritdoc IOracleFactory
    function createOracle(
        address collateralToken_,
        address loanToken_,
        bytes calldata customParams_
    ) external override onlyEnabled onlyOracleManagerOrManagerOrAdminRole returns (address oracle) {
        // Check if creation is enabled
        if (!isCreationEnabled) {
            revert OracleFactory_CreationDisabled();
        }

        // Validate PRICE module has been set
        if (address(PRICE) == address(0)) {
            revert OracleFactory_PRICEInterfaceNotSupported();
        }

        // Check if oracle already exists
        if (_tokensToOracle[collateralToken_][loanToken_] != address(0)) {
            revert OracleFactory_OracleAlreadyExists(collateralToken_, loanToken_);
        }

        // Validate collateral token
        if (collateralToken_ == address(0) || collateralToken_.code.length == 0) {
            revert OracleFactory_InvalidToken(collateralToken_);
        }

        // Validate loan token
        if (loanToken_ == address(0) || loanToken_.code.length == 0) {
            revert OracleFactory_InvalidToken(loanToken_);
        }

        // Validate tokens are configured in PRICE module
        // PRICE.getPrice() will revert if tokens are not approved or price feeds are not functioning
        PRICE.getPrice(collateralToken_);
        PRICE.getPrice(loanToken_);

        // Get service-specific encoded data (includes validation, calculation, and encoding)
        bytes memory oracleData = _encodeOracleData(collateralToken_, loanToken_, customParams_);

        // Get oracle implementation
        address implementation = _getOracleImplementation();

        // Create clone with immutable args
        oracle = implementation.clone(oracleData);

        // Update storage
        _tokensToOracle[collateralToken_][loanToken_] = oracle;
        _oracles.push(oracle);
        isOracle[oracle] = true;
        _isOracleEnabled[oracle] = true;

        // Emit events
        // Note: New oracles are enabled by default, so we emit OracleEnabled event
        emit OracleCreated(oracle, collateralToken_, loanToken_);
        emit OracleEnabled(oracle);

        // Return the oracle address
        return oracle;
    }

    /// @inheritdoc IOracleFactory
    function getOracle(
        address collateralToken_,
        address loanToken_
    ) external view override returns (address oracle) {
        oracle = _tokensToOracle[collateralToken_][loanToken_];
    }

    /// @inheritdoc IOracleFactory
    function getPriceModule() external view override returns (address) {
        return address(PRICE);
    }

    /// @inheritdoc IOracleFactory
    function getOracles() external view override returns (address[] memory) {
        return _oracles;
    }

    // ========== CREATION CONTROL ========== //

    /// @inheritdoc IOracleFactory
    function enableCreation() external override onlyEnabled onlyOracleManagerOrManagerOrAdminRole {
        if (isCreationEnabled) revert OracleFactory_CreationAlreadyEnabled();
        isCreationEnabled = true;
        emit CreationEnabled();
    }

    /// @inheritdoc IOracleFactory
    function disableCreation()
        external
        override
        onlyEnabled
        onlyOracleManagerOrManagerOrAdminOrEmergencyRole
    {
        if (!isCreationEnabled) revert OracleFactory_CreationAlreadyDisabled();
        isCreationEnabled = false;
        emit CreationDisabled();
    }

    // ========== ORACLE STATE ========== //

    /// @inheritdoc IOracleFactory
    /// @dev        This function reverts if:
    ///             - The caller does not have the required role
    ///             - The contract is disabled
    ///             - The oracle is not created by the factory
    ///             - The oracle is already enabled
    function enableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrManagerOrAdminRole {
        if (!isOracle[oracle_]) revert OracleFactory_InvalidOracle(oracle_);
        if (_isOracleEnabled[oracle_]) revert OracleFactory_OracleAlreadyEnabled(oracle_);

        _isOracleEnabled[oracle_] = true;
        emit OracleEnabled(oracle_);
    }

    /// @inheritdoc IOracleFactory
    /// @dev        This function reverts if:
    ///             - The caller does not have the required role
    ///             - The contract is disabled
    ///             - The oracle is not created by the factory
    ///             - The oracle is already disabled
    function disableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrManagerOrAdminOrEmergencyRole {
        if (!isOracle[oracle_]) revert OracleFactory_InvalidOracle(oracle_);
        if (!_isOracleEnabled[oracle_]) revert OracleFactory_OracleAlreadyDisabled(oracle_);

        _isOracleEnabled[oracle_] = false;
        emit OracleDisabled(oracle_);
    }

    /// @inheritdoc IOracleFactory
    /// @dev        Determines if a given oracle is enabled, using the following logic:
    ///             - Factory must be enabled
    ///             - Oracle must be created by the factory
    ///             - Oracle must be enabled
    function isOracleEnabled(address oracle_) external view override returns (bool) {
        return
            isEnabled && // Factory enabled
            isOracle[oracle_] && // Oracle exists
            _isOracleEnabled[oracle_]; // Oracle enabled
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @param interfaceId_ The interface identifier, as specified in ERC-165
    /// @return true if the contract implements interfaceId_ and false otherwise
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IOracleFactory).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
