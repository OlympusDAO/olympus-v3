// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {Kernel} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {BurnerLoans} from "src/policies/BurnerLoans.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

contract BurnerLoansHarness is BurnerLoans {
    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) BurnerLoans(kernel_, ohm_, depositManager_) {}

    function debtValueUsd(
        uint256 debtOhm_,
        uint256 ohmUsdPrice_,
        uint8 ohmDecimals_
    ) external pure returns (uint256) {
        return _debtValueUsd(debtOhm_, ohmUsdPrice_, ohmDecimals_);
    }

    function collateralValueUsd(
        uint256 collateralAmount_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) external pure returns (uint256) {
        return _collateralValueUsd(collateralAmount_, collateralUsdPrice_, collateralDecimals_);
    }

    function riskAdjustedCollateralUsd(
        uint256 collateralValueUsd_,
        uint256 collateralFactorBps_
    ) external pure returns (uint256) {
        return _riskAdjustedCollateralUsd(collateralValueUsd_, collateralFactorBps_);
    }

    function requiredBackingUsd(
        uint256 debtOhm_,
        uint256 backingPerOhmUsd_,
        uint8 ohmDecimals_,
        uint256 backingMultiplierBps_
    ) external pure returns (uint256) {
        return
            _requiredBackingUsd(debtOhm_, backingPerOhmUsd_, ohmDecimals_, backingMultiplierBps_);
    }

    function requiredCollateralUsd(
        RequiredCollateralUsdInputs calldata inputs_
    ) external pure returns (uint256) {
        return _requiredCollateralUsd(inputs_);
    }

    function requiredCollateralAsset(
        uint256 requiredCollateralUsd_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) external pure returns (uint256) {
        return
            _requiredCollateralAsset(
                requiredCollateralUsd_,
                collateralUsdPrice_,
                collateralDecimals_
            );
    }

    function healthFactor(
        uint256 riskAdjustedCollateralUsd_,
        uint256 requiredCollateralUsd_
    ) external pure returns (uint256) {
        return _healthFactor(riskAdjustedCollateralUsd_, requiredCollateralUsd_);
    }

    function utilizationBps(uint256 debt_, uint256 cap_) external pure returns (uint256) {
        return _utilizationBps(debt_, cap_);
    }

    function assetUtilizationWad(uint256 debt_, uint256 cap_) external pure returns (uint256) {
        return _assetUtilizationWad(debt_, cap_);
    }

    function effectiveUtilizationWad(
        UtilizationInputs calldata inputs_
    ) external pure returns (uint256) {
        return _effectiveUtilizationWad(inputs_);
    }

    function feeRateWad(
        uint256 utilizationWad_,
        IBurnerLoans.AssetFeeConfig memory feeConfig_
    ) external pure returns (uint256) {
        return _feeRateWad(utilizationWad_, feeConfig_);
    }

    function borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) external pure returns (uint256) {
        return _borrowFee(incrementalRequiredCollateral_, feeRateWad_);
    }

    function extensionFee(
        uint256 currentRequiredCollateral_,
        uint256 feeRateWad_,
        uint256 termCount_
    ) external pure returns (uint256) {
        return _extensionFee(currentRequiredCollateral_, feeRateWad_, termCount_);
    }

    function keeperRewardAsset(
        KeeperRewardInputs calldata inputs_
    ) external pure returns (uint256) {
        return _keeperRewardAsset(inputs_);
    }

    function setActiveDebtForTest(
        address asset_,
        uint256 totalActiveDebtOhm_,
        uint256 assetActiveDebtOhm_
    ) external {
        totalActiveDebtOhm = totalActiveDebtOhm_;
        assetActiveDebtOhm[asset_] = assetActiveDebtOhm_;
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
