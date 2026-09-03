// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

abstract contract BurnerLoansConfigTimelockConfigGuardsTest is BurnerLoansConfigTimelockTest {
    bytes32 internal constant _FEE_DOMAIN = keccak256("BURNER_LOANS_FEE_CONFIG");
    bytes32 internal constant _RISK_DOMAIN = keccak256("BURNER_LOANS_RISK_CONFIG");
    bytes32 internal constant _DEBT_CAP_DOMAIN = keccak256("BURNER_LOANS_DEBT_CAP");
    bytes32 internal constant _ORIGINATIONS_DOMAIN = keccak256("BURNER_LOANS_ASSET_ORIGINATIONS");
    bytes32 internal constant _YIELD_RECIPIENT_DOMAIN = keccak256("BURNER_LOANS_YIELD_RECIPIENT");
    bytes32 internal constant _YIELD_RECIPIENT_ASSET_DOMAIN =
        keccak256("BURNER_LOANS_YIELD_RECIPIENT_ASSET");

    function _feeAction(
        uint16 baseFeeBps_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            _singleAction(
                IBurnerLoansConfig.setAssetFeeConfig.selector,
                abi.encode(address(usds), _feeUpdate(baseFeeBps_), _feeSelection())
            );
    }

    function _riskAction(
        uint16 maxLtvBps_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return
            _singleAction(
                IBurnerLoansConfig.setAssetRiskConfig.selector,
                abi.encode(address(usds), _riskUpdate(maxLtvBps_), _riskSelection())
            );
    }

    function _assertGuard(
        uint64 actionId_,
        uint256 index_,
        bytes32 domain_,
        bytes32 expectedHash_
    ) internal view {
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(
            actionId_,
            index_,
            0
        );
        bytes32 expectedKey = _scopedConfigKey(domain_);
        assertEq(key, expectedKey, "configuration key");
        assertEq(
            configTimelock.getQueuedConfigDestination(actionId_, index_),
            address(burnerLoansConfig),
            "configuration destination"
        );
        assertEq(expectedHash, expectedHash_, "canonical state hash");
        assertEq(configTimelock.pendingActionId(key), actionId_, "key owner");
    }

    function _scopedConfigKey(bytes32 domain_) internal view returns (bytes32 key) {
        bytes32 localKey = keccak256(abi.encode(domain_, address(usds)));
        return keccak256(abi.encode(address(burnerLoansConfig), localKey));
    }

    function _scopedYieldRecipientKey() internal view returns (bytes32 key) {
        bytes32 localKey = keccak256(abi.encode(_YIELD_RECIPIENT_DOMAIN));
        return keccak256(abi.encode(address(burnerLoansConfig), localKey));
    }

    function _scopedYieldRecipientAssetKey(address asset_) internal view returns (bytes32 key) {
        bytes32 localKey = keccak256(abi.encode(_YIELD_RECIPIENT_ASSET_DOMAIN, asset_));
        return keccak256(abi.encode(address(burnerLoansConfig), localKey));
    }

    function _yieldRoutingStateHash() internal view returns (bytes32 stateHash) {
        bytes32 allocationsHash;
        uint256 assetCount = burnerLoans.getAssetCount();
        for (uint256 i; i < assetCount; ++i) {
            address asset = burnerLoans.getAssetAt(i);
            allocationsHash = keccak256(
                abi.encode(allocationsHash, asset, burnerLoans.getYieldRecipientAssetBps(asset))
            );
        }
        return
            keccak256(
                abi.encode(address(burnerLoans), burnerLoans.getYieldRecipient(), allocationsHash)
            );
    }

    function _yieldRecipientAssetStateHash(
        address asset_
    ) internal view returns (bytes32 stateHash) {
        return
            keccak256(
                abi.encode(
                    address(burnerLoans),
                    burnerLoans.getYieldRecipient(),
                    asset_,
                    burnerLoans.getYieldRecipientAssetBps(asset_)
                )
            );
    }

    function _feeUpdate(
        uint16 baseFeeBps_
    ) internal pure returns (IBurnerLoans.AssetFeeConfig memory config) {
        config.baseFeeBps = baseFeeBps_;
    }

    function _feeSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection)
    {
        selection.baseFeeBps = true;
    }

    function _riskUpdate(
        uint16 maxLtvBps_
    ) internal pure returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update) {
        update.maxLtvBps = maxLtvBps_;
    }

    function _riskSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection)
    {
        selection.maxLtvBps = true;
    }
}
