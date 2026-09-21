// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// forge-lint: disable-start(missing-zero-check,multi-contract-file,empty-block,block-timestamp)

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

contract MockPriceCacherCache is Policy, IPriceCache, IEnabler, IERC165, IVersioned {
    error PairReverted(address asset, address quote);
    error PairUnsupported(address asset, address quote);

    uint8 internal constant _DECIMALS = 18;
    uint256 internal constant _PRICE = 1e18;
    uint48 internal constant _UPDATED_AT = 1;
    uint80 internal constant _ROUND_ID = 1;

    bool internal _isEnabled;
    bool public revertEnabledQuery;
    uint8 public versionMajor = 1;
    uint8 public versionMinor = 0;
    bool public supportsPriceCache = true;
    bool public supportsEnabler = true;
    bool public supportsVersioned = true;
    address public revertingAsset;
    address public revertingQuote;
    uint256 public callCount;
    address public lastAsset;
    address public lastQuote;
    uint48 public lastMaxAge;

    mapping(bytes32 pairKey => uint256 calls) public pairCallCount;
    mapping(bytes32 pairKey => bool unsupported) public unsupportedPair;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](0);
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    function setVersion(uint8 major_, uint8 minor_) external {
        versionMajor = major_;
        versionMinor = minor_;
    }

    function setInterfaceSupport(bool cache_, bool enabler_, bool versioned_) external {
        supportsPriceCache = cache_;
        supportsEnabler = enabler_;
        supportsVersioned = versioned_;
    }

    function setRevertingPair(address asset_, address quote_) external {
        revertingAsset = asset_;
        revertingQuote = quote_;
    }

    function setUnsupportedPair(address asset_, address quote_) external {
        unsupportedPair[keccak256(abi.encode(asset_, quote_))] = true;
    }

    function setRevertEnabledQuery(bool revert_) external {
        revertEnabledQuery = revert_;
    }

    function isEnabled() external view override returns (bool) {
        if (revertEnabledQuery) revert PairReverted(address(0), address(0));
        return _isEnabled;
    }

    function enable(bytes calldata) external override {
        _isEnabled = true;
        emit Enabled();
    }

    function disable(bytes calldata) external override {
        _isEnabled = false;
        emit Disabled();
    }

    function VERSION() external view override returns (uint8 major, uint8 minor) {
        return (versionMajor, versionMinor);
    }

    function cachePrice(address asset_, address quote_) external override {
        _record(asset_, quote_);
    }

    function cachePriceIfNecessary(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external override returns (CachedPrice memory cachedPrice) {
        _validateAssetPairSupport(asset_, quote_);
        if (asset_ == revertingAsset && quote_ == revertingQuote) {
            revert PairReverted(asset_, quote_);
        }

        _record(asset_, quote_);
        lastMaxAge = maxAge_;
        return
            CachedPrice({
                assetPriceUsd: _PRICE,
                quotePriceUsd: _PRICE,
                updatedAt: _UPDATED_AT,
                roundId: _ROUND_ID
            });
    }

    function _record(address asset_, address quote_) internal {
        ++callCount;
        ++pairCallCount[keccak256(abi.encode(asset_, quote_))];
        lastAsset = asset_;
        lastQuote = quote_;
    }

    function getCachedPrice(address, address) external pure override returns (CachedPrice memory) {}

    function isStale(address, address, uint48) external pure override returns (bool) {
        return true;
    }

    function decimals() external pure override returns (uint8) {
        return _DECIMALS;
    }

    function assetDecimals(address) external pure override returns (uint8) {
        return _DECIMALS;
    }

    function assetSymbol(address) external pure override returns (string memory) {
        return "MOCK";
    }

    function validateAssetPair(address asset_, address quote_) external view override {
        _validateAssetPairSupport(asset_, quote_);
    }

    function _validateAssetPairSupport(address asset_, address quote_) internal view {
        if (unsupportedPair[keccak256(abi.encode(asset_, quote_))]) {
            revert PairUnsupported(asset_, quote_);
        }
    }

    function setNonContractAssetMetadata(address, uint8, string calldata) external override {}

    function removeNonContractAssetMetadata(address) external override {}

    function supportsInterface(bytes4 interfaceId_) external view override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            (supportsPriceCache && interfaceId_ == type(IPriceCache).interfaceId) ||
            (supportsEnabler && interfaceId_ == type(IEnabler).interfaceId) ||
            (supportsVersioned && interfaceId_ == type(IVersioned).interfaceId);
    }
}

// forge-lint: disable-end(missing-zero-check,multi-contract-file,empty-block,block-timestamp)
