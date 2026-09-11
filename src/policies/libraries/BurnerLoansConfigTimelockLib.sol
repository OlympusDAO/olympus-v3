// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {ExcessivelySafeCall} from "@excessively-safe-call-0.0.1/ExcessivelySafeCall.sol";

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock Library
/// @notice Transformations and dispatch used by Burner Loans timelocked configuration updates.
library BurnerLoansConfigTimelockLib {
    using ExcessivelySafeCall for address;

    /// @dev Caps copied return data so a callee cannot exhaust the caller's remaining gas.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 256;

    error BurnerLoansConfigTimelockLib_NonCanonicalYieldAssetRoutingPayload();

    /// @notice Decodes an asset-yield-routing action payload.
    /// @dev The external boundary lets the caller normalize decoding and canonicality failures.
    function decodeYieldAssetRoutingPayload(
        bytes calldata payload_
    ) external pure returns (address asset, IBurnerLoans.AssetYieldRouting memory routing) {
        (asset, routing) = abi.decode(payload_, (address, IBurnerLoans.AssetYieldRouting));
        if (keccak256(payload_) != keccak256(abi.encode(asset, routing))) {
            revert BurnerLoansConfigTimelockLib_NonCanonicalYieldAssetRoutingPayload();
        }
    }

    /// @notice Validates a proposed repurchase recipient against every current asset route.
    /// @dev Clearing the recipient requires every route's repurchase allocation to be zero.
    function validateYieldRepurchaseRecipientChange(
        IBurnerLoansView facility_,
        address recipient_
    ) external view {
        uint256 assetCount = facility_.getAssetCount();
        // Governance controls the asset registry, which is expected to remain small. Inspecting
        // every route is required to validate a global recipient change.
        // forge-lint: disable-start(calls-loop)
        if (recipient_ == address(0)) {
            // Count every active allocation so queue-time validation reports the same complete
            // state as the facility setter rather than stopping with an arbitrary count of one.
            uint256 activeAssetCount;
            for (uint256 i; i < assetCount; ++i) {
                if (
                    facility_
                        .getYieldAssetRouting(facility_.getAssetAt(i))
                        .repurchaseRecipientBps != 0
                ) {
                    ++activeAssetCount;
                }
            }
            if (activeAssetCount != 0) {
                revert IBurnerLoans.BurnerLoans_YieldRepurchaseAllocationsActive(activeAssetCount);
            }
            return;
        }

        for (uint256 i; i < assetCount; ++i) {
            address asset = facility_.getAssetAt(i);
            IBurnerLoans.AssetYieldRouting memory routing = facility_.getYieldAssetRouting(asset);
            uint256 directAllocationCount = routing.directAllocations.length;
            for (uint256 j; j < directAllocationCount; ++j) {
                if (routing.directAllocations[j].recipient == recipient_) {
                    // Rejecting a collision immediately preserves atomic route validation.
                    // forge-lint: disable-next-line(require-revert-in-loop)
                    revert IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient(recipient_);
                }
            }
        }
        // forge-lint: disable-end(calls-loop)
    }

    /// @notice Hashes the complete yield-routing configuration guarded by the timelock.
    /// @dev The append-only asset order makes the rolling route hash deterministic. Any recipient,
    ///      asset-registration, route value, or direct-allocation order change alters the result.
    function yieldRoutingStateHash(
        IBurnerLoansView facility_
    ) external view returns (bytes32 stateHash) {
        uint256 assetCount = facility_.getAssetCount();
        bytes32 routesHash;
        // Governance controls the asset registry, which is expected to remain small. The complete
        // registry must be read to bind queued actions to the current global routing state.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i; i < assetCount; ++i) {
            address asset = facility_.getAssetAt(i);
            routesHash = keccak256(
                abi.encode(routesHash, asset, facility_.getYieldAssetRouting(asset))
            );
        }
        // forge-lint: disable-end(calls-loop)
        return
            keccak256(
                abi.encode(address(facility_), facility_.getYieldRepurchaseRecipient(), routesHash)
            );
    }

    /// @notice Hashes the routing state relevant to one asset route.
    /// @dev Recipient changes invalidate every queued route, while changes for a different asset
    ///      leave this hash unchanged.
    function yieldAssetRoutingStateHash(
        IBurnerLoansView facility_,
        address asset_
    ) external view returns (bytes32 stateHash) {
        return
            keccak256(
                abi.encode(
                    address(facility_),
                    facility_.getYieldRepurchaseRecipient(),
                    asset_,
                    facility_.getYieldAssetRouting(asset_)
                )
            );
    }

    /// @notice Decodes and executes one supported Burner Loans configuration action.
    /// @dev Reverts for unsupported selectors. Complete target errors below the return-data cap are
    ///      bubbled verbatim. Empty or potentially truncated errors use a descriptive fallback.
    function executeSubAction(
        IBurnerLoansConfig burnerLoans_,
        ITimelockBatchQueue.BatchAction memory action_
    ) external {
        bytes4 actionSelector = action_.selector;
        bytes memory callData;
        if (actionSelector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
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
            callData = abi.encodeWithSelector(actionSelector, asset, toRiskConfig(config));
        } else if (actionSelector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
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
            callData = abi.encodeWithSelector(actionSelector, asset, config);
        } else if (
            actionSelector == IBurnerLoansConfig.setAssetDebtCap.selector ||
            actionSelector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector ||
            actionSelector == IBurnerLoansConfig.setYieldRepurchaseRecipient.selector ||
            actionSelector == IBurnerLoansConfig.setYieldAssetRouting.selector
        ) {
            callData = abi.encodePacked(actionSelector, action_.payload);
        } else {
            revert ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid(
                action_.target,
                actionSelector
            );
        }

        (bool success, bytes memory returnData) = action_.target.excessivelySafeCall(
            gasleft(),
            0,
            _MAX_RETURN_DATA_BYTES,
            callData
        );
        if (!success) {
            if (returnData.length == 0 || returnData.length == _MAX_RETURN_DATA_BYTES) {
                revert IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_SubActionCallFailed(
                    action_.target,
                    actionSelector
                );
            }

            // Bounded return data is rethrown verbatim to preserve the underlying error.
            // forge-lint: disable-next-line(inline-assembly)
            assembly ("memory-safe") {
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
        _validateAssetRiskConfigUpdateShape(update_, selection_);

        if (selection_.maxLtvBps) {
            config.maxLtvBps = update_.maxLtvBps;
        }
        if (selection_.backingMultiplierBps) {
            config.backingMultiplierBps = update_.backingMultiplierBps;
        }
        if (selection_.keeperRewardBps) {
            config.keeperRewardBps = update_.keeperRewardBps;
        }
        if (selection_.termLength) {
            config.termLength = update_.termLength;
        }
        if (selection_.maxMaturityHorizon) {
            config.maxMaturityHorizon = update_.maxMaturityHorizon;
        }
        if (selection_.maxKeeperReward) {
            config.maxKeeperReward = update_.maxKeeperReward;
        }

        return config;
    }

    /// @notice Validates the shape of a partial asset risk update.
    /// @dev Reverts when no fields are selected or an unselected field is nonzero. Full-value
    ///      validation is performed separately after applying the partial update because
    ///      cross-field rules require the selected values to be merged with current state, and
    ///      Burner Loans Config remains the single owner of those rules.
    /// @param update_ Partial risk and term values to validate.
    /// @param selection_ Fields selected for application from `update_`.
    function _validateAssetRiskConfigUpdateShape(
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_
    ) private pure {
        if (
            !selection_.maxLtvBps &&
            !selection_.backingMultiplierBps &&
            !selection_.keeperRewardBps &&
            !selection_.termLength &&
            !selection_.maxMaturityHorizon &&
            !selection_.maxKeeperReward
        ) revert IBurnerLoans.BurnerLoans_InvalidParam();

        _requireUnselectedAssetRiskConfigFieldZero(selection_.maxLtvBps, update_.maxLtvBps);
        _requireUnselectedAssetRiskConfigFieldZero(
            selection_.backingMultiplierBps,
            update_.backingMultiplierBps
        );
        _requireUnselectedAssetRiskConfigFieldZero(
            selection_.keeperRewardBps,
            update_.keeperRewardBps
        );
        _requireUnselectedAssetRiskConfigFieldZero(selection_.termLength, update_.termLength);
        _requireUnselectedAssetRiskConfigFieldZero(
            selection_.maxMaturityHorizon,
            update_.maxMaturityHorizon
        );
        _requireUnselectedAssetRiskConfigFieldZero(
            selection_.maxKeeperReward,
            update_.maxKeeperReward
        );
    }

    /// @notice Requires an unselected asset risk field to carry a zero update value.
    /// @dev Selected values are validated as part of the resulting complete risk configuration.
    /// @param selected_ Whether the field is selected for application.
    /// @param value_ Proposed value for the field.
    function _requireUnselectedAssetRiskConfigFieldZero(
        bool selected_,
        uint256 value_
    ) private pure {
        if (!selected_ && value_ != 0) revert IBurnerLoans.BurnerLoans_InvalidParam();
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
