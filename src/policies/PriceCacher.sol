// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title Price Cacher
/// @notice Heart task that refreshes an admin-configured set of PriceCache pairs.
/// @dev Pair configuration is independent from every cache consumer.
///      Calls are not gas bounded. A cache call that consumes nearly all available gas can prevent
///      later pairs, later Heart tasks, or Heart finalization despite ordinary revert isolation.
contract PriceCacher is Policy, ReEnablerGracePeriod, PolicyEnablerV2, IPriceCacher, IVersioned {
    uint32 internal constant _INITIAL_REENABLE_GRACE_PERIOD = 7 days;

    IPriceCache internal _PRICE_CACHE;
    AssetPair[] internal _assetPairs;

    constructor(
        Kernel kernel_,
        IPriceCache priceCache_
    ) Policy(kernel_) ReEnablerGracePeriod(_INITIAL_REENABLE_GRACE_PERIOD) {
        _validatePriceCache(kernel_, address(priceCache_));
        _PRICE_CACHE = priceCache_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    /// @inheritdoc IPeriodicTask
    function execute() external override onlyRole(HEART_ROLE) {
        if (!isEnabled) return;

        try this.selfExecuteTask() {} catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            emit ExecutionFailed(bytes4(reason));
        }
    }

    /// @inheritdoc IPriceCacher
    function selfExecuteTask() external override {
        if (msg.sender != address(this)) revert PriceCacher_OnlySelf();

        address priceCache_ = address(_PRICE_CACHE);
        if (!kernel.isPolicyActive(Policy(priceCache_)) || !IEnabler(priceCache_).isEnabled())
            return;

        uint256 length = _assetPairs.length;
        for (uint256 i; i < length; ++i) {
            _cachePair(priceCache_, _assetPairs[i]);
        }
    }

    /// @inheritdoc IPriceCacher
    function setPriceCache(address priceCache_) external override onlyAdminRole {
        _validatePriceCache(kernel, priceCache_);
        IPriceCache candidate = IPriceCache(priceCache_);
        uint256 length = _assetPairs.length;
        for (uint256 i; i < length; ++i) {
            AssetPair memory pair = _assetPairs[i];
            // Each configured pair must remain valid on cache rotation.
            // forge-lint: disable-next-line(calls-loop)
            candidate.validateAssetPair(pair.asset, pair.quote);
        }
        _PRICE_CACHE = IPriceCache(priceCache_);
        emit PriceCacheSet(priceCache_);
    }

    /// @inheritdoc IPriceCacher
    function addAssetPair(address asset_, address quote_) external override onlyAdminRole {
        _validateAssetPair(asset_, quote_);
        if (_findAssetPair(asset_, quote_) != type(uint256).max) {
            revert PriceCacher_AssetPairAlreadyAdded(asset_, quote_);
        }
        _PRICE_CACHE.validateAssetPair(asset_, quote_);

        _assetPairs.push(AssetPair({asset: asset_, quote: quote_}));
        emit AssetPairAdded(asset_, quote_);
    }

    /// @inheritdoc IPriceCacher
    function removeAssetPair(address asset_, address quote_) external override onlyAdminRole {
        _validateAssetPair(asset_, quote_);
        uint256 index = _findAssetPair(asset_, quote_);
        if (index == type(uint256).max) revert PriceCacher_AssetPairNotFound(asset_, quote_);

        AssetPair memory removedPair = _assetPairs[index];
        uint256 lastIndex = _assetPairs.length - 1;
        if (index != lastIndex) _assetPairs[index] = _assetPairs[lastIndex];
        _assetPairs.pop();
        emit AssetPairRemoved(removedPair.asset, removedPair.quote);
    }

    /// @inheritdoc IPriceCacher
    function priceCache() external view override returns (address priceCache_) {
        return address(_PRICE_CACHE);
    }

    /// @inheritdoc IPriceCacher
    function getAssetPairs() external view override returns (AssetPair[] memory pairs) {
        return _assetPairs;
    }

    function _authorizeReEnable() internal view override onlyAdminRole {}

    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    function _beforeEnable(bytes calldata) internal view override {
        _validatePriceCache(kernel, address(_PRICE_CACHE));
    }

    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validatePriceCache(kernel, address(_PRICE_CACHE));
    }

    /// @inheritdoc IPeriodicTask
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IPriceCacher).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    function _validatePriceCache(Kernel kernel_, address priceCache_) private view {
        if (priceCache_ == address(0)) revert PriceCacher_ZeroAddress();

        bytes4[] memory interfaceIds = new bytes4[](3);
        interfaceIds[0] = type(IPriceCache).interfaceId;
        interfaceIds[1] = type(IEnabler).interfaceId;
        interfaceIds[2] = type(IVersioned).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(priceCache_, interfaceIds)) {
            revert PriceCacher_InvalidPriceCache(priceCache_);
        }

        (uint8 major, uint8 minor) = IVersioned(priceCache_).VERSION();
        if (major != 1) {
            revert PriceCacher_UnsupportedPriceCacheVersion(priceCache_, major, minor);
        }

        address priceCacheKernel = address(Policy(priceCache_).kernel());
        if (priceCacheKernel != address(kernel_)) {
            revert PriceCacher_PriceCacheKernelMismatch(address(kernel_), priceCacheKernel);
        }
    }

    function _validateAssetPair(address asset_, address quote_) private pure {
        if (asset_ == address(0) || quote_ == address(0) || asset_ == quote_) {
            revert PriceCacher_InvalidAssetPair();
        }
    }

    function _findAssetPair(address asset_, address quote_) private view returns (uint256 index) {
        uint256 length = _assetPairs.length;
        for (uint256 i; i < length; ++i) {
            AssetPair memory pair = _assetPairs[i];
            // PriceCache keys pairs independently of request direction, so reversed semantic
            // requests share one snapshot and must not be configured twice.
            if (
                (pair.asset == asset_ && pair.quote == quote_) ||
                (pair.asset == quote_ && pair.quote == asset_)
            ) return i;
        }
        return type(uint256).max;
    }

    function _cachePair(address priceCache_, AssetPair memory pair_) private {
        // External calls are the purpose of this governance-configured pair iteration.
        // forge-lint: disable-next-line(calls-loop)
        try IPriceCache(priceCache_).cachePriceIfNecessary(pair_.asset, pair_.quote, 0) returns (
            IPriceCache.CachedPrice memory
        ) {} catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            emit PairCacheFailed(priceCache_, pair_.asset, pair_.quote, bytes4(reason));
        }
    }
}
