// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity ^0.8.15;

import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

contract MockPrice is PRICEv2 {
    address internal constant UNIT_OF_ACCOUNT = address(840);

    mapping(address => bool) internal assetApproved;
    mapping(address => bool) internal _storeMovingAverageEnabled;
    mapping(address => uint256) internal prices;
    mapping(address => uint256) internal movingAverages;
    mapping(address => uint48) internal _movingAverageLastUpdated;
    mapping(address => uint256[]) internal observations;
    uint48 internal timestamp;

    address[] internal _assets;

    constructor(Kernel kernel_, uint8 decimals_, uint32 observationFrequency_) PRICEv2(kernel_) {
        timestamp = uint48(block.timestamp);
        _observationFrequency = observationFrequency_;
        _decimals = decimals_;
    }

    // ========== KERNEL FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    // ========== FUNCTIONS ========== //

    function setTimestamp(uint48 timestamp_) public {
        timestamp = timestamp_;
    }

    function setPrice(address asset, uint256 price) public {
        assetApproved[asset] = true;
        prices[asset] = price;

        // Add to the assets array
        bool exists = false;
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == asset) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            _assets.push(asset);
        }
    }

    function setMovingAverage(address asset, uint256 movingAverage) public {
        _storeMovingAverageEnabled[asset] = true;
        movingAverages[asset] = movingAverage;
        _movingAverageLastUpdated[asset] = timestamp;
    }

    function _isUnitOfAccount(address asset_) internal pure returns (bool) {
        return asset_ == UNIT_OF_ACCOUNT;
    }

    function _unitPrice() internal view returns (uint256) {
        return 10 ** _decimals;
    }

    function setObservations(address asset, uint256[] memory observations_) public {
        _storeMovingAverageEnabled[asset] = true;
        observations[asset] = observations_;
        _movingAverageLastUpdated[asset] = observations_.length == 0 ? uint48(0) : timestamp;
    }

    function _getLastObservationPrice(
        address asset_
    ) internal view returns (uint256 price_, uint48 timestamp_) {
        if (!_storeMovingAverageEnabled[asset_]) revert PRICE_MovingAverageNotStored(asset_);

        uint256[] memory assetObservations = observations[asset_];
        if (assetObservations.length == 0) revert PRICE_MovingAverageNotStored(asset_);

        return (assetObservations[assetObservations.length - 1], _movingAverageLastUpdated[asset_]);
    }

    function _getMovingAveragePrice(
        address asset
    ) internal view returns (uint256 price_, uint48 timestamp_) {
        if (!_storeMovingAverageEnabled[asset]) revert PRICE_MovingAverageNotStored(asset);

        uint256[] memory assetObservations = observations[asset];
        if (assetObservations.length == 0) revert PRICE_MovingAverageNotStored(asset);

        uint256 movingAverage = movingAverages[asset];
        if (movingAverage == 0) {
            uint256 cumulativeObs;
            for (uint256 i; i < assetObservations.length; ) {
                cumulativeObs += assetObservations[i];
                unchecked {
                    ++i;
                }
            }
            movingAverage = cumulativeObs / assetObservations.length;
        }

        return (movingAverage, _movingAverageLastUpdated[asset]);
    }

    function getPrice(address asset_) external view override returns (uint256) {
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);
        return price;
    }

    function getPrice(
        address asset_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (_isUnitOfAccount(asset_)) {
            if (variant_ == Variant.MOVINGAVERAGE) revert PRICE_MovingAverageNotStored(asset_);
            return (_unitPrice(), timestamp);
        }

        // Mimic PRICE's behaviour of reverting if the asset is not approved
        if (!assetApproved[asset_]) revert PRICE_AssetNotApproved(asset_);

        uint256 price;
        uint48 priceTimestamp;
        if (variant_ == Variant.CURRENT) {
            price = prices[asset_];
            priceTimestamp = timestamp;
        } else if (variant_ == Variant.LAST) {
            (price, priceTimestamp) = _getLastObservationPrice(asset_);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            (price, priceTimestamp) = _getMovingAveragePrice(asset_);
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }

        // Mimic PRICE's behaviour of reverting
        if (price == 0) {
            revert PRICE_PriceZero(asset_);
        }

        return (price, priceTimestamp);
    }

    function getPriceIn(address asset_, address base_) external view override returns (uint256) {
        (uint256 price, ) = getPriceIn(asset_, base_, Variant.CURRENT);
        return price;
    }

    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        if (asset_ == base_) return (_unitPrice(), timestamp);

        (uint256 assetPrice, uint48 assetTimestamp) = getPrice(asset_, variant_);
        (uint256 basePrice, uint48 baseTimestamp) = getPrice(base_, variant_);

        return (
            (assetPrice * 10 ** _decimals) / basePrice,
            assetTimestamp < baseTimestamp ? assetTimestamp : baseTimestamp
        );
    }

    function setPriceDecimals(uint8 decimals_) public {
        _decimals = decimals_;
    }

    function getAssets() external view override returns (address[] memory) {
        return _assets;
    }

    function getAssetData(address asset_) external view override returns (Asset memory) {
        uint256[] memory assetObservations = observations[asset_];
        return
            Asset({
                approved: assetApproved[asset_],
                storeMovingAverage: _storeMovingAverageEnabled[asset_],
                useMovingAverage: false,
                movingAverageDuration: 30 days,
                nextObsIndex: 0,
                numObservations: uint16(assetObservations.length),
                lastObservationTime: _movingAverageLastUpdated[asset_],
                cumulativeObs: 0,
                obs: assetObservations,
                strategy: bytes(""),
                feeds: bytes("")
            });
    }

    function isAssetApproved(address asset_) external view override returns (bool) {
        return assetApproved[asset_];
    }

    function registerNonContractAsset(address asset_) external override {
        _registerNonContractAsset(asset_);
    }

    function unregisterNonContractAsset(address asset_) external override {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);
        if (!isNonContractAsset[asset_]) revert PRICE_InvalidAsset(asset_);
        if (assetApproved[asset_]) revert PRICE_AssetAlreadyApproved(asset_);

        delete isNonContractAsset[asset_];
    }

    function storeObservation(address asset_) external override {
        if (!assetApproved[asset_]) revert PRICE_AssetNotApproved(asset_);
        if (!_storeMovingAverageEnabled[asset_]) revert PRICE_MovingAverageNotStored(asset_);

        // Get current price
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);

        observations[asset_].push(price);
        _movingAverageLastUpdated[asset_] = timestamp;

        uint256 cumulativeObs;
        uint256[] memory assetObservations = observations[asset_];
        for (uint256 i; i < assetObservations.length; ) {
            cumulativeObs += assetObservations[i];
            unchecked {
                ++i;
            }
        }
        movingAverages[asset_] = cumulativeObs / assetObservations.length;

        // Emit both events to match PRICEv2 behavior
        emit PriceStored(asset_, price, timestamp);
    }

    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        Component memory strategy_,
        Component[] memory feeds_
    ) external override {
        assetApproved[asset_] = true;
        _storeMovingAverageEnabled[asset_] = storeMovingAverage_;
        observations[asset_] = observations_;
        _movingAverageLastUpdated[asset_] = lastObservationTime_;

        uint256 cumulativeObs;
        for (uint256 i; i < observations_.length; ) {
            cumulativeObs += observations_[i];
            unchecked {
                ++i;
            }
        }
        movingAverages[asset_] = observations_.length == 0
            ? 0
            : cumulativeObs / observations_.length;

        bool exists;
        for (uint256 i; i < _assets.length; ) {
            if (_assets[i] == asset_) {
                exists = true;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (!exists) _assets.push(asset_);

        useMovingAverage_;
        movingAverageDuration_;
        strategy_;
        feeds_;
    }

    function removeAsset(address asset_) external override {
        assetApproved[asset_] = false;
        _storeMovingAverageEnabled[asset_] = false;
        delete movingAverages[asset_];
        delete _movingAverageLastUpdated[asset_];
        delete observations[asset_];

        // Keep getAssets()/storeObservations() aligned with asset approval state.
        for (uint256 i; i < _assets.length; ) {
            if (_assets[i] == asset_) {
                _assets[i] = _assets[_assets.length - 1];
                _assets.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function updateAsset(address asset_, UpdateAssetParams memory params_) external override {
        if (params_.updateMovingAverage) {
            _storeMovingAverageEnabled[asset_] = params_.storeMovingAverage;
            observations[asset_] = params_.observations;
            _movingAverageLastUpdated[asset_] = params_.lastObservationTime;

            uint256 cumulativeObs;
            for (uint256 i; i < params_.observations.length; ) {
                cumulativeObs += params_.observations[i];
                unchecked {
                    ++i;
                }
            }
            movingAverages[asset_] = params_.observations.length == 0
                ? 0
                : cumulativeObs / params_.observations.length;
        }
    }

    function storeObservations() external virtual override {
        // Iterate over all assets
        for (uint256 i = 0; i < _assets.length; i++) {
            address asset = _assets[i];
            if (asset == address(0)) continue;

            getPrice(asset, Variant.CURRENT);
        }
    }
}
/// forge-lint: disable-end(mixed-case-function)
