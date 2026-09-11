// SPDX-License-Identifier: AGPL-3.0-only
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Bophades
import {Kernel, Policy, Keycode, toKeycode, Permissions, Module} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title  PriceCache
/// @author OlympusDAO
/// @notice Permissionless pair cache policy for approved PRICE assets
contract PriceCache is Policy, PolicyEnabler, IPriceCache, IVersioned {
    // ========== STATE ========== //

    bytes5 internal constant _PRICE_KEYCODE = "PRICE";
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";
    bytes32 internal constant _PRICE_ADMIN_ROLE = "price_admin";
    uint256 internal constant _MAX_SYMBOL_LENGTH = 32;

    IPRICEv2 public PRICE;
    uint8 internal immutable _UNIT_OF_ACCOUNT_DECIMALS;
    bytes32 internal immutable _UNIT_OF_ACCOUNT_SYMBOL;

    uint256 internal _cacheEpoch;
    mapping(address asset => IPriceCache.NonContractAssetMetadata metadata)
        internal _nonContractAssetMetadata;
    mapping(address asset => uint64 epoch) internal _assetEpoch;
    mapping(uint256 epoch => mapping(bytes32 key => IPriceCache.PairSnapshot snapshot))
        internal _pairSnapshot;

    // ========== CONSTRUCTOR ========== //

    constructor(
        Kernel kernel_,
        uint8 unitOfAccountDecimals_,
        string memory unitOfAccountSymbol_
    ) Policy(kernel_) {
        _UNIT_OF_ACCOUNT_DECIMALS = unitOfAccountDecimals_;
        _validateSymbol(unitOfAccountSymbol_);
        _UNIT_OF_ACCOUNT_SYMBOL = _stringToBytes32(unitOfAccountSymbol_);
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev        Reverts if:
    ///             - The configured PRICE module version is unsupported
    ///             - The configured PRICE module does not implement IPRICEv2
    ///             - The configured ROLES module major version is unsupported
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

    /// @notice Reverts unless the caller has the `price_admin` or `admin` role.
    /// @dev    Reverts with `PolicyAdmin.NotAuthorised()` if the caller lacks both roles.
    function _onlyPriceOrAdminRole() internal view {
        if (!ROLES.hasRole(msg.sender, _PRICE_ADMIN_ROLE) && !_isAdmin(msg.sender)) {
            revert NotAuthorised();
        }
    }

    /// @notice Modifier that reverts unless the caller has the `price_admin` or `admin` role.
    modifier onlyPriceOrAdminRole() {
        _onlyPriceOrAdminRole();
        _;
    }

    // ========== CACHE FUNCTIONS ========== //

    /// @notice Reverts if this policy is not active in the Kernel.
    modifier onlyPolicyActive() {
        _onlyPolicyActive();
        _;
    }

    function _onlyPolicyActive() internal view {
        if (!kernel.isPolicyActive(this)) revert IPriceCache.PriceCache_PolicyNotActive();
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if dependencies are not configured and the PRICE module is unset.
    function decimals() external view override returns (uint8 decimals_) {
        return PRICE.decimals();
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - `asset_` is a non-contract asset that is not known to PRICE
    ///             - `asset_` is a non-contract asset without registered decimals
    function assetDecimals(address asset_) external view override returns (uint8 decimals_) {
        return _assetDecimals(asset_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - `asset_` is a non-contract asset that is not known to PRICE
    ///             - `asset_` is a non-contract asset without registered symbol metadata
    function assetSymbol(address asset_) external view override returns (string memory symbol_) {
        return _assetSymbol(asset_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The caller is neither `price_admin` nor `admin`
    ///             - `asset_` is not a valid non-contract asset managed by PRICE
    ///             - `symbol_` is empty or exceeds the configured max length
    function setNonContractAssetMetadata(
        address asset_,
        uint8 decimals_,
        string calldata symbol_
    ) external override onlyEnabled onlyPriceOrAdminRole {
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
    ///             - `asset_` is the unit of account
    ///             - `asset_` does not have registered metadata
    function removeNonContractAssetMetadata(
        address asset_
    ) external override onlyEnabled onlyPriceOrAdminRole {
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
    ///             - PRICE cannot return a current USD price for either token
    function cachePrice(
        address asset_,
        address quote_
    ) public override onlyPolicyActive onlyEnabled {
        _cachePrice(asset_, quote_);
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is deactivated in Kernel
    ///             - The policy is disabled
    ///             - Pair validation fails while evaluating staleness
    ///             - PRICE cannot serve required data when a recache is needed
    function cachePriceIfNecessary(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external override onlyPolicyActive onlyEnabled {
        if (_isStale(asset_, quote_, maxAge_)) {
            _cachePrice(asset_, quote_);
        }
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
    ) public view override onlyPolicyActive onlyEnabled returns (CachedPrice memory cachedPrice) {
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
    ) public view override onlyPolicyActive onlyEnabled returns (bool stale) {
        return _isStale(asset_, quote_, maxAge_);
    }

    // ========== INTERNAL HELPERS ========== //

    function _cachePrice(address asset_, address quote_) internal {
        _validatePair(asset_, quote_);
        _validatePairDecimals(asset_, quote_);

        (uint256 assetPriceUsd, uint48 assetTimestamp) = _getPriceOrUnit(asset_);
        (uint256 quotePriceUsd, uint48 quoteTimestamp) = _getPriceOrUnit(quote_);
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
    }

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

    function _isStale(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) internal view returns (bool stale) {
        CachedPrice memory cachedPrice = _getCachedPrice(asset_, quote_);
        return
            cachedPrice.updatedAt == 0 ||
            block.timestamp > uint256(cachedPrice.updatedAt) + uint256(maxAge_);
    }

    function _isUnitOfAccount(address asset_) internal view returns (bool) {
        return asset_ == PRICE.unitOfAccount();
    }

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
    /// @dev    Reverts if `_assetDecimals(asset_)` or `_assetDecimals(quote_)` reverts.
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
    ///         - `asset_` is a contract whose `decimals()` call reverts
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
    ///         - `asset_` is a contract whose `symbol()` call reverts
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
    /// @dev    Reverts if `PRICE.unitOfAccount()` reverts because dependencies are not configured.
    ///
    /// @param asset_    Non-contract asset identifier
    /// @return bool     True if `asset_` is known to PRICE
    function _isKnownNonContractAsset(address asset_) internal view returns (bool) {
        if (asset_ == PRICE.unitOfAccount()) return true;
        return PRICE.isNonContractAsset(asset_);
    }

    /// @notice Return whether an asset can have non-contract metadata configured in the cache
    /// @dev    This is intended for admin-managed non-contract asset metadata registration paths.
    /// @dev    Reverts if `_isKnownNonContractAsset(asset_)` reverts because PRICE dependencies are not
    ///         configured.
    ///
    /// @param asset_    Asset identifier
    /// @return bool     True if `asset_` is a non-contract asset known to PRICE
    function _isConfigurableNonContractAsset(address asset_) internal view returns (bool) {
        return asset_.code.length == 0 && _isKnownNonContractAsset(asset_);
    }

    /// @notice Register the unit-of-account metadata in the cache if it has not been set yet
    /// @dev    This is used only during dependency configuration to seed the initial unit-of-account
    ///         metadata without overwriting a later admin update on replayed `configureDependencies()`.
    /// @dev    Reverts if `PRICE.unitOfAccount()` reverts because the PRICE module is not configured.
    function _registerUnitOfAccountMetadataIfMissing() internal {
        address unitOfAccount = PRICE.unitOfAccount();
        if (_nonContractAssetMetadata[unitOfAccount].registered) return;

        _nonContractAssetMetadata[unitOfAccount] = IPriceCache.NonContractAssetMetadata({
            registered: true,
            decimals: _UNIT_OF_ACCOUNT_DECIMALS,
            symbol: _bytes32ToString(_UNIT_OF_ACCOUNT_SYMBOL)
        });
    }

    /// @notice Validate a non-contract asset symbol before it is stored
    /// @dev    Reverts if `symbol_` is empty or exceeds `_MAX_SYMBOL_LENGTH`.
    function _validateSymbol(string memory symbol_) internal pure {
        uint256 symbolLength = bytes(symbol_).length;
        if (symbolLength == 0 || symbolLength > _MAX_SYMBOL_LENGTH) {
            revert IPriceCache.PriceCache_InvalidAssetSymbol();
        }
    }

    /// @notice Convert a <=32 byte string into a bytes32 word for immutable storage
    function _stringToBytes32(string memory value_) internal pure returns (bytes32 result_) {
        assembly {
            result_ := mload(add(value_, 32))
        }
    }

    /// @notice Convert a zero-padded bytes32 word back into a string
    function _bytes32ToString(bytes32 value_) internal pure returns (string memory result_) {
        uint256 length;
        while (length < 32 && value_[length] != 0) {
            unchecked {
                ++length;
            }
        }

        bytes memory buffer = new bytes(length);
        for (uint256 i; i < length; ) {
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
    ///
    /// @param asset_    Asset identifier whose cached pairs should be invalidated
    function _invalidateAsset(address asset_) internal {
        unchecked {
            _assetEpoch[asset_]++;
        }
    }

    function _getPriceOrUnit(
        address asset_
    ) internal view returns (uint256 price_, uint48 timestamp_) {
        if (_isUnitOfAccount(asset_)) {
            return (10 ** PRICE.decimals(), uint48(block.timestamp));
        }

        return PRICE.getPrice(asset_, IPRICEv2.Variant.CURRENT);
    }

    function _pairKey(
        address asset_,
        address quote_
    ) internal pure returns (bytes32 key_, bool assetIsToken0_) {
        if (asset_ < quote_) {
            return (keccak256(abi.encodePacked(asset_, quote_)), true);
        }

        return (keccak256(abi.encodePacked(quote_, asset_)), false);
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_    The interface identifier, as specified in ERC-165
    /// @return bool            True if the contract implements `interfaceId_`
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IPriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
