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

    // queueAction
    // when the asset debt cap payload is one byte shorter than its ABI encoding
    //  then validation rejects the action
    function test_whenAssetDebtCapPayloadIsOneByteShort_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetDebtCap.selector, 63);
    }

    // queueAction
    // when the asset debt cap payload is one byte longer than its ABI encoding
    //  then validation rejects the action
    function test_whenAssetDebtCapPayloadIsOneByteLong_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetDebtCap.selector, 65);
    }

    // queueAction
    // when the asset debt cap word is not a canonical uint128 encoding
    //  then ABI decoding rejects the action
    function test_whenAssetDebtCapEncodingIsNonCanonical_reverts() public {
        _authorizeHarness();

        // Solidity's ABI decoder returns no stable custom error for a non-canonical uint128 word.
        vm.expectRevert();
        vm.prank(burnerLoansAdmin);
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetDebtCap.selector,
            abi.encode(address(usds), uint256(type(uint128).max) + 1)
        );
    }

    // queueAction
    // when the asset originations payload is one byte shorter than its ABI encoding
    //  then validation rejects the action
    function test_whenAssetOriginationsEnabledPayloadIsOneByteShort_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetOriginationsEnabled.selector, 63);
    }

    // queueAction
    // when the asset originations payload is one byte longer than its ABI encoding
    //  then validation rejects the action
    function test_whenAssetOriginationsEnabledPayloadIsOneByteLong_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetOriginationsEnabled.selector, 65);
    }

    // queueAction
    // when the asset originations word is not a canonical bool encoding
    //  then ABI decoding rejects the action
    function test_whenAssetOriginationsEnabledEncodingIsNonCanonical_reverts() public {
        _authorizeHarness();

        // Solidity's ABI decoder returns no stable custom error for a non-canonical bool word.
        vm.expectRevert();
        vm.prank(burnerLoansAdmin);
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetOriginationsEnabled.selector,
            abi.encode(address(usds), uint256(2))
        );
    }

    function _expectInvalidPayloadLength(bytes4 selector_, uint256 payloadLength_) internal {
        _authorizeHarness();

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(0),
                selector_
            )
        );
        vm.prank(burnerLoansAdmin);
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            selector_,
            new bytes(payloadLength_)
        );
    }

    function _authorizeHarness() internal {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(configTimelockHarness));
    }
}
