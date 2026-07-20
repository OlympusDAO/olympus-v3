// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {Kernel} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {BurnerLoans} from "src/policies/BurnerLoans.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

import {FullMath} from "src/libraries/FullMath.sol";
import {BurnerLoansCalculator} from "src/policies/libraries/BurnerLoansCalculator.sol";

contract BurnerLoansHarness is BurnerLoans {
    IBurnerLoansConfig internal _testConfig;

    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) BurnerLoans(kernel_, ohm_, depositManager_) {}

    function setConfigForTest(IBurnerLoansConfig config_) external {
        _testConfig = config_;
    }

    function floanForTest() external view returns (IFLOANv1) {
        return _FLOAN;
    }

    function addAsset(
        address asset_,
        uint256 debtCapOhm_,
        IBurnerLoans.AssetRiskConfigInput calldata riskConfig_,
        IBurnerLoans.AssetFeeConfig calldata feeConfig_
    ) external {
        if (debtCapOhm_ > type(uint128).max) revert BurnerLoans_InvalidCap();
        _testConfig.addAsset(address(this), asset_, uint128(debtCapOhm_), riskConfig_, feeConfig_);
    }

    function getAssetConfig(
        address asset_
    ) external view returns (IBurnerLoans.AssetConfig memory) {
        return _testConfig.getAssetConfig(address(this), asset_);
    }

    function getAssetFeeConfig(
        address asset_
    ) external view returns (IBurnerLoans.AssetFeeConfig memory) {
        return _testConfig.getAssetFeeConfig(address(this), asset_);
    }

    function isAssetConfigured(address asset_) external view returns (bool) {
        return _testConfig.isAssetConfigured(address(this), asset_);
    }

    function marketId(address asset_) external view returns (uint32) {
        return _testConfig.marketId(address(this), asset_);
    }

    function enableAsset(address asset_) external {
        _testConfig.enableAsset(address(this), asset_);
    }

    function disableAsset(address asset_) external {
        _testConfig.disableAsset(address(this), asset_);
    }

    function setAssetDebtCap(address asset_, uint256 debtCapOhm_) external {
        if (debtCapOhm_ > type(uint128).max) revert BurnerLoans_InvalidCap();
        _testConfig.setAssetDebtCap(address(this), asset_, uint128(debtCapOhm_));
    }

    function setAssetRiskConfig(
        address asset_,
        IBurnerLoans.AssetRiskConfigInput calldata config_
    ) external {
        _testConfig.setAssetRiskConfig(address(this), asset_, config_);
    }

    function setAssetFeeConfig(
        address asset_,
        IBurnerLoans.AssetFeeConfig calldata config_
    ) external {
        _testConfig.setAssetFeeConfig(address(this), asset_, config_);
    }

    function setConfigurator(address configurator_) external {
        _testConfig.setConfigurator(configurator_);
    }

    function configurator() external view returns (address) {
        return _testConfig.configurator();
    }

    function validateAssetDebtCap(address asset_, uint256 debtCapOhm_) external view {
        if (debtCapOhm_ > type(uint128).max) revert BurnerLoans_InvalidCap();
        _testConfig.validateAssetDebtCap(address(this), asset_, uint128(debtCapOhm_));
    }

    function validateAssetRiskConfig(IBurnerLoans.AssetConfig calldata config_) external view {
        _testConfig.validateAssetRiskConfig(config_);
    }

    function validateFeeConfig(IBurnerLoans.AssetFeeConfig calldata config_) external view {
        _testConfig.validateFeeConfig(config_);
    }

    function debtValueUsd(
        uint256 debtOhm_,
        uint256 ohmUsdPrice_,
        uint8 ohmDecimals_
    ) external pure returns (uint256) {
        if (ohmUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return BurnerLoansCalculator.debtValueUsd(debtOhm_, ohmUsdPrice_, ohmDecimals_);
    }

    function collateralValueUsd(
        uint256 collateralAmount_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) external pure returns (uint256) {
        if (collateralUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return
            BurnerLoansCalculator.collateralValueUsd(
                collateralAmount_,
                collateralUsdPrice_,
                collateralDecimals_
            );
    }

    function riskAdjustedCollateralUsd(
        uint256 collateralValueUsd_,
        uint256 collateralFactorBps_
    ) external pure returns (uint256) {
        return
            BurnerLoansCalculator.riskAdjustedCollateralUsd(
                collateralValueUsd_,
                collateralFactorBps_
            );
    }

    function requiredBackingUsd(
        uint256 debtOhm_,
        uint256 backingPerOhmUsd_,
        uint8 ohmDecimals_,
        uint256 backingMultiplierBps_
    ) external pure returns (uint256) {
        if (backingPerOhmUsd_ == 0) revert BurnerLoans_InvalidPrice();
        return
            BurnerLoansCalculator.requiredBackingUsd(
                debtOhm_,
                backingPerOhmUsd_,
                ohmDecimals_,
                backingMultiplierBps_
            );
    }

    function requiredCollateralUsd(
        RequiredCollateralUsdInputs calldata inputs_
    ) external view returns (uint256) {
        return
            BurnerLoansCalculator.requiredCollateralUsd(
                inputs_.debtValueUsd,
                inputs_.debtOhm,
                inputs_.backingPerOhmUsd,
                _OHM_DECIMALS,
                inputs_.minCollateralRatioBps,
                inputs_.backingMultiplierBps
            );
    }

    function requiredCollateralAsset(
        uint256 requiredCollateralUsd_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) external pure returns (uint256) {
        if (collateralUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return
            BurnerLoansCalculator.requiredCollateralAsset(
                requiredCollateralUsd_,
                collateralUsdPrice_,
                collateralDecimals_
            );
    }

    function healthFactor(
        uint256 riskAdjustedCollateralUsd_,
        uint256 requiredCollateralUsd_
    ) external pure returns (uint256) {
        return
            BurnerLoansCalculator.healthFactor(riskAdjustedCollateralUsd_, requiredCollateralUsd_);
    }

    function utilizationBps(uint256 debt_, uint256 cap_) external pure returns (uint256) {
        if (cap_ == 0) {
            if (debt_ == 0) return 0;
            revert BurnerLoans_InvalidCap();
        }
        return FullMath.mulDivUp(debt_, _BPS, cap_);
    }

    function assetUtilizationWad(uint256 debt_, uint256 cap_) external pure returns (uint256) {
        uint256 utilization = BurnerLoansCalculator.assetUtilizationWad(debt_, cap_);
        if (utilization == type(uint256).max) revert BurnerLoans_InvalidCap();
        return utilization;
    }

    function effectiveUtilizationWad(
        UtilizationInputs calldata inputs_
    ) external pure returns (uint256) {
        uint256 utilization = BurnerLoansCalculator.assetUtilizationWad(
            inputs_.assetDebtOhm,
            inputs_.assetDebtCapOhm
        );
        if (utilization == type(uint256).max) revert BurnerLoans_InvalidCap();
        return utilization;
    }

    function feeRateWad(
        uint256 utilizationWad_,
        IBurnerLoans.AssetFeeConfig memory feeConfig_
    ) external pure returns (uint256) {
        if (utilizationWad_ > _WAD) revert BurnerLoans_InvalidParam();
        return
            BurnerLoansCalculator.feeRateWad(
                utilizationWad_,
                feeConfig_.baseFeeBps,
                feeConfig_.kinkBps,
                feeConfig_.preKinkSlopeBps,
                feeConfig_.postKinkSlopeBps
            );
    }

    function borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) external pure returns (uint256) {
        return BurnerLoansCalculator.borrowFee(incrementalRequiredCollateral_, feeRateWad_);
    }

    function extensionFee(
        uint256 currentRequiredCollateral_,
        uint256 feeRateWad_,
        uint256 termCount_
    ) external pure returns (uint256) {
        return FullMath.mulDivUp(currentRequiredCollateral_, feeRateWad_, _WAD) * termCount_;
    }

    function keeperRewardAsset(
        KeeperRewardInputs calldata inputs_
    ) external view returns (uint256) {
        if (
            inputs_.isProtocolSeizureCaller ||
            inputs_.rewardBps == 0 ||
            inputs_.maxKeeperRewardAsset == 0
        ) return 0;

        uint256 configuredReward = FullMath.mulDiv(
            inputs_.seizedCollateralAmount,
            inputs_.rewardBps,
            _BPS
        );
        if (configuredReward > inputs_.maxKeeperRewardAsset) {
            configuredReward = inputs_.maxKeeperRewardAsset;
        }
        uint256 backingRequirementUsd = BurnerLoansCalculator.requiredBackingUsd(
            inputs_.seizedUnrepaidDebtOhm,
            inputs_.backingPerOhmUsd,
            _OHM_DECIMALS,
            inputs_.backingMultiplierBps
        );
        uint256 requiredBackingAsset = BurnerLoansCalculator.requiredCollateralAsset(
            backingRequirementUsd,
            inputs_.collateralUsdPrice,
            inputs_.collateralDecimals
        );
        uint256 surplus = inputs_.seizedCollateralAmount > requiredBackingAsset
            ? inputs_.seizedCollateralAmount - requiredBackingAsset
            : 0;
        return configuredReward < surplus ? configuredReward : surplus;
    }

    function setActiveDebtForTest(address asset_, uint256, uint256 assetActiveDebtOhm_) external {
        uint64 positionId = _FLOAN.getOrCreatePosition(
            _marketId(asset_),
            address(uint160(uint256(keccak256(abi.encode(asset_, "accounting")))))
        );
        IFLOANv1.Position memory position = _FLOAN.getPosition(positionId);
        uint256 marketDebt = _FLOAN.marketPrincipalDue(_marketId(asset_));
        uint256 positionDebt = position.principalDue;
        uint256 debtWithoutPosition = marketDebt - positionDebt;
        if (assetActiveDebtOhm_ < debtWithoutPosition) revert BurnerLoans_InvalidCap();
        uint256 targetPositionDebt = assetActiveDebtOhm_ - debtWithoutPosition;
        if (targetPositionDebt > positionDebt) {
            _FLOAN.increaseDebt(
                positionId,
                uint128(targetPositionDebt - positionDebt),
                0,
                uint48(block.timestamp + 30 days)
            );
        } else if (targetPositionDebt < positionDebt) {
            _FLOAN.decreaseDebt(positionId, uint128(positionDebt - targetPositionDebt), 0);
        }
    }

    function setPositionForTest(
        address asset_,
        address owner_,
        IBurnerLoans.Position memory position_
    ) external {
        uint64 positionId = _FLOAN.getOrCreatePosition(_marketId(asset_), owner_);
        IFLOANv1.Position memory current = _FLOAN.getPosition(positionId);
        if (position_.depositedCollateral > current.collateral) {
            _FLOAN.addCollateral(
                positionId,
                uint128(position_.depositedCollateral - current.collateral)
            );
        } else if (position_.depositedCollateral < current.collateral) {
            _FLOAN.removeCollateral(
                positionId,
                uint128(current.collateral - position_.depositedCollateral)
            );
        }
        if (position_.debtOhm > current.principalDue) {
            _FLOAN.increaseDebt(
                positionId,
                uint128(position_.debtOhm - current.principalDue),
                0,
                position_.maturity
            );
        } else if (position_.debtOhm < current.principalDue) {
            _FLOAN.decreaseDebt(positionId, uint128(current.principalDue - position_.debtOhm), 0);
        }
    }

    function MINTR() external view returns (MINTRv1) {
        return _MINTR;
    }

    function PRICE() external view returns (IPRICEv2) {
        return _PRICE;
    }

    function TRSRY() external view returns (TRSRYv1) {
        return _TRSRY;
    }
}
