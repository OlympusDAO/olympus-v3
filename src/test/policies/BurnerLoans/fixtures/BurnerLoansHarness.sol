// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {Kernel} from "src/Kernel.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {BurnerLoans} from "src/policies/BurnerLoans.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

import {FullMath} from "src/libraries/FullMath.sol";
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {BurnerLoansCalculator} from "src/policies/libraries/BurnerLoansCalculator.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";
import {BurnerLoansSeizure} from "src/policies/libraries/BurnerLoansSeizure.sol";

contract BurnerLoansHarness is BurnerLoans {
    using SafeCast for uint256;

    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_,
        IOlympusBackingOracle backingOracle_
    ) BurnerLoans(kernel_, ohm_, depositManager_, backingOracle_) {}

    function floanForTest() external view returns (IFLOANv1) {
        return _FLOAN;
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
        return
            BurnerLoansCalculator.borrowFee(currentRequiredCollateral_, feeRateWad_) * termCount_;
    }

    function keeperRewardAsset(
        KeeperRewardInputs calldata inputs_
    ) external view returns (uint256) {
        IBurnerLoans.AssetConfig memory config;
        config.backingMultiplierBps = inputs_.backingMultiplierBps.toUint16();
        config.keeperRewardBps = inputs_.rewardBps.toUint16();
        config.collateralDecimals = inputs_.collateralDecimals;
        config.maxKeeperReward = inputs_.maxKeeperRewardAsset;
        BurnerLoansSeizure.Pricing memory pricing = BurnerLoansSeizure.Pricing({
            ohmUsdPrice: 0,
            backingPerOhmUsd: inputs_.backingPerOhmUsd,
            collateralUsdPrice: inputs_.collateralUsdPrice
        });
        return
            BurnerLoansSeizure._keeperReward(
                _OHM_DECIMALS,
                config,
                pricing,
                inputs_.seizedUnrepaidDebtOhm,
                inputs_.seizedCollateralAmount,
                inputs_.isProtocolSeizureCaller
            );
    }

    function setActiveDebtForTest(address asset_, uint256 assetActiveDebtOhm_) external {
        uint64 positionId = BurnerLoansPositions.getOrCreate(
            _FLOAN,
            _marketId(asset_),
            address(uint160(uint256(keccak256(abi.encode(asset_, "accounting")))))
        );
        IFLOANv1.Position memory position = _FLOAN.getPosition(positionId);
        uint256 marketDebt = _FLOAN.getMarketPrincipalDue(_marketId(asset_));
        uint256 positionDebt = position.principalDue;
        uint256 debtWithoutPosition = marketDebt - positionDebt;
        if (assetActiveDebtOhm_ < debtWithoutPosition) revert BurnerLoans_InvalidCap();
        uint256 targetPositionDebt = assetActiveDebtOhm_ - debtWithoutPosition;
        if (targetPositionDebt > positionDebt) {
            uint128 increase = (targetPositionDebt - positionDebt).toUint128();
            _FLOAN.increaseDebt(positionId, increase, 0, uint48(block.timestamp + 30 days));
            _INVENTORY.draw(address(this), increase);
        } else if (targetPositionDebt < positionDebt) {
            uint128 decrease = (positionDebt - targetPositionDebt).toUint128();
            _FLOAN.decreaseDebt(positionId, decrease, 0);
            _INVENTORY.recordDefault(decrease);
        }
    }

    function setPositionForTest(
        address asset_,
        address owner_,
        IBurnerLoans.Position memory position_
    ) external {
        uint64 positionId = BurnerLoansPositions.getOrCreate(_FLOAN, _marketId(asset_), owner_);
        IFLOANv1.Position memory current = _FLOAN.getPosition(positionId);
        if (position_.depositedCollateral > current.collateral) {
            _FLOAN.addCollateral(
                positionId,
                (position_.depositedCollateral - current.collateral).toUint128()
            );
        } else if (position_.depositedCollateral < current.collateral) {
            _FLOAN.removeCollateral(
                positionId,
                (current.collateral - position_.depositedCollateral).toUint128()
            );
        }
        if (position_.debtOhm > current.principalDue) {
            uint128 increase = (position_.debtOhm - current.principalDue).toUint128();
            _FLOAN.increaseDebt(positionId, increase, 0, position_.maturity);
            _INVENTORY.draw(address(this), increase);
        } else if (position_.debtOhm < current.principalDue) {
            uint128 decrease = (current.principalDue - position_.debtOhm).toUint128();
            _FLOAN.decreaseDebt(positionId, decrease, 0);
            _INVENTORY.recordDefault(decrease);
        }
        IFLOANv1.Position memory resulting = _FLOAN.getPosition(positionId);
        if (position_.debtOhm != 0 && position_.maturity > resulting.maturity) {
            _FLOAN.extendMaturity(positionId, position_.maturity);
        }
    }

    function PRICE() external view returns (IPRICEv2) {
        return _PRICE;
    }

    function TRSRY() external view returns (TRSRYv1) {
        return _TRSRY;
    }
}
