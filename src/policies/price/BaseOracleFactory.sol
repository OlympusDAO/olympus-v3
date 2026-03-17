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
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";

/// @title  BaseOracleFactory
/// @author OlympusDAO
/// @notice Abstract base contract for oracle factories with common functionality
/// @dev    Uses ClonesWithImmutableArgs for gas-efficient oracle deployment
abstract contract BaseOracleFactory is
    Policy,
    PolicyEnabler,
    IOracleFactory,
    IVersioned,
    ReentrancyGuard
{
    using ClonesWithImmutableArgs for address;

    // ========== STATE ========== //

    bytes5 internal constant _PRICE_KEYCODE = "PRICE";
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    /// @notice The PRICE module
    IPRICEv2 public PRICE;

    /// @notice The PRICE module decimals
    uint8 public PRICE_DECIMALS;

    /// @notice Mapping from base token to quote token to maxAge to oracle address
    mapping(address baseToken => mapping(address quoteToken => mapping(uint48 maxAge => address oracle)))
        internal _tokensToOracle;

    /// @notice Internal array of all deployed oracles
    address[] internal _oracles;

    /// @notice Mapping to validate deployed oracles
    mapping(address => bool) public isOracle;

    /// @notice Mapping from oracle to base token
    mapping(address oracle => address baseToken) internal _oracleToBaseToken;

    /// @notice Mapping from oracle to quote token
    mapping(address oracle => address quoteToken) internal _oracleToQuoteToken;

    /// @notice Mapping from oracle to maxAge
    mapping(address oracle => uint48 maxAge) internal _oracleToMaxAge;

    /// @notice Mapping to track if an oracle is enabled
    mapping(address => bool) internal _isOracleEnabled;

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
        dependencies[0] = toKeycode(_PRICE_KEYCODE);
        dependencies[1] = toKeycode(_ROLES_KEYCODE);

        address priceModule = getModuleAddress(dependencies[0]);

        // Require PRICE v1.2+ (major=1, minor>=2) or v2+ (major>=2)
        // Cast to Module to access VERSION() function
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if (major == 0 || (major == 1 && minor < 2))
            revert OracleFactory_UnsupportedModuleVersion(_PRICE_KEYCODE, major, minor);

        // Verify the PRICE module supports IPRICEv2 interface
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId))
            revert OracleFactory_UnsupportedModuleInterface(
                _PRICE_KEYCODE,
                type(IPRICEv2).interfaceId
            );

        // Set PRICE module
        PRICE = IPRICEv2(priceModule);
        PRICE_DECIMALS = PRICE.decimals();

        // Set ROLES module (required by PolicyEnabler)
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        // Ensure ROLES module is using the expected major version
        (uint8 rolesMajor, uint8 rolesMinor) = ROLES.VERSION();
        if (rolesMajor != 1)
            revert OracleFactory_UnsupportedModuleVersion(_ROLES_KEYCODE, rolesMajor, rolesMinor);
    }

    /// @inheritdoc Policy
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](1);
        requests[0] = Permissions({
            keycode: toKeycode(_PRICE_KEYCODE),
            funcSelector: IPRICEv2.cachePrice.selector
        });
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure virtual override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ACCESS CONTROL ========== //

    /// @notice Checks if the caller has the oracle_manager or admin role
    function _onlyOracleManagerOrAdminRole() internal view {
        if (!ROLES.hasRole(msg.sender, ORACLE_MANAGER_ROLE) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    /// @notice Checks if the caller has the oracle_manager, admin, or emergency role
    function _onlyOracleManagerOrAdminOrEmergencyRole() internal view {
        if (
            !ROLES.hasRole(msg.sender, ORACLE_MANAGER_ROLE) &&
            !_isAdmin(msg.sender) &&
            !_isEmergency(msg.sender)
        ) {
            revert NotAuthorised();
        }
    }

    /// @notice Modifier that reverts if the caller does not have the oracle_manager or admin role
    modifier onlyOracleManagerOrAdminRole() {
        _onlyOracleManagerOrAdminRole();
        _;
    }

    /// @notice Modifier that reverts if the caller does not have the oracle_manager, admin, or emergency role
    modifier onlyOracleManagerOrAdminOrEmergencyRole() {
        _onlyOracleManagerOrAdminOrEmergencyRole();
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
    /// @param  baseToken_     The base token address
    /// @param  quoteToken_    The quote token address
    /// @param  maxAge_        The maximum age (in seconds) of cached prices used by the oracle
    /// @param  customParams_  Service-specific custom parameters (can be empty)
    /// @return bytes          The encoded bytes for cloning
    function _encodeOracleData(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_,
        bytes calldata customParams_
    ) internal view virtual returns (bytes memory);

    // ========== FACTORY FUNCTIONS ========== //

    /// @inheritdoc IOracleFactory
    function createOracle(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_,
        bytes calldata customParams_
    )
        external
        override
        onlyEnabled
        onlyOracleManagerOrAdminRole
        nonReentrant
        returns (address oracle)
    {
        // Check if creation is enabled
        if (!isCreationEnabled) {
            revert OracleFactory_CreationDisabled();
        }

        // Check if oracle already exists
        if (_tokensToOracle[baseToken_][quoteToken_][maxAge_] != address(0)) {
            revert OracleFactory_OracleAlreadyExists(baseToken_, quoteToken_);
        }

        // Validate base token
        if (baseToken_ == address(0) || baseToken_.code.length == 0) {
            revert OracleFactory_InvalidToken(baseToken_);
        }

        // Validate quote token
        if (quoteToken_ == address(0) || quoteToken_.code.length == 0) {
            revert OracleFactory_InvalidToken(quoteToken_);
        }

        // Validate token pair
        if (baseToken_ == quoteToken_) {
            revert OracleFactory_InvalidTokenPair(baseToken_, quoteToken_);
        }

        // Validate tokens are configured in PRICE module
        // PRICE.getPrice() will revert if tokens are not approved or price feeds are not functioning
        PRICE.getPrice(baseToken_);
        PRICE.getPrice(quoteToken_);

        // Get service-specific encoded data (includes validation, calculation, and encoding)
        bytes memory oracleData = _encodeOracleData(
            baseToken_,
            quoteToken_,
            maxAge_,
            customParams_
        );

        // Get oracle implementation
        address implementation = _getOracleImplementation();

        // Create clone with immutable args
        oracle = implementation.clone(oracleData);

        // Update storage
        _tokensToOracle[baseToken_][quoteToken_][maxAge_] = oracle;
        _oracles.push(oracle);
        isOracle[oracle] = true;
        _oracleToBaseToken[oracle] = baseToken_;
        _oracleToQuoteToken[oracle] = quoteToken_;
        _oracleToMaxAge[oracle] = maxAge_;
        _isOracleEnabled[oracle] = true;

        _cacheOraclePrices(oracle);

        // Emit events
        // Note: New oracles are enabled by default, so we emit OracleEnabled event
        emit OracleCreated(oracle, baseToken_, quoteToken_);
        emit OracleEnabled(oracle);

        // Return the oracle address
        return oracle;
    }

    /// @inheritdoc IOracleFactory
    function getOracle(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_
    ) external view override returns (address oracle) {
        oracle = _tokensToOracle[baseToken_][quoteToken_][maxAge_];
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
    function enableCreation()
        external
        override
        onlyEnabled
        onlyOracleManagerOrAdminRole
        nonReentrant
    {
        if (isCreationEnabled) revert OracleFactory_CreationAlreadyEnabled();

        isCreationEnabled = true;
        emit CreationEnabled();
    }

    /// @inheritdoc IOracleFactory
    function disableCreation()
        external
        override
        onlyEnabled
        onlyOracleManagerOrAdminOrEmergencyRole
        nonReentrant
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
    ) external override onlyEnabled onlyOracleManagerOrAdminRole nonReentrant {
        if (!isOracle[oracle_]) revert OracleFactory_InvalidOracle(oracle_);
        if (_isOracleEnabled[oracle_]) revert OracleFactory_OracleAlreadyEnabled(oracle_);

        _isOracleEnabled[oracle_] = true;
        _cacheOraclePricesIfNecessary(oracle_);
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
    ) external override onlyEnabled onlyOracleManagerOrAdminOrEmergencyRole nonReentrant {
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

    /// @inheritdoc IOracleFactory
    function cacheOraclePrices() external override onlyEnabled nonReentrant {
        if (!isOracle[msg.sender]) revert OracleFactory_InvalidOracle(msg.sender);
        if (!_isOracleEnabled[msg.sender]) revert OracleFactory_OracleDisabled(msg.sender);

        _cacheOraclePrices(msg.sender);
    }

    /// @inheritdoc IOracleFactory
    function cachePrices(
        address baseToken_,
        address quoteToken_
    ) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        _validateCachingPair(msg.sender, baseToken_, quoteToken_);
        PRICE.cachePrice(baseToken_);
        PRICE.cachePrice(quoteToken_);
    }

    /// @inheritdoc IOracleFactory
    function cachePricesIfNecessary(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_
    ) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        _validateCachingPair(msg.sender, baseToken_, quoteToken_);
        (, uint48 baseTokenTimestamp) = PRICE.getPrice(baseToken_, IPRICEv2.Variant.LAST);
        (, uint48 quoteTokenTimestamp) = PRICE.getPrice(quoteToken_, IPRICEv2.Variant.LAST);
        bool timestampsDiffer = baseTokenTimestamp != quoteTokenTimestamp;
        bool baseTokenStale = baseTokenTimestamp == 0 ||
            block.timestamp > uint256(baseTokenTimestamp) + uint256(maxAge_);
        bool quoteTokenStale = quoteTokenTimestamp == 0 ||
            block.timestamp > uint256(quoteTokenTimestamp) + uint256(maxAge_);

        if (timestampsDiffer || baseTokenStale || quoteTokenStale) {
            PRICE.cachePrice(baseToken_);
            PRICE.cachePrice(quoteToken_);
        }
    }

    /// @notice Caches prices for the configured oracle token pair
    /// @param oracle_ The oracle whose base/quote tokens should be cached
    function _cacheOraclePrices(address oracle_) internal {
        address baseToken = _oracleToBaseToken[oracle_];
        address quoteToken = _oracleToQuoteToken[oracle_];

        PRICE.cachePrice(baseToken);
        PRICE.cachePrice(quoteToken);
    }

    /// @notice Conditionally caches prices for the configured oracle token pair based on maxAge/timestamp mismatch
    /// @param oracle_ The oracle whose base/quote tokens should be conditionally cached
    function _cacheOraclePricesIfNecessary(address oracle_) internal {
        address baseToken = _oracleToBaseToken[oracle_];
        address quoteToken = _oracleToQuoteToken[oracle_];
        uint48 maxAge = _oracleToMaxAge[oracle_];

        (, uint48 baseTokenTimestamp) = PRICE.getPrice(baseToken, IPRICEv2.Variant.LAST);
        (, uint48 quoteTokenTimestamp) = PRICE.getPrice(quoteToken, IPRICEv2.Variant.LAST);
        bool timestampsDiffer = baseTokenTimestamp != quoteTokenTimestamp;
        bool baseTokenStale = maxAge > 0 &&
            block.timestamp > uint256(baseTokenTimestamp) + uint256(maxAge);
        bool quoteTokenStale = maxAge > 0 &&
            block.timestamp > uint256(quoteTokenTimestamp) + uint256(maxAge);

        if (timestampsDiffer || baseTokenStale || quoteTokenStale) {
            PRICE.cachePrice(baseToken);
            PRICE.cachePrice(quoteToken);
        }
    }

    function _validateCachingCaller(address caller_) internal view {
        if (!isOracle[caller_]) revert OracleFactory_InvalidOracle(caller_);
        if (!_isOracleEnabled[caller_]) revert OracleFactory_OracleDisabled(caller_);
    }

    function _validateCachingPair(
        address caller_,
        address baseToken_,
        address quoteToken_
    ) internal view {
        if (
            _oracleToBaseToken[caller_] != baseToken_ || _oracleToQuoteToken[caller_] != quoteToken_
        ) {
            revert OracleFactory_InvalidTokenPair(baseToken_, quoteToken_);
        }
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
