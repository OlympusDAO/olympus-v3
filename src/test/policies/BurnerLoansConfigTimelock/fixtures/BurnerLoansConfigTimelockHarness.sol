// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/BurnerLoansConfigTimelock.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

contract BurnerLoansConfigTimelockHarness is BurnerLoansConfigTimelock {
    constructor(
        Kernel kernel_,
        IBurnerLoansConfig config_,
        address facility_
    ) BurnerLoansConfigTimelock(kernel_, config_, facility_) {}

    function queueAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) external returns (uint64 actionId) {
        return _queueAction(target_, selector_, payload_);
    }

    function expectedPreStateHash(
        uint64 actionId_,
        uint256 index_
    ) external view returns (bytes32) {
        return _expectedPreStateHashes[actionId_][index_];
    }

    function feeConfigPostState(
        uint64 actionId_,
        uint256 index_
    )
        external
        view
        returns (bool exists, address asset, IBurnerLoans.AssetFeeConfig memory config)
    {
        FeeConfigPostState storage state = _feeConfigPostStates[actionId_][index_];
        exists = state.exists;
        asset = state.asset;
        config = state.config;
    }

    function assetConfigPostState(
        uint64 actionId_,
        uint256 index_
    ) external view returns (bool exists, address asset, IBurnerLoans.AssetConfig memory config) {
        AssetConfigPostState storage state = _assetConfigPostStates[actionId_][index_];
        exists = state.exists;
        asset = state.asset;
        config = state.config;
    }
}
