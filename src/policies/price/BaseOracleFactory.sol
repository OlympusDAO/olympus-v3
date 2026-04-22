// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Bophades
import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
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

    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    /// @notice The pair cache policy
    IPriceCache public priceCache;

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
    /// @dev    Reverts if `priceCache_` is not a valid IPriceCache policy for this Kernel.
    ///
    /// @param  kernel_ The Kernel address
    /// @param  priceCache_ The price cache policy address
    constructor(Kernel kernel_, address priceCache_) Policy(kernel_) {
        // Creation is enabled by default
        isCreationEnabled = true;

        _setPriceCache(priceCache_);

        // Disabled by default from PolicyEnabler
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev        Reverts if the configured ROLES module major version is unsupported.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode(_ROLES_KEYCODE);

        // Set ROLES module (required by PolicyEnabler)
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // Ensure ROLES module is using the expected major version
        (uint8 rolesMajor, uint8 rolesMinor) = ROLES.VERSION();
        if (rolesMajor != 1)
            revert OracleFactory_UnsupportedModuleVersion(_ROLES_KEYCODE, rolesMajor, rolesMinor);
    }

    /// @inheritdoc Policy
    /// @dev        Does not revert.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    /// @dev        Does not revert.
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
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not admin or oracle manager
    ///             - Oracle creation is disabled
    ///             - An oracle for `(baseToken_, quoteToken_, maxAge_)` already exists
    ///             - Either token is invalid or both tokens are the same
    ///             - Service-specific validation in `_encodeOracleData` fails
    ///             - Initial cache population fails in the configured price cache policy
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

        // This will revert if the assets are not approved
        _cacheOraclePrices(oracle);

        // Emit events
        // Note: New oracles are enabled by default, so we emit OracleEnabled event
        emit OracleCreated(oracle, baseToken_, quoteToken_);
        emit OracleEnabled(oracle);

        // Return the oracle address
        return oracle;
    }

    /// @inheritdoc IOracleFactory
    /// @dev        Does not revert.
    function getOracle(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_
    ) external view override returns (address oracle) {
        oracle = _tokensToOracle[baseToken_][quoteToken_][maxAge_];
    }

    /// @inheritdoc IOracleFactory
    /// @dev        Does not revert.
    function getPriceCache() external view override returns (address) {
        return address(priceCache);
    }

    /// @inheritdoc IOracleFactory
    /// @dev        Does not revert.
    function getOracles() external view override returns (address[] memory) {
        return _oracles;
    }

    // ========== CREATION CONTROL ========== //

    /// @inheritdoc IOracleFactory
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not admin or oracle manager
    ///             - Creation is already enabled
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
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not admin, oracle manager, or emergency
    ///             - Creation is already disabled
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

    /// @inheritdoc IOracleFactory
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not admin
    ///             - `policy_` is zero, not IPriceCache-compatible, or bound to a different Kernel
    function setPriceCache(
        address policy_
    ) external override onlyEnabled onlyAdminRole nonReentrant {
        _setPriceCache(policy_);
    }

    // ========== ORACLE STATE ========== //

    /// @inheritdoc IOracleFactory
    /// @dev        Reverts if:
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
        _cachePriceIfNecessary(
            _oracleToBaseToken[oracle_],
            _oracleToQuoteToken[oracle_],
            _oracleToMaxAge[oracle_]
        );
        emit OracleEnabled(oracle_);
    }

    /// @inheritdoc IOracleFactory
    /// @dev        Reverts if:
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
    /// @dev        Does not revert.
    ///             Determines if a given oracle is enabled, using the following logic:
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
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not a factory-created oracle
    ///             - The caller oracle is disabled
    ///             - `(baseToken_, quoteToken_)` does not match the caller oracle pair
    ///             - Underlying cache write fails
    function cachePrice(
        address baseToken_,
        address quoteToken_
    ) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        _validateCachingPair(msg.sender, baseToken_, quoteToken_);
        priceCache.cachePrice(baseToken_, quoteToken_);
    }

    /// @inheritdoc IOracleFactory
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not a factory-created oracle
    ///             - The caller oracle is disabled
    ///             - `(baseToken_, quoteToken_)` does not match the caller oracle pair
    ///             - Underlying cache evaluation/write fails
    function cachePriceIfNecessary(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_
    ) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        _validateCachingPair(msg.sender, baseToken_, quoteToken_);
        _cachePriceIfNecessary(baseToken_, quoteToken_, maxAge_);
    }

    /// @notice Caches prices for the configured oracle token pair
    ///
    /// @param  oracle_ The oracle whose base/quote tokens should be cached
    function _cacheOraclePrices(address oracle_) internal {
        address baseToken = _oracleToBaseToken[oracle_];
        address quoteToken = _oracleToQuoteToken[oracle_];

        priceCache.cachePrice(baseToken, quoteToken);
    }

    /// @notice Conditionally caches prices for the token pair based on direct pair staleness
    function _cachePriceIfNecessary(
        address baseToken_,
        address quoteToken_,
        uint48 maxAge_
    ) internal {
        priceCache.cachePriceIfNecessary(baseToken_, quoteToken_, maxAge_);
    }

    function _setPriceCache(address policy_) internal {
        if (policy_ == address(0) || !_implementsIPriceCache(policy_) || !_hasSameKernel(policy_)) {
            revert OracleFactory_InvalidPriceCache(policy_);
        }
        priceCache = IPriceCache(policy_);
        emit PriceCacheSet(policy_);
    }

    function _implementsIPriceCache(address policy_) internal view returns (bool) {
        if (policy_.code.length == 0) return false;

        (bool success, bytes memory returnData) = policy_.staticcall(
            abi.encodeWithSelector(
                IERC165.supportsInterface.selector,
                type(IPriceCache).interfaceId
            )
        );

        return success && returnData.length >= 32 && abi.decode(returnData, (bool));
    }

    function _hasSameKernel(address policy_) internal view returns (bool) {
        (bool success, bytes memory returnData) = policy_.staticcall(
            abi.encodeWithSignature("kernel()")
        );
        if (!success || returnData.length < 32) return false;

        address cacheKernel = abi.decode(returnData, (address));
        return cacheKernel == address(kernel);
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
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_    The interface identifier, as specified in ERC-165
    /// @return bool            True if the contract implements interfaceId_ and false otherwise
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IOracleFactory).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
