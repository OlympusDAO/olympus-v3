// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IMorphoOracleFactory} from "src/policies/interfaces/price/IMorphoOracleFactory.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";

// Bophades
import {Kernel, Policy, Keycode, toKeycode, Permissions, Module} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ORACLE_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Libraries
import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @title  MorphoOracleFactory
/// @author OlympusDAO
/// @notice Factory contract for deploying MorphoOracle clones for collateral/loan token pairs
/// @dev    Uses ClonesWithImmutableArgs for gas-efficient oracle deployment
contract MorphoOracleFactory is Policy, PolicyEnabler, IMorphoOracleFactory {
    using ClonesWithImmutableArgs for address;

    // ========== STATE ========== //

    /// @notice The PRICE module
    IPRICEv2 public PRICE;

    /// @notice The PRICE module decimals
    uint8 public PRICE_DECIMALS;

    /// @notice Reference implementation for cloning
    MorphoOracleCloneable public immutable ORACLE_IMPLEMENTATION;

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

    /// @notice The Morpho scale factor decimals
    uint8 internal constant MORPHO_DECIMALS = 36;

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new MorphoOracleFactory
    ///
    /// @param  kernel_ The Kernel address
    constructor(Kernel kernel_) Policy(kernel_) {
        // Deploy implementation for cloning
        ORACLE_IMPLEMENTATION = new MorphoOracleCloneable();

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
            revert MorphoOracleFactory_UnsupportedPRICEVersion(major, minor);
        }

        // Verify the PRICE module supports IPRICEv2 interface
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert MorphoOracleFactory_PRICEInterfaceNotSupported();
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

    // ========== FACTORY FUNCTIONS ========== //

    /// @inheritdoc IMorphoOracleFactory
    function createOracle(
        address collateralToken_,
        address loanToken_
    ) external override onlyEnabled onlyOracleManagerOrManagerOrAdminRole returns (address oracle) {
        // Check if creation is enabled
        if (!isCreationEnabled) {
            revert MorphoOracleFactory_CreationDisabled();
        }

        // Validate PRICE module has been set
        if (address(PRICE) == address(0)) {
            revert MorphoOracleFactory_PRICEInterfaceNotSupported();
        }

        // Check if oracle already exists
        if (_tokensToOracle[collateralToken_][loanToken_] != address(0)) {
            revert MorphoOracleFactory_OracleAlreadyExists(collateralToken_, loanToken_);
        }

        // Validate collateral token
        if (collateralToken_ == address(0) || collateralToken_.code.length == 0) {
            revert MorphoOracleFactory_InvalidToken(collateralToken_);
        }

        // Validate loan token
        if (loanToken_ == address(0) || loanToken_.code.length == 0) {
            revert MorphoOracleFactory_InvalidToken(loanToken_);
        }

        // Validate tokens are configured in PRICE module
        // PRICE.getPrice() will revert if tokens are not approved or price feeds are not functioning
        PRICE.getPrice(collateralToken_);
        PRICE.getPrice(loanToken_);

        // Calculate scale factor
        uint8 collateralDecimals = ERC20(collateralToken_).decimals();
        uint8 loanDecimals = ERC20(loanToken_).decimals();

        // Validate decimals to prevent overflow (max exponent ~77 for uint256)
        // MORPHO_DECIMALS = 36, so we need loanDecimals - collateralDecimals < 41
        // This is extremely unlikely in practice (tokens typically have 0-18 decimals)
        // but we add a check for safety
        /// forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = int256(uint256(loanDecimals)) -
            int256(uint256(collateralDecimals)) +
            int256(uint256(MORPHO_DECIMALS));
        if (exponent < 0 || exponent > 77) {
            revert MorphoOracleFactory_TokenDecimalsOutOfBounds(collateralToken_, loanToken_);
        }

        /// forge-lint: disable-next-line(unsafe-typecast)
        uint256 scaleFactor = 10 ** uint256(exponent);

        // Compose name from token symbols: "collateral/loan Morpho Oracle"
        string memory collateralSymbol = ERC20(collateralToken_).symbol();
        string memory loanSymbol = ERC20(loanToken_).symbol();
        bytes32 oracleName = bytes32(
            abi.encodePacked(collateralSymbol, "/", loanSymbol, " Morpho Oracle")
        );

        // Create clone with immutable args
        // Layout: factory (20 bytes) | collateral (20 bytes) | loan (20 bytes) | scaleFactor (32 bytes) | name (32 bytes)
        bytes memory oracleData = abi.encodePacked(
            address(this), // factory address
            collateralToken_, // collateral token address
            loanToken_, // loan token address
            scaleFactor, // scale factor
            oracleName // name
        );

        oracle = address(ORACLE_IMPLEMENTATION).clone(oracleData);

        // Update storage
        _tokensToOracle[collateralToken_][loanToken_] = oracle;
        _oracles.push(oracle);
        isOracle[oracle] = true;
        _isOracleEnabled[oracle] = true;

        // Emit events
        // Note: New oracles are enabled by default, so we emit OracleEnabled event
        emit OracleCreated(oracle, collateralToken_, loanToken_);
        emit OracleEnabled(oracle);

        return oracle;
    }

    /// @inheritdoc IMorphoOracleFactory
    function getOracle(
        address collateralToken_,
        address loanToken_
    ) external view override returns (address oracle) {
        oracle = _tokensToOracle[collateralToken_][loanToken_];
    }

    /// @inheritdoc IMorphoOracleFactory
    function getPriceModule() external view override returns (address) {
        return address(PRICE);
    }

    /// @inheritdoc IMorphoOracleFactory
    function getOracles() external view override returns (address[] memory) {
        return _oracles;
    }

    // ========== CREATION CONTROL ========== //

    /// @inheritdoc IMorphoOracleFactory
    function enableCreation() external override onlyEnabled onlyOracleManagerOrManagerOrAdminRole {
        if (isCreationEnabled) revert MorphoOracleFactory_CreationAlreadyEnabled();
        isCreationEnabled = true;
        emit CreationEnabled();
    }

    /// @inheritdoc IMorphoOracleFactory
    function disableCreation()
        external
        override
        onlyEnabled
        onlyOracleManagerOrManagerOrAdminOrEmergencyRole
    {
        if (!isCreationEnabled) revert MorphoOracleFactory_CreationAlreadyDisabled();
        isCreationEnabled = false;
        emit CreationDisabled();
    }

    // ========== ORACLE STATE ========== //

    /// @inheritdoc IMorphoOracleFactory
    /// @dev        This function reverts if:
    ///             - The caller does not have the required role
    ///             - The contract is disabled
    ///             - The oracle is not created by the factory
    ///             - The oracle is already enabled
    function enableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrManagerOrAdminRole {
        if (!isOracle[oracle_]) revert MorphoOracleFactory_InvalidOracle(oracle_);
        if (_isOracleEnabled[oracle_]) revert MorphoOracleFactory_OracleAlreadyEnabled(oracle_);

        _isOracleEnabled[oracle_] = true;
        emit OracleEnabled(oracle_);
    }

    /// @inheritdoc IMorphoOracleFactory
    /// @dev        This function reverts if:
    ///             - The caller does not have the required role
    ///             - The contract is disabled
    ///             - The oracle is not created by the factory
    ///             - The oracle is already disabled
    function disableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrManagerOrAdminOrEmergencyRole {
        if (!isOracle[oracle_]) revert MorphoOracleFactory_InvalidOracle(oracle_);
        if (!_isOracleEnabled[oracle_]) revert MorphoOracleFactory_OracleAlreadyDisabled(oracle_);

        _isOracleEnabled[oracle_] = false;
        emit OracleDisabled(oracle_);
    }

    /// @inheritdoc IMorphoOracleFactory
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
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IMorphoOracleFactory).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
