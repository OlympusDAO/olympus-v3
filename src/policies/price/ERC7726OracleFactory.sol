// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Bophades
import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";
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

    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    /// @notice The pair cache policy
    IPriceCache public priceCache;

    /// @notice Reference implementation for cloning
    ERC7726OracleCloneable public immutable ORACLE_IMPLEMENTATION;

    /// @notice Whether new oracle creation is enabled
    bool public isCreationEnabled;

    /// @notice Internal array of all deployed oracles
    address[] internal _oracles;

    /// @notice Number of deployed oracles that are currently enabled
    /// @dev    Updated when oracles are created, enabled, or disabled. Factory-level re-enable
    ///         recaching skips all requested pairs when this count is zero.
    uint256 internal _enabledOracleCount;

    /// @notice Mapping from maxAge to oracle
    mapping(uint48 maxAge => address oracle) internal _maxAgeToOracle;

    /// @notice Mapping from oracle to maxAge
    mapping(address oracle => uint48 maxAge) internal _oracleToMaxAge;

    /// @notice Mapping to validate deployed oracles
    mapping(address oracle => bool) public isOracle;

    /// @notice Mapping to track if an oracle is enabled
    mapping(address oracle => bool) internal _isOracleEnabled;

    bytes32 internal constant _DEFAULT_ORACLE_NAME = "ERC7726 Oracle";

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructs a new ERC7726OracleFactory
    /// @dev    Reverts if `priceCache_` is not a valid IPriceCache policy for this Kernel.
    ///
    /// @param  kernel_     The Kernel address
    /// @param  priceCache_ The price cache policy address
    constructor(Kernel kernel_, address priceCache_) Policy(kernel_) {
        ORACLE_IMPLEMENTATION = new ERC7726OracleCloneable();
        isCreationEnabled = true;
        _setPriceCache(priceCache_);
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev        Reverts if the configured ROLES module major version is unsupported.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode(_ROLES_KEYCODE);
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

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
    /// @dev        Does not revert.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    /// @dev        Does not revert.
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
    /// @dev        Creates an enabled oracle and adds it to the factory-level re-enable recache count.
    ///
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not admin or oracle manager
    ///             - Oracle creation is disabled
    ///             - An oracle for `maxAge_` already exists
    ///             - `customParams_` is non-empty and not exactly 32 bytes
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
        ++_enabledOracleCount;

        emit OracleCreated(oracle, maxAge_);
        emit OracleEnabled(oracle);
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Does not revert.
    function getOracle(uint48 maxAge_) external view override returns (address oracle) {
        oracle = _maxAgeToOracle[maxAge_];
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Does not revert.
    function getOracles() external view override returns (address[] memory oracles) {
        return _oracles;
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Does not revert.
    function getPriceCache() external view override returns (address policy) {
        return address(priceCache);
    }

    // ========== CREATION CONTROL ========== //

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        `enableCreation()` sets `isCreationEnabled` to true. It does not update the
    ///             enabled-oracle counter or perform recaching logic.
    ///
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
        if (isCreationEnabled) revert ERC7726OracleFactory_CreationAlreadyEnabled();
        isCreationEnabled = true;
        emit CreationEnabled();
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        `disableCreation()` sets `isCreationEnabled` to false. It does not update the
    ///             enabled-oracle counter or perform recaching logic.
    ///
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
        if (!isCreationEnabled) revert ERC7726OracleFactory_CreationAlreadyDisabled();
        isCreationEnabled = false;
        emit CreationDisabled();
    }

    /// @inheritdoc IERC7726OracleFactory
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

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not admin or oracle manager
    ///             - `oracle_` is not a factory-created oracle
    ///             - `oracle_` is already enabled
    function enableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrAdminRole nonReentrant {
        if (!isOracle[oracle_]) revert ERC7726OracleFactory_InvalidOracle(oracle_);
        if (_isOracleEnabled[oracle_]) revert ERC7726OracleFactory_OracleAlreadyEnabled(oracle_);

        _isOracleEnabled[oracle_] = true;
        ++_enabledOracleCount;
        emit OracleEnabled(oracle_);
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not admin, oracle manager, or emergency
    ///             - `oracle_` is not a factory-created oracle
    ///             - `oracle_` is already disabled
    function disableOracle(
        address oracle_
    ) external override onlyEnabled onlyOracleManagerOrAdminOrEmergencyRole nonReentrant {
        if (!isOracle[oracle_]) revert ERC7726OracleFactory_InvalidOracle(oracle_);
        if (!_isOracleEnabled[oracle_]) {
            revert ERC7726OracleFactory_OracleAlreadyDisabled(oracle_);
        }

        _isOracleEnabled[oracle_] = false;
        --_enabledOracleCount;
        emit OracleDisabled(oracle_);
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Does not revert.
    function isOracleEnabled(address oracle_) external view override returns (bool enabled) {
        return isEnabled && isOracle[oracle_] && _isOracleEnabled[oracle_];
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not a factory-created oracle
    ///             - The caller oracle is disabled
    ///             - Underlying cache write fails
    function cachePrice(address base_, address quote_) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        priceCache.cachePrice(base_, quote_);
    }

    /// @inheritdoc IERC7726OracleFactory
    /// @dev        Reverts if:
    ///             - The factory is disabled
    ///             - The caller is not a factory-created oracle
    ///             - The caller oracle is disabled
    ///             - Underlying cache evaluation/write fails
    function cachePriceIfNecessary(
        address base_,
        address quote_
    ) external override onlyEnabled nonReentrant {
        _validateCachingCaller(msg.sender);
        uint48 configuredMaxAge = _oracleToMaxAge[msg.sender];
        priceCache.cachePriceIfNecessary(base_, quote_, configuredMaxAge);
    }

    /// @inheritdoc PolicyEnabler
    /// @dev        `_enable` optionally re-caches caller-specified pairs from `enableData_` before
    ///             the factory-level `isEnabled` flag flips to true. `enableData_` can be empty for
    ///             a no-op. Requested pairs are only recached when at least one ERC-7726 oracle
    ///             variant is enabled; otherwise all requested pairs are skipped because disabled
    ///             clones cannot request fresh cache writes until they are individually re-enabled.
    ///
    ///             When `enableData_` is non-empty, it must encode:
    ///             `(address[] baseTokens, address[] quoteTokens)`.
    ///
    ///             Reverts if `enableData_` is non-empty and:
    ///             - `enableData_` cannot be decoded into `(address[] baseTokens, address[] quoteTokens)`
    ///             - The decoded base and quote token arrays have different lengths
    ///             - The price cache rejects a requested pair during recaching
    function _enable(bytes calldata enableData_) internal override {
        if (enableData_.length == 0) return;

        (address[] memory baseTokens, address[] memory quoteTokens) = abi.decode(
            enableData_,
            (address[], address[])
        );
        uint256 pairCount = baseTokens.length;
        if (pairCount != quoteTokens.length) {
            revert ERC7726OracleFactory_InvalidEnableData(pairCount, quoteTokens.length);
        }

        if (!_hasEnabledOracleVariant()) return;

        for (uint256 i; i < pairCount; ) {
            priceCache.cachePrice(baseTokens[i], quoteTokens[i]);

            unchecked {
                ++i;
            }
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

    function _hasEnabledOracleVariant() internal view returns (bool) {
        return _enabledOracleCount != 0;
    }

    function _setPriceCache(address policy_) internal {
        if (policy_ == address(0) || !_implementsIPriceCache(policy_) || !_hasSameKernel(policy_)) {
            revert ERC7726OracleFactory_InvalidPriceCache(policy_);
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

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_    The interface identifier, as specified in ERC-165
    /// @return bool            True if the contract implements `interfaceId_`
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IERC7726OracleFactory).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
