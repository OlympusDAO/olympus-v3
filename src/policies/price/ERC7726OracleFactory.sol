// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Bophades
import {Kernel, Policy, Keycode, toKeycode, Permissions, Module} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ORACLE_MANAGER_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ERC7726OracleCloneable} from "src/policies/price/ERC7726OracleCloneable.sol";

// Libraries
import {ClonesWithImmutableArgs} from "clones/ClonesWithImmutableArgs.sol";
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";

/// @title  ERC7726OracleFactory
/// @author OlympusDAO
/// @notice Factory for deploying generic ERC7726 clone oracles keyed by maxAge
contract ERC7726OracleFactory is
    Policy,
    PolicyEnabler,
    IERC7726OracleFactory,
    IVersioned,
    ReentrancyGuard
{
    using ClonesWithImmutableArgs for address;

    // ========== STATE ========== //

    bytes5 internal constant _PRICE_KEYCODE = "PRICE";
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    /// @notice The PRICE module
    IPRICEv2 public PRICE;

    /// @notice Reference implementation for cloning
    ERC7726OracleCloneable public immutable ORACLE_IMPLEMENTATION;

    /// @notice Whether new oracle creation is enabled
    bool public isCreationEnabled;

    /// @notice Internal array of all deployed oracles
    address[] internal _oracles;

    /// @notice Mapping from maxAge to oracle
    mapping(uint48 maxAge => address oracle) internal _maxAgeToOracle;

    /// @notice Mapping from oracle to maxAge
    mapping(address oracle => uint48 maxAge) internal _oracleToMaxAge;

    /// @notice Mapping to validate deployed oracles
    mapping(address oracle => bool) public isOracle;

    /// @notice Mapping to track if an oracle is enabled
    mapping(address oracle => bool) internal _isOracleEnabled;

    bytes32 internal constant _DEFAULT_ORACLE_NAME = bytes32("ERC7726 Oracle");

    // ========== CONSTRUCTOR ========== //

    constructor(Kernel kernel_) Policy(kernel_) {
        ORACLE_IMPLEMENTATION = new ERC7726OracleCloneable();
        isCreationEnabled = true;
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode(_PRICE_KEYCODE);
        dependencies[1] = toKeycode(_ROLES_KEYCODE);

        address priceModule = getModuleAddress(dependencies[0]);

        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if (major < 1 || (major == 1 && minor < 2)) {
            revert ERC7726OracleFactory_UnsupportedModuleVersion(_PRICE_KEYCODE, major, minor);
        }

        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert ERC7726OracleFactory_UnsupportedModuleInterface(
                _PRICE_KEYCODE,
                type(IPRICEv2).interfaceId
            );
        }

        PRICE = IPRICEv2(priceModule);
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 rolesMajor, uint8 rolesMinor) = ROLES.VERSION();
        if (rolesMajor != 1) {
            revert ERC7726OracleFactory_UnsupportedModuleVersion(
                _ROLES_KEYCODE,
                rolesMajor,
                rolesMinor
            );
        }
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
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ACCESS CONTROL ========== //

    function _onlyOracleManagerOrAdminRole() internal view {
        if (!ROLES.hasRole(msg.sender, ORACLE_MANAGER_ROLE) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    function _onlyOracleManagerOrAdminOrEmergencyRole() internal view {
        if (
            !ROLES.hasRole(msg.sender, ORACLE_MANAGER_ROLE) &&
            !_isAdmin(msg.sender) &&
            !_isEmergency(msg.sender)
        ) {
            revert NotAuthorised();
        }
    }

    modifier onlyOracleManagerOrAdminRole() {
        _onlyOracleManagerOrAdminRole();
        _;
    }

    modifier onlyOracleManagerOrAdminOrEmergencyRole() {
        _onlyOracleManagerOrAdminOrEmergencyRole();
        _;
    }

    // ========== FACTORY FUNCTIONS ========== //

    /// @inheritdoc IERC7726OracleFactory
    function createOracle(
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
        if (!isCreationEnabled) revert ERC7726OracleFactory_CreationDisabled();
        if (_maxAgeToOracle[maxAge_] != address(0)) {
            revert ERC7726OracleFactory_OracleAlreadyExists(maxAge_);
        }

        bytes32 oracleName = _decodeOracleName(customParams_);
        bytes memory oracleData = abi.encodePacked(address(this), uint64(maxAge_), oracleName);
        oracle = address(ORACLE_IMPLEMENTATION).clone(oracleData);

        _oracles.push(oracle);
        _maxAgeToOracle[maxAge_] = oracle;
        _oracleToMaxAge[oracle] = maxAge_;
        isOracle[oracle] = true;
        _isOracleEnabled[oracle] = true;

        emit OracleCreated(oracle, maxAge_);
        emit OracleEnabled(oracle);
    }

    /// @inheritdoc IERC7726OracleFactory
    function getOracle(uint48 maxAge_) external view override returns (address oracle) {
        oracle = _maxAgeToOracle[maxAge_];
    }

    /// @inheritdoc IERC7726OracleFactory
    function getOracles() external view override returns (address[] memory oracles) {
        return _oracles;
    }

    /// @inheritdoc IERC7726OracleFactory
    function getPriceModule() external view override returns (address module) {
        return address(PRICE);
    }

    // ========== CREATION CONTROL ========== //

    /// @inheritdoc IERC7726OracleFactory
    function enableCreation()
        external
        override
        onlyEnabled
        onlyOracleManagerOrAdminRole
        nonReentrant
    {
        if (isCreationEnabled) revert ERC7726OracleFactory_CreationAlreadyEnabled();
        isCreationEnabled = true;
        emit CreationEnabled();
    }

    /// @inheritdoc IERC7726OracleFactory
    function disableCreation()
        external
        override
        onlyEnabled
        onlyOracleManagerOrAdminOrEmergencyRole
        nonReentrant
    {
        if (!isCreationEnabled) revert ERC7726OracleFactory_CreationAlreadyDisabled();
        isCreationEnabled = false;
        emit CreationDisabled();
    }

    // ========== ORACLE STATE ========== //

    /// @inheritdoc IERC7726OracleFactory
    function enableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrAdminRole nonReentrant {
        if (!isOracle[oracle_]) revert ERC7726OracleFactory_InvalidOracle(oracle_);
        if (_isOracleEnabled[oracle_]) revert ERC7726OracleFactory_OracleAlreadyEnabled(oracle_);

        _isOracleEnabled[oracle_] = true;
        emit OracleEnabled(oracle_);
    }

    /// @inheritdoc IERC7726OracleFactory
    function disableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrAdminOrEmergencyRole nonReentrant {
        if (!isOracle[oracle_]) revert ERC7726OracleFactory_InvalidOracle(oracle_);
        if (!_isOracleEnabled[oracle_]) {
            revert ERC7726OracleFactory_OracleAlreadyDisabled(oracle_);
        }

        _isOracleEnabled[oracle_] = false;
        emit OracleDisabled(oracle_);
    }

    /// @inheritdoc IERC7726OracleFactory
    function isOracleEnabled(address oracle_) external view override returns (bool enabled) {
        return isEnabled && isOracle[oracle_] && _isOracleEnabled[oracle_];
    }

    /// @inheritdoc IERC7726OracleFactory
    function cachePrices(address base_, address quote_) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        PRICE.cachePrice(base_);
        PRICE.cachePrice(quote_);
    }

    /// @inheritdoc IERC7726OracleFactory
    function cachePricesIfNecessary(
        address base_,
        address quote_,
        uint48 maxAge_
    ) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        (, uint48 baseTimestamp) = PRICE.getPrice(base_, IPRICEv2.Variant.LAST);
        (, uint48 quoteTimestamp) = PRICE.getPrice(quote_, IPRICEv2.Variant.LAST);
        bool timestampsDiffer = baseTimestamp != quoteTimestamp;
        bool baseStale = baseTimestamp == 0 ||
            block.timestamp > uint256(baseTimestamp) + uint256(maxAge_);
        bool quoteStale = quoteTimestamp == 0 ||
            block.timestamp > uint256(quoteTimestamp) + uint256(maxAge_);

        if (timestampsDiffer || baseStale || quoteStale) {
            PRICE.cachePrice(base_);
            PRICE.cachePrice(quote_);
        }
    }

    // ========== INTERNAL HELPERS ========== //

    function _decodeOracleName(
        bytes calldata customParams_
    ) internal pure returns (bytes32 oracleName) {
        if (customParams_.length == 0) return _DEFAULT_ORACLE_NAME;
        if (customParams_.length != 32) {
            revert ERC7726OracleFactory_InvalidCustomParams(customParams_.length);
        }

        return abi.decode(customParams_, (bytes32));
    }

    function _validateCachingCaller(address caller_) internal view {
        if (!isOracle[caller_]) revert ERC7726OracleFactory_InvalidOracle(caller_);
        if (!_isOracleEnabled[caller_]) revert ERC7726OracleFactory_OracleDisabled(caller_);
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IERC7726OracleFactory).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
