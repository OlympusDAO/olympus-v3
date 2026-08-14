// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueActionTest is BurnerLoansConfigTimelockTest {
    // queueAction
    // given target is not BurnerLoans
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenWrongTarget_reverts(address target_) public {
        vm.assume(target_ != address(burnerLoansConfig));
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                target_,
                IBurnerLoansConfig.setAssetRiskConfig.selector
            )
        );
        configTimelockHarness.queueAction(
            target_,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds), update, selection)
        );
    }

    // queueAction
    // given selector is not a supported Burner Loans configuration setter
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenUnsupportedSelector_reverts() public {
        bytes4 unsupportedSelector = bytes4(keccak256("setGlobalDebtCap(uint256)"));
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(burnerLoansConfig),
                unsupportedSelector
            )
        );
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            unsupportedSelector,
            abi.encode(1_000_000e9)
        );
    }

    // queueAction
    // given payload length does not match the asset risk setter ABI
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenMalformedAssetRiskConfigPayload_reverts() public {
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(0),
                IBurnerLoansConfig.setAssetRiskConfig.selector
            )
        );
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds))
        );
    }

    // queueAction
    // given payload length does not match the fee config setter ABI
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenMalformedFeeConfigPayload_reverts() public {
        _authorizeHarness();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(0),
                IBurnerLoansConfig.setAssetFeeConfig.selector
            )
        );
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetFeeConfig.selector,
            abi.encode(address(usds))
        );
    }

    function _authorizeHarness() internal {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(configTimelockHarness));
    }
}
