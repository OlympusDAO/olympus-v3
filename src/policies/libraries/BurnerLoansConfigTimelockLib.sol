// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";

/// @title Burner Loans Config Timelock Library
/// @notice Pure transformations used when projecting partial timelocked configuration updates.
library BurnerLoansConfigTimelockLib {
    function applyAssetRiskConfigUpdate(
        IBurnerLoans.AssetConfig memory config,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_
    ) external pure returns (IBurnerLoans.AssetConfig memory) {
        if (
            !selection_.collateralFactorBps &&
            !selection_.minCollateralRatioBps &&
            !selection_.backingMultiplierBps &&
            !selection_.keeperRewardBps &&
            !selection_.termLength &&
            !selection_.maxMaturityHorizon &&
            !selection_.maxKeeperReward
        ) revert IBurnerLoans.BurnerLoans_InvalidParam();

        if (selection_.collateralFactorBps) {
            config.collateralFactorBps = update_.collateralFactorBps;
        } else if (update_.collateralFactorBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.minCollateralRatioBps) {
            config.minCollateralRatioBps = update_.minCollateralRatioBps;
        } else if (update_.minCollateralRatioBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.backingMultiplierBps) {
            config.backingMultiplierBps = update_.backingMultiplierBps;
        } else if (update_.backingMultiplierBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.keeperRewardBps) {
            config.keeperRewardBps = update_.keeperRewardBps;
        } else if (update_.keeperRewardBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.termLength) {
            config.termLength = update_.termLength;
        } else if (update_.termLength != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.maxMaturityHorizon) {
            config.maxMaturityHorizon = update_.maxMaturityHorizon;
        } else if (update_.maxMaturityHorizon != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.maxKeeperReward) {
            config.maxKeeperReward = update_.maxKeeperReward;
        } else if (update_.maxKeeperReward != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }

        return config;
    }

    function toRiskConfig(
        IBurnerLoans.AssetConfig memory config_
    ) external pure returns (IBurnerLoans.AssetRiskConfigInput memory) {
        return
            IBurnerLoans.AssetRiskConfigInput({
                collateralFactorBps: config_.collateralFactorBps,
                minCollateralRatioBps: config_.minCollateralRatioBps,
                backingMultiplierBps: config_.backingMultiplierBps,
                keeperRewardBps: config_.keeperRewardBps,
                termLength: config_.termLength,
                maxMaturityHorizon: config_.maxMaturityHorizon,
                maxKeeperReward: config_.maxKeeperReward
            });
    }

    function applyFeeConfigUpdate(
        IBurnerLoans.AssetFeeConfig memory config,
        IBurnerLoans.AssetFeeConfig memory update_,
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection_
    ) external pure returns (IBurnerLoans.AssetFeeConfig memory) {
        if (
            !selection_.baseFeeBps &&
            !selection_.kinkBps &&
            !selection_.preKinkSlopeBps &&
            !selection_.postKinkSlopeBps
        ) revert IBurnerLoans.BurnerLoans_InvalidParam();

        if (selection_.baseFeeBps) {
            config.baseFeeBps = update_.baseFeeBps;
        } else if (update_.baseFeeBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.kinkBps) {
            config.kinkBps = update_.kinkBps;
        } else if (update_.kinkBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.preKinkSlopeBps) {
            config.preKinkSlopeBps = update_.preKinkSlopeBps;
        } else if (update_.preKinkSlopeBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }
        if (selection_.postKinkSlopeBps) {
            config.postKinkSlopeBps = update_.postKinkSlopeBps;
        } else if (update_.postKinkSlopeBps != 0) {
            revert IBurnerLoans.BurnerLoans_InvalidParam();
        }

        return config;
    }
}
