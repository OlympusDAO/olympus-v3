// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock Library
/// @notice Transformations and dispatch used by Burner Loans timelocked configuration updates.
library BurnerLoansConfigTimelockLib {
    /// @notice Validates a proposed recipient against every current nonzero asset allocation.
    /// @dev Clearing the recipient requires every per-asset allocation to be zero.
    function validateYieldRecipientChange(
        IBurnerLoansView facility_,
        address recipient_
    ) external view {
        uint256 assetCount = facility_.getAssetCount();
        if (recipient_ == address(0)) {
            // Count every active allocation so queue-time validation reports the same complete
            // state as the facility setter rather than stopping with an arbitrary count of one.
            uint256 activeAssetCount;
            for (uint256 i; i < assetCount; ++i) {
                if (facility_.getYieldRecipientAssetBps(facility_.getAssetAt(i)) != 0) {
                    ++activeAssetCount;
                }
            }
            if (activeAssetCount != 0) {
                revert IBurnerLoans.BurnerLoans_YieldAllocationsActive(activeAssetCount);
            }
            return;
        }

        facility_.validateYieldRecipient(recipient_);
        for (uint256 i; i < assetCount; ++i) {
            address asset = facility_.getAssetAt(i);
            if (facility_.getYieldRecipientAssetBps(asset) != 0) {
                facility_.validateYieldRecipientAsset(recipient_, asset);
            }
        }
    }

    /// @notice Hashes the complete yield-routing configuration guarded by the timelock.
    /// @dev The append-only asset order makes the rolling allocation hash deterministic. Any
    ///      recipient, asset-registration, or per-asset allocation change alters the result.
    function yieldRoutingStateHash(
        IBurnerLoansView facility_
    ) external view returns (bytes32 stateHash) {
        uint256 assetCount = facility_.getAssetCount();
        bytes32 allocationsHash;
        for (uint256 i; i < assetCount; ++i) {
            address asset = facility_.getAssetAt(i);
            allocationsHash = keccak256(
                abi.encode(allocationsHash, asset, facility_.getYieldRecipientAssetBps(asset))
            );
        }
        return
            keccak256(
                abi.encode(address(facility_), facility_.getYieldRecipient(), allocationsHash)
            );
    }

    /// @notice Hashes the routing state relevant to one asset allocation.
    /// @dev Recipient changes invalidate every queued allocation, while allocation changes for a
    ///      different asset leave this hash unchanged.
    function yieldRecipientAssetStateHash(
        IBurnerLoansView facility_,
        address asset_
    ) external view returns (bytes32 stateHash) {
        return
            keccak256(
                abi.encode(
                    address(facility_),
                    facility_.getYieldRecipient(),
                    asset_,
                    facility_.getYieldRecipientAssetBps(asset_)
                )
            );
    }

    /// @notice Decodes and executes one supported Burner Loans configuration action.
    /// @dev Reverts for unsupported selectors and bubbles the target setter's revert data.
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
        } else if (selector == IBurnerLoansConfig.setYieldRecipient.selector) {
            callData = abi.encodeWithSelector(selector, abi.decode(action_.payload, (address)));
        } else if (selector == IBurnerLoansConfig.setYieldRecipientAssetBps.selector) {
            (address asset, uint16 bps) = abi.decode(action_.payload, (address, uint16));
            callData = abi.encodeWithSelector(selector, asset, bps);
        } else {
            revert ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        }

        (bool success, bytes memory returnData) = action_.target.call(callData);
        if (!success) {
            if (returnData.length == 0) {
                revert IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_SubActionCallFailed(
                    action_.target,
                    selector
                );
            }
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    /// @notice Applies a selected partial risk-configuration update.
    /// @dev Reverts when no fields are selected or an unselected update field is nonzero.
    function applyAssetRiskConfigUpdate(
        IBurnerLoans.AssetConfig memory config,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_
    ) public pure returns (IBurnerLoans.AssetConfig memory) {
        if (
            !selection_.maxLtvBps &&
            !selection_.backingMultiplierBps &&
            !selection_.keeperRewardBps &&
            !selection_.termLength &&
            !selection_.maxMaturityHorizon &&
            !selection_.maxKeeperReward
        ) revert IBurnerLoans.BurnerLoans_InvalidParam();

        if (selection_.maxLtvBps) {
            config.maxLtvBps = update_.maxLtvBps;
        } else if (update_.maxLtvBps != 0) {
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

    /// @notice Projects a complete asset configuration into the risk setter's input shape.
    function toRiskConfig(
        IBurnerLoans.AssetConfig memory config_
    ) public pure returns (IBurnerLoans.AssetRiskConfigInput memory) {
        return
            IBurnerLoans.AssetRiskConfigInput({
                maxLtvBps: config_.maxLtvBps,
                backingMultiplierBps: config_.backingMultiplierBps,
                keeperRewardBps: config_.keeperRewardBps,
                termLength: config_.termLength,
                maxMaturityHorizon: config_.maxMaturityHorizon,
                maxKeeperReward: config_.maxKeeperReward
            });
    }

    /// @notice Applies a selected partial fee-configuration update.
    /// @dev Reverts when no fields are selected or an unselected update field is nonzero.
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
