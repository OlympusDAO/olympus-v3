// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
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

    IPRICEv2 public PRICE;

    struct PairSnapshot {
        uint256 token0PriceUsd;
        uint256 token1PriceUsd;
        uint48 updatedAt;
        uint80 roundId;
    }

    uint256 internal _cacheEpoch;
    mapping(uint256 epoch => mapping(bytes32 key => PairSnapshot snapshot)) internal _pairSnapshot;

    // ========== CONSTRUCTOR ========== //

    constructor(Kernel kernel_) Policy(kernel_) {}

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

    // ========== CACHE FUNCTIONS ========== //

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if dependencies are not configured and the PRICE module is unset.
    function decimals() external view override returns (uint8 decimals_) {
        return PRICE.decimals();
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - The pair is invalid (zero address or identical tokens)
    ///             - Either non-unit asset in the pair is not approved in PRICE
    ///             - PRICE cannot return a current USD price for either token
    function cachePrice(address asset_, address quote_) public override onlyEnabled {
        _validatePair(asset_, quote_);

        (uint256 assetPriceUsd, uint48 assetTimestamp) = _getPriceOrUnit(asset_);
        (uint256 quotePriceUsd, uint48 quoteTimestamp) = _getPriceOrUnit(quote_);
        uint48 updatedAt = assetTimestamp < quoteTimestamp ? assetTimestamp : quoteTimestamp;

        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        PairSnapshot storage snapshot = _pairSnapshot[_cacheEpoch][key];

        if (assetIsToken0) {
            snapshot.token0PriceUsd = assetPriceUsd;
            snapshot.token1PriceUsd = quotePriceUsd;
        } else {
            snapshot.token0PriceUsd = quotePriceUsd;
            snapshot.token1PriceUsd = assetPriceUsd;
        }

        snapshot.updatedAt = updatedAt;
        snapshot.roundId++;
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The policy is disabled
    ///             - Pair validation fails while evaluating staleness
    ///             - PRICE cannot serve required data when a recache is needed
    function cachePriceIfNecessary(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external override onlyEnabled {
        if (isStale(asset_, quote_, maxAge_)) {
            cachePrice(asset_, quote_);
        }
    }

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if:
    ///             - The pair is invalid (zero address or identical tokens)
    ///             - Either non-unit asset in the pair is not approved in PRICE
    function getCachedPrice(
        address asset_,
        address quote_
    ) public view override returns (CachedPrice memory cachedPrice) {
        _validatePair(asset_, quote_);

        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        PairSnapshot memory snapshot = _pairSnapshot[_cacheEpoch][key];

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

    /// @inheritdoc IPriceCache
    /// @dev        Reverts if pair validation fails in `getCachedPrice`.
    function isStale(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) public view override returns (bool stale) {
        CachedPrice memory cachedPrice = getCachedPrice(asset_, quote_);
        return
            cachedPrice.updatedAt == 0 ||
            block.timestamp > uint256(cachedPrice.updatedAt) + uint256(maxAge_);
    }

    // ========== INTERNAL HELPERS ========== //

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
