// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {Kernel, Policy, Keycode, toKeycode, Permissions, Module} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title  PriceCache
/// @author OlympusDAO
/// @notice Permissionless pair cache policy for approved PRICE assets
contract PriceCache is Policy, ReEnablerGracePeriod, PolicyEnablerV2, IPriceCache, IVersioned {
    // ========== STATE ========== //

    /// @notice Keycode used to resolve the price module from the Kernel.
    bytes5 internal constant _PRICE_KEYCODE = "PRICE";

    /// @notice Keycode used to resolve the authorization module from the Kernel.
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    /// @notice Role permitted to manage non-contract asset metadata alongside admin.
    bytes32 internal constant _PRICE_ADMIN_ROLE = "price_admin";

    /// @notice Maximum asset-symbol length in bytes.
    uint256 internal constant _MAX_SYMBOL_LENGTH = 32;

    /// @notice Initial re-enable grace window in seconds.
    uint32 internal constant _REENABLE_GRACE_PERIOD = 7 days;

    /// @notice Current price module supplying approved assets and USD observations.
    IPRICEv2 public PRICE;

    /// @notice Constructor-configured amount-decimal scale for the unit of account.
    uint8 internal immutable _UNIT_OF_ACCOUNT_DECIMALS;

    /// @notice Constructor-configured unit-of-account symbol packed into one word.
    bytes32 internal immutable _UNIT_OF_ACCOUNT_SYMBOL;

    /// @notice Exact symbol length in bytes, preserving embedded zero bytes on decoding.
    uint8 internal immutable _UNIT_OF_ACCOUNT_SYMBOL_LENGTH;

    /// @notice Snapshot namespace advanced when the configured PRICE module changes.
    uint256 internal _cacheEpoch;

    /// @notice Registered decimals and symbols for non-contract asset identifiers.
    mapping(address asset => IPriceCache.NonContractAssetMetadata metadata)
        internal _nonContractAssetMetadata;

    /// @notice Invalidation generation advanced when an asset's registered metadata changes.
    mapping(address asset => uint64 epoch) internal _assetEpoch;

    /// @notice Pair snapshots by PRICE-module epoch and canonical unordered-pair key.
    mapping(uint256 epoch => mapping(bytes32 key => IPriceCache.PairSnapshot snapshot))
        internal _pairSnapshot;

    // ========== CONSTRUCTOR ========== //

    /// @notice Configures the Kernel, unit-of-account metadata and initial re-enable window.
    /// @dev Reverts if:
    ///      - The symbol is empty or exceeds 32 bytes (PriceCache_InvalidAssetSymbol).
    ///
    /// @param kernel_ Kernel supplying PRICE and ROLES.
    /// @param unitOfAccountDecimals_ Amount-decimal scale of the unit of account.
    /// @param unitOfAccountSymbol_ Unit-of-account symbol, including any embedded zero bytes.
    constructor(
        Kernel kernel_,
        uint8 unitOfAccountDecimals_,
        string memory unitOfAccountSymbol_
    ) Policy(kernel_) ReEnablerGracePeriod(_REENABLE_GRACE_PERIOD) {
        _UNIT_OF_ACCOUNT_DECIMALS = unitOfAccountDecimals_;
        _validateSymbol(unitOfAccountSymbol_);
        _UNIT_OF_ACCOUNT_SYMBOL = _stringToBytes32(unitOfAccountSymbol_);
        _UNIT_OF_ACCOUNT_SYMBOL_LENGTH = SafeCast.toUint8(bytes(unitOfAccountSymbol_).length);
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev        Reverts if:
    ///             - PRICE or ROLES is not installed in the Kernel (Policy_ModuleDoesNotExist)
    ///             - The configured PRICE module version is unsupported
    ///             - The configured PRICE module does not implement IPRICEv2
    ///             - The configured ROLES module major version is unsupported
    ///             - A module version/interface getter or PRICE.unitOfAccount() fails or returns malformed data
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode(_PRICE_KEYCODE);
        dependencies[1] = toKeycode(_ROLES_KEYCODE);

        address priceModule = getModuleAddress(dependencies[0]);
        (uint8 major, uint8 minor) = Module(priceModule).VERSION();
        if ((major == 1 && minor < 2) || major < 1) {
            revert IPriceCache.PriceCache_UnsupportedModuleVersion(_PRICE_KEYCODE, major, minor);
        }
        if (!IERC165(priceModule).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert IPriceCache.PriceCache_UnsupportedModuleInterface(
                _PRICE_KEYCODE,
                type(IPRICEv2).interfaceId
            );
        }

        if (address(PRICE) != address(0) && address(PRICE) != priceModule) {
            unchecked {
                _cacheEpoch++;
            }
        }

        PRICE = IPRICEv2(priceModule);
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 rolesMajor, uint8 rolesMinor) = ROLES.VERSION();
        if (rolesMajor != 1) {
            revert IPriceCache.PriceCache_UnsupportedModuleVersion(
                _ROLES_KEYCODE,
                rolesMajor,
                rolesMinor
            );
        }

        _registerUnitOfAccountMetadataIfMissing();
    }

    /// @inheritdoc Policy
    /// @dev        Does not revert.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    /// @dev        Does not revert.
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    // ========== MODIFIERS ========== //

    /// @notice Requires price administration or governance authority.
    /// @dev Reverts if:
    ///      - The caller lacks both roles (NotAuthorised).
    function _onlyPriceOrAdminRole() internal view {
        if (!ROLES.hasRole(msg.sender, _PRICE_ADMIN_ROLE) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    /// @notice Requires price administration or governance authority.
    /// @dev Reverts if:
    ///      - The caller holds neither price_admin nor admin.
    modifier onlyPriceOrAdminRole() {
        _onlyPriceOrAdminRole();
        _;
    }

    // ========== CACHE FUNCTIONS ========== //

    /// @notice Requires own Kernel activity.
    /// @dev Reverts if:
    ///      - This policy is not active in the Kernel.
    modifier onlyPolicyActive() {
        _onlyPolicyActive();
        _;
    }

    /// @notice Requires this policy to remain active in its Kernel.
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive (PriceCache_PolicyNotActive).
    function _onlyPolicyActive() internal view {
        if (!kernel.isPolicyActive(this)) revert IPriceCache.PriceCache_PolicyNotActive();
    }

    /// @inheritdoc IPriceCache
    /// @dev Reverts if:
    ///      - PRICE.decimals() fails or returns malformed data, including when PRICE is unset.
    function decimals() external view override returns (uint8 decimals_) {
        return PRICE.decimals();
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - `asset_` is a non-contract asset that is not known to PRICE
    ///             - `asset_` is a non-contract asset without registered decimals
    ///             - A required PRICE or contract-token getter reverts or returns malformed data
    function assetDecimals(address asset_) external view override returns (uint8 decimals_) {
        return _assetDecimals(asset_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - `asset_` is a non-contract asset that is not known to PRICE
    ///             - `asset_` is a non-contract asset without registered symbol metadata
    ///             - A required PRICE or contract-token getter reverts or returns malformed data
    function assetSymbol(address asset_) external view override returns (string memory symbol_) {
        return _assetSymbol(asset_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The pair is invalid (zero address or identical tokens)
    ///             - Either non-unit asset in the pair is not approved in PRICE
    ///             - Either asset's decimals cannot be resolved
    function validateAssetPair(address asset_, address quote_) external view override {
        _validatePair(asset_, quote_);
        _validatePairDecimals(asset_, quote_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - The policy is deactivated in Kernel
    ///             - `asset_` is not a valid non-contract asset managed by PRICE
    ///             - `symbol_` is empty or exceeds the configured max length
    function setNonContractAssetMetadata(
        address asset_,
        uint8 decimals_,
        string calldata symbol_
    ) external override onlyPolicyActive givenEnabled onlyPriceOrAdminRole {
        if (!_isConfigurableNonContractAsset(asset_)) {
            revert IPriceCache.PriceCache_InvalidAsset(asset_);
        }

        _validateSymbol(symbol_);

        IPriceCache.NonContractAssetMetadata storage metadata = _nonContractAssetMetadata[asset_];
        if (
            !metadata.registered ||
            metadata.decimals != decimals_ ||
            keccak256(bytes(metadata.symbol)) != keccak256(bytes(symbol_))
        ) {
            metadata.registered = true;
            metadata.decimals = decimals_;
            metadata.symbol = symbol_;
            _invalidateAsset(asset_);
        }
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - The policy is deactivated in Kernel
    ///             - `asset_` is the unit of account
    ///             - `asset_` does not have registered metadata
    function removeNonContractAssetMetadata(
        address asset_
    ) external override onlyPolicyActive givenEnabled onlyPriceOrAdminRole {
        if (asset_ == PRICE.unitOfAccount()) {
            revert IPriceCache.PriceCache_InvalidAsset(asset_);
        }

        if (!_nonContractAssetMetadata[asset_].registered) {
            revert IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered(asset_);
        }

        delete _nonContractAssetMetadata[asset_];
        _invalidateAsset(asset_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is deactivated in Kernel
    ///             - The policy is disabled
    ///             - The pair is invalid (zero address or identical tokens)
    ///             - Either non-unit asset in the pair is not approved in PRICE
    ///             - Pair decimals cannot be resolved
    ///             - PRICE cannot return a current USD price for either token
    ///             - The pair's uint80 round counter overflows
    function cachePrice(
        address asset_,
        address quote_
    ) public override onlyPolicyActive givenEnabled {
        _cachePrice(asset_, quote_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is deactivated in Kernel
    ///             - The policy is disabled
    ///             - Pair validation fails while evaluating staleness
    ///             - PRICE cannot serve required data when a recache is needed
    ///             - A recache overflows the pair's uint80 round counter
    function cachePriceIfNecessary(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external override onlyPolicyActive givenEnabled returns (CachedPrice memory cachedPrice) {
        cachedPrice = _getCachedPrice(asset_, quote_);
        if (_isStale(cachedPrice, maxAge_)) {
            return _cachePrice(asset_, quote_);
        }

        return cachedPrice;
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is deactivated in Kernel
    ///             - The policy is disabled
    ///             - The pair is invalid (zero address or identical tokens)
    ///             - Either non-unit asset in the pair is not approved in PRICE
    ///             - Pair decimals validation fails
    /// @dev        Returns a fully zeroed `CachedPrice` when the stored snapshot was invalidated by a
    ///             later non-contract decimals update or removal for either asset in the pair.
    function getCachedPrice(
        address asset_,
        address quote_
    ) public view override onlyPolicyActive givenEnabled returns (CachedPrice memory cachedPrice) {
        return _getCachedPrice(asset_, quote_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is deactivated in Kernel
    ///             - The policy is disabled
    ///             - Pair validation fails in `getCachedPrice`
    function isStale(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) public view override onlyPolicyActive givenEnabled returns (bool stale) {
        return _isStale(_getCachedPrice(asset_, quote_), maxAge_);
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Refreshes a pair snapshot and advances its round counter in the current epoch.
    /// @dev Reverts if:
    ///      - Pair shape, PRICE approval or decimal metadata validation fails.
    ///      - PRICE cannot serve a current observation or a unit price cannot fit in uint256.
    ///      - The pair's uint80 round counter overflows.
    ///
    /// @param asset_ Asset in requested orientation.
    /// @param quote_ Quote in requested orientation.
    /// @return cachedPrice Refreshed prices, oldest observation time and new round in requested orientation.
    function _cachePrice(
        address asset_,
        address quote_
    ) internal returns (CachedPrice memory cachedPrice) {
        _validatePair(asset_, quote_);
        _validatePairDecimals(asset_, quote_);

        (uint256 assetPriceUsd, uint48 assetTimestamp) = _getPriceOrUnit(asset_);
        (uint256 quotePriceUsd, uint48 quoteTimestamp) = _getPriceOrUnit(quote_);
        // The unit-of-account leg deliberately uses the current block time as its observation.
        // forge-lint: disable-next-line(block-timestamp)
        uint48 updatedAt = assetTimestamp < quoteTimestamp ? assetTimestamp : quoteTimestamp;

        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        IPriceCache.PairSnapshot storage snapshot = _pairSnapshot[_cacheEpoch][key];
        // Record the current per-asset invalidation epochs so a later decimals update/removal can
        // invalidate this cached pair without enumerating stored pairs.
        uint64 assetEpoch = _assetEpoch[asset_];
        uint64 quoteEpoch = _assetEpoch[quote_];

        if (assetIsToken0) {
            snapshot.token0PriceUsd = assetPriceUsd;
            snapshot.token1PriceUsd = quotePriceUsd;
            snapshot.token0Epoch = assetEpoch;
            snapshot.token1Epoch = quoteEpoch;
        } else {
            snapshot.token0PriceUsd = quotePriceUsd;
            snapshot.token1PriceUsd = assetPriceUsd;
            snapshot.token0Epoch = quoteEpoch;
            snapshot.token1Epoch = assetEpoch;
        }

        snapshot.updatedAt = updatedAt;
        snapshot.roundId++;

        cachedPrice.assetPriceUsd = assetPriceUsd;
        cachedPrice.quotePriceUsd = quotePriceUsd;
        cachedPrice.updatedAt = updatedAt;
        cachedPrice.roundId = snapshot.roundId;
    }

    /// @notice Reads the current pair snapshot, returning zeros if its asset epochs were invalidated.
    /// @dev Reverts if:
    ///      - Pair shape, PRICE approval or decimal metadata validation fails.
    ///
    /// @param asset_ Asset in requested orientation.
    /// @param quote_ Quote in requested orientation.
    /// @return cachedPrice Stored snapshot in requested orientation, or zeros when absent or invalidated.
    function _getCachedPrice(
        address asset_,
        address quote_
    ) internal view returns (CachedPrice memory cachedPrice) {
        _validatePair(asset_, quote_);
        _validatePairDecimals(asset_, quote_);

        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        IPriceCache.PairSnapshot memory snapshot = _pairSnapshot[_cacheEpoch][key];
        bool pairIsInvalidated;

        if (assetIsToken0) {
            pairIsInvalidated =
                snapshot.token0Epoch != _assetEpoch[asset_] ||
                snapshot.token1Epoch != _assetEpoch[quote_];
        } else {
            pairIsInvalidated =
                snapshot.token0Epoch != _assetEpoch[quote_] ||
                snapshot.token1Epoch != _assetEpoch[asset_];
        }

        if (pairIsInvalidated) {
            // Return the zero-initialized cachedPrice so callers treat the pair as uncached/stale.
            return cachedPrice;
        }

        if (assetIsToken0) {
            cachedPrice.assetPriceUsd = snapshot.token0PriceUsd;
            cachedPrice.quotePriceUsd = snapshot.token1PriceUsd;
        } else {
            cachedPrice.assetPriceUsd = snapshot.token1PriceUsd;
            cachedPrice.quotePriceUsd = snapshot.token0PriceUsd;
        }

        cachedPrice.updatedAt = snapshot.updatedAt;
        cachedPrice.roundId = snapshot.roundId;
    }

    /// @notice Compares an observation time with the inclusive maximum-age boundary.
    /// @dev Revert conditions: none; the timestamp addition is widened to uint256.
    ///
    /// @param cachedPrice_ Snapshot whose observation time is checked.
    /// @param maxAge_ Maximum acceptable age in seconds.
    /// @return stale True when the snapshot is absent or older than maxAge_.
    function _isStale(
        CachedPrice memory cachedPrice_,
        uint48 maxAge_
    ) internal view returns (bool stale) {
        return
            cachedPrice_.updatedAt == 0 ||
            // A cache's age must be compared with the current block time.
            // forge-lint: disable-next-line(block-timestamp)
            block.timestamp > uint256(cachedPrice_.updatedAt) + uint256(maxAge_);
    }

    /// @notice Identifies the current PRICE unit of account.
    /// @dev Reverts if:
    ///      - PRICE.unitOfAccount() fails or returns malformed data, including when PRICE is unset.
    ///
    /// @param asset_ Asset identifier to compare.
    /// @return bool True when the asset is the unit of account.
    function _isUnitOfAccount(address asset_) internal view returns (bool) {
        return asset_ == PRICE.unitOfAccount();
    }

    /// @notice Validates distinct nonzero pair legs and PRICE approval of non-unit assets.
    /// @dev Reverts if:
    ///      - A leg is zero or both legs are identical (PriceCache_InvalidPair).
    ///      - A non-unit asset is not approved (PRICE_AssetNotApproved).
    ///      - A required PRICE getter fails or returns malformed data.
    ///
    /// @param asset_ Asset in requested orientation.
    /// @param quote_ Quote in requested orientation.
    function _validatePair(address asset_, address quote_) internal view {
        if (asset_ == address(0) || quote_ == address(0) || asset_ == quote_) {
            revert IPriceCache.PriceCache_InvalidPair(asset_, quote_);
        }

        if (!_isUnitOfAccount(asset_) && !PRICE.isAssetApproved(asset_)) {
            revert IPRICEv2.PRICE_AssetNotApproved(asset_);
        }
        if (!_isUnitOfAccount(quote_) && !PRICE.isAssetApproved(quote_)) {
            revert IPRICEv2.PRICE_AssetNotApproved(quote_);
        }
    }

    /// @notice Validate that both legs in a pair have resolvable cache metadata
    /// @dev Reverts if:
    ///      - Decimal metadata resolution fails for either pair leg in _assetDecimals.
    ///
    /// @param asset_    Asset in requested orientation
    /// @param quote_    Quote in requested orientation
    function _validatePairDecimals(address asset_, address quote_) internal view {
        _assetDecimals(asset_);
        _assetDecimals(quote_);
    }

    /// @notice Resolve the amount-decimal scale for an asset identifier
    /// @dev    Contract assets source decimals from `IERC20.decimals()`. Non-contract assets must be
    ///         known to PRICE and have registered metadata in this cache.
    /// @dev    Reverts if:
    ///         - `asset_` is a non-contract asset that is not registered in PRICE
    ///         - `asset_` is a registered non-contract asset without cache decimals
    ///         - A required PRICE or contract-token getter reverts or returns malformed data
    ///
    /// @param asset_        Asset identifier
    /// @return decimals_    Amount-decimal scale for `asset_`
    function _assetDecimals(address asset_) internal view returns (uint8 decimals_) {
        if (asset_.code.length != 0) {
            return IERC20(asset_).decimals();
        }

        if (!_isKnownNonContractAsset(asset_)) {
            revert IPriceCache.PriceCache_NonContractAssetNotRegistered(asset_);
        }

        IPriceCache.NonContractAssetMetadata memory metadata = _nonContractAssetMetadata[asset_];
        if (!metadata.registered) {
            revert IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered(asset_);
        }

        return metadata.decimals;
    }

    /// @notice Resolve the symbol for an asset identifier
    /// @dev    Contract assets source symbols from `IERC20.symbol()`. Non-contract assets must be
    ///         known to PRICE and have registered symbol metadata in this cache.
    /// @dev    Reverts if:
    ///         - `asset_` is a non-contract asset that is not registered in PRICE
    ///         - `asset_` is a registered non-contract asset without cache symbol metadata
    ///         - A required PRICE or contract-token getter reverts or returns malformed data
    ///
    /// @param asset_      Asset identifier
    /// @return symbol_    Symbol for `asset_`
    function _assetSymbol(address asset_) internal view returns (string memory symbol_) {
        if (asset_.code.length != 0) {
            return IERC20(asset_).symbol();
        }

        if (!_isKnownNonContractAsset(asset_)) {
            revert IPriceCache.PriceCache_NonContractAssetNotRegistered(asset_);
        }

        IPriceCache.NonContractAssetMetadata memory metadata = _nonContractAssetMetadata[asset_];
        if (!metadata.registered) {
            revert IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered(asset_);
        }

        return metadata.symbol;
    }

    /// @notice Return whether a non-contract asset identifier is known to PRICE
    /// @dev    Returns true for PRICE's configured unit of account. All other non-contract assets must
    ///         be explicitly registered in PRICE.
    /// @dev Reverts if:
    ///      - A required PRICE getter fails or returns malformed data, including when PRICE is unset.
    ///
    /// @param asset_    Non-contract asset identifier
    /// @return bool     True if `asset_` is known to PRICE
    function _isKnownNonContractAsset(address asset_) internal view returns (bool) {
        if (asset_ == PRICE.unitOfAccount()) return true;
        return PRICE.isNonContractAsset(asset_);
    }

    /// @notice Return whether an asset can have non-contract metadata configured in the cache
    /// @dev    This is intended for admin-managed non-contract asset metadata registration paths.
    /// @dev Reverts if:
    ///      - Non-contract lookup reaches a PRICE getter that fails or returns malformed data.
    ///
    /// @param asset_    Asset identifier
    /// @return bool     True if `asset_` is a non-contract asset known to PRICE
    function _isConfigurableNonContractAsset(address asset_) internal view returns (bool) {
        return asset_.code.length == 0 && _isKnownNonContractAsset(asset_);
    }

    /// @notice Register the unit-of-account metadata in the cache if it has not been set yet
    /// @dev    This is used only during dependency configuration to seed the initial unit-of-account
    ///         metadata without overwriting a later admin update on replayed `configureDependencies()`.
    /// @dev Reverts if:
    ///      - PRICE.unitOfAccount() fails or returns malformed data, including when PRICE is unset.
    function _registerUnitOfAccountMetadataIfMissing() internal {
        address unitOfAccount = PRICE.unitOfAccount();
        if (_nonContractAssetMetadata[unitOfAccount].registered) return;

        _nonContractAssetMetadata[unitOfAccount] = IPriceCache.NonContractAssetMetadata({
            registered: true,
            decimals: _UNIT_OF_ACCOUNT_DECIMALS,
            symbol: _bytes32ToString(_UNIT_OF_ACCOUNT_SYMBOL, _UNIT_OF_ACCOUNT_SYMBOL_LENGTH)
        });
    }

    /// @notice Validate a non-contract asset symbol before it is stored
    /// @dev Reverts if:
    ///      - The symbol is empty or exceeds 32 bytes (PriceCache_InvalidAssetSymbol).
    function _validateSymbol(string memory symbol_) internal pure {
        uint256 symbolLength = bytes(symbol_).length;
        if (symbolLength == 0 || symbolLength > _MAX_SYMBOL_LENGTH) {
            revert IPriceCache.PriceCache_InvalidAssetSymbol();
        }
    }

    /// @notice Convert a <=32 byte string into a bytes32 word for immutable storage
    /// @dev Revert conditions: none. Callers validate the symbol length before packing.
    ///
    /// @param value_ Constructor-validated symbol.
    /// @return result_ Packed symbol bytes, padded with zeros.
    function _stringToBytes32(string memory value_) internal pure returns (bytes32 result_) {
        bytes memory valueBytes = bytes(value_);
        for (uint256 i; i < valueBytes.length; ++i) {
            result_ |= bytes32(valueBytes[i]) >> (i * 8);
        }
    }

    /// @notice Convert a bytes32 word back into its exact constructor-validated string length.
    /// @dev Reverts if:
    ///      - length_ exceeds 32 (array bounds panic); constructor validation prevents this.
    ///
    /// @param value_ Packed constructor symbol.
    /// @param length_ Exact constructor-validated symbol length in bytes.
    /// @return result_ Symbol with its original length and bytes.
    function _bytes32ToString(
        bytes32 value_,
        uint8 length_
    ) internal pure returns (string memory result_) {
        bytes memory buffer = new bytes(length_);
        for (uint256 i; i < length_; ) {
            buffer[i] = value_[i];
            unchecked {
                ++i;
            }
        }

        return string(buffer);
    }

    /// @notice Invalidate cached pairs involving `asset_` by advancing its epoch
    /// @dev    Use this after changing or removing non-contract asset decimals so future reads treat
    ///         existing snapshots as uncached.
    /// @dev    Revert conditions: none; the epoch increment is unchecked.
    ///
    /// @param asset_    Asset identifier whose cached pairs should be invalidated
    function _invalidateAsset(address asset_) internal {
        unchecked {
            _assetEpoch[asset_]++;
        }
    }

    /// @notice Resolves a current USD observation or the unit-of-account price at the current time.
    /// @dev Reverts if:
    ///      - A required PRICE getter fails or returns malformed data.
    ///      - The unit price, 10 ** PRICE.decimals(), overflows uint256.
    ///
    /// @param asset_ Asset identifier to price.
    /// @return price_ USD price using PRICE.decimals() decimal places.
    /// @return timestamp_ Source observation time, or the current time for the unit of account.
    function _getPriceOrUnit(
        address asset_
    ) internal view returns (uint256 price_, uint48 timestamp_) {
        if (_isUnitOfAccount(asset_)) {
            // Current chain timestamps fit in uint48 for over eight million years.
            // forge-lint: disable-next-line(unsafe-typecast)
            return (10 ** PRICE.decimals(), uint48(block.timestamp));
        }

        return PRICE.getPrice(asset_, IPRICEv2.Variant.CURRENT);
    }

    /// @notice Derives one storage key shared by both orientations of a pair.
    /// @dev Revert conditions: none.
    ///
    /// @param asset_ Asset in requested orientation.
    /// @param quote_ Quote in requested orientation.
    /// @return key_ Hash of the pair in ascending address order.
    /// @return assetIsToken0_ True when asset_ is the lower-sorted address.
    function _pairKey(
        address asset_,
        address quote_
    ) internal pure returns (bytes32 key_, bool assetIsToken0_) {
        assetIsToken0_ = asset_ < quote_;
        key_ = assetIsToken0_
            ? keccak256(abi.encodePacked(asset_, quote_))
            : keccak256(abi.encodePacked(quote_, asset_));
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_    The interface identifier, as specified in ERC-165
    /// @return bool            True if the contract implements `interfaceId_`
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IPriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty (PriceCache_InvalidData).
    ///      - This policy is Kernel-inactive (PriceCache_PolicyInactive).
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert PriceCache_InvalidData();
        if (!kernel.isPolicyActive(this)) revert PriceCache_PolicyInactive();
    }

    /// @inheritdoc EnablerV2
    /// @dev Inactive policies remain pausable. Reverts if:
    ///      - Lifecycle data is nonempty (PriceCache_InvalidData).
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert PriceCache_InvalidData();
    }

    /// @notice Authorizes bounded re-enablement by price admin or governance.
    /// @dev Reverts if:
    ///      - The caller holds neither price_admin nor admin (NotAuthorised).
    function _authorizeReEnable() internal view override onlyPriceOrAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override onlyPolicyActive {
        super.setGracePeriod(period_);
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN_ROLE (ROLES_RequireRole).
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Revalidates own membership after history, authorization and grace checks.
    ///      Reverts if:
    ///      - The widened grace deadline exceeds uint48 (SafeCastOverflowedUintDowncast).
    ///      - The current timestamp exceeds the inclusive deadline (GracePeriod_Expired).
    ///      - This policy is Kernel-inactive (PriceCache_PolicyInactive).
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        if (!kernel.isPolicyActive(this)) revert PriceCache_PolicyInactive();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The widened deadline exceeds uint48 (SafeCastOverflowedUintDowncast).
    ///      - The current timestamp exceeds the inclusive deadline (GracePeriod_Expired).
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
