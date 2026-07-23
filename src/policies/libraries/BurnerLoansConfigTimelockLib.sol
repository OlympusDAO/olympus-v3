// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock Library
/// @notice Pure transformations used when projecting partial timelocked configuration updates.
library BurnerLoansConfigTimelockLib {
    function validatePreState(
        IBurnerLoansConfig burnerLoans_,
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_,
        bytes32 expectedHash_
    ) external view {
        if (action_.target != address(burnerLoans_) || expectedHash_ == bytes32(0)) {
            revert ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid(
                action_.target,
                action_.selector
            );
        }

        bytes4 selector = action_.selector;
        address asset = abi.decode(action_.payload, (address));
        if (!burnerLoans_.isAssetConfigured(asset)) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset);
        }

        bytes32 currentHash;
        if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            currentHash = keccak256(abi.encode(asset, burnerLoans_.getAssetFeeConfig(asset)));
        } else if (
            selector == IBurnerLoansConfig.setAssetRiskConfig.selector ||
            selector == IBurnerLoansConfig.setAssetDebtCap.selector ||
            selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector
        ) {
            currentHash = keccak256(abi.encode(asset, burnerLoans_.getAssetConfig(asset)));
        } else {
            revert ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }

        if (currentHash != expectedHash_) {
            revert IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged(
                actionId_,
                index_,
                expectedHash_,
                currentHash
            );
        }
    }

    function executeSubAction(
        IBurnerLoansConfig burnerLoans_,
        ITimelockBatchQueue.BatchAction memory action_
    ) external {
        bytes4 selector = action_.selector;
        bytes memory callData;
        if (selector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
            (
                address asset,
                IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
                IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
            ) = abi.decode(
                    action_.payload,
                    (
                        address,
                        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate,
                        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection
                    )
                );
            IBurnerLoans.AssetConfig memory config = applyAssetRiskConfigUpdate(
                burnerLoans_.getAssetConfig(asset),
                update,
                selection
            );
            callData = abi.encodeWithSelector(selector, asset, toRiskConfig(config));
        } else if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            (
                address asset,
                IBurnerLoans.AssetFeeConfig memory update,
                IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
            ) = abi.decode(
                    action_.payload,
                    (
                        address,
                        IBurnerLoans.AssetFeeConfig,
                        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection
                    )
                );
            IBurnerLoans.AssetFeeConfig memory config = applyFeeConfigUpdate(
                burnerLoans_.getAssetFeeConfig(asset),
                update,
                selection
            );
            callData = abi.encodeWithSelector(selector, asset, config);
        } else if (selector == IBurnerLoansConfig.setAssetDebtCap.selector) {
            (address asset, uint128 debtCapOhm) = abi.decode(action_.payload, (address, uint128));
            callData = abi.encodeWithSelector(selector, asset, debtCapOhm);
        } else if (selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector) {
            (address asset, bool enabled) = abi.decode(action_.payload, (address, bool));
            callData = abi.encodeWithSelector(selector, asset, enabled);
        } else {
            revert ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }

        (bool success, bytes memory returnData) = action_.target.call(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function applyAssetRiskConfigUpdate(
        IBurnerLoans.AssetConfig memory config,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_
    ) public pure returns (IBurnerLoans.AssetConfig memory) {
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
    ) public pure returns (IBurnerLoans.AssetRiskConfigInput memory) {
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
    ) public pure returns (IBurnerLoans.AssetFeeConfig memory) {
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
