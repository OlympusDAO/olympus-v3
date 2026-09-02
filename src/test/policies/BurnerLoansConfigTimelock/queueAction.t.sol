// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueActionTest is BurnerLoansConfigTimelockTest {
    function test_whenYieldAssetRoutingHasZeroDirectAllocations_queues() public {
        _queueYieldAssetRoutingPayload(abi.encode(address(usds), _directRouting(0)));
    }

    function test_whenYieldAssetRoutingHasOneDirectAllocation_queues() public {
        _queueYieldAssetRoutingPayload(abi.encode(address(usds), _directRouting(1)));
    }

    function test_whenYieldAssetRoutingHasMoreThanFiveDirectAllocations_queues() public {
        _queueYieldAssetRoutingPayload(abi.encode(address(usds), _directRouting(6)));
    }

    function test_whenYieldAssetRoutingDeclaresUnrepresentableAllocationCount_reverts() public {
        bytes memory payload = abi.encode(address(usds), _treasuryOnlyRouting());
        for (uint256 i = 128; i < 160; ++i) {
            payload[i] = 0xff;
        }

        _expectInvalidYieldAssetRoutingPayload(payload);
    }

    function test_whenYieldAssetRoutingPayloadIsShort_reverts() public {
        _expectInvalidYieldAssetRoutingPayload(new bytes(31));
    }

    function test_whenYieldAssetRoutingPayloadIsTruncated_reverts() public {
        bytes memory canonicalPayload = abi.encode(address(usds), _directRouting(1));
        bytes memory truncatedPayload = new bytes(canonicalPayload.length - 32);
        for (uint256 i; i < truncatedPayload.length; ++i) {
            truncatedPayload[i] = canonicalPayload[i];
        }

        _expectInvalidYieldAssetRoutingPayload(truncatedPayload);
    }

    function test_whenYieldAssetRoutingRepurchaseBpsEncodingIsNonCanonical_reverts() public {
        bytes memory payload = abi.encode(address(usds), _treasuryOnlyRouting());
        payload[64] = 0x01;

        _expectInvalidYieldAssetRoutingPayload(payload);
    }

    function test_whenYieldAssetRoutingPayloadHasTrailingData_reverts() public {
        bytes memory canonicalPayload = abi.encode(address(usds), _treasuryOnlyRouting());

        _expectInvalidYieldAssetRoutingPayload(bytes.concat(canonicalPayload, bytes32(0)));
    }

    function test_whenYieldAssetRoutingPayloadUsesNonCanonicalOffset_reverts() public {
        bytes memory payload = bytes.concat(
            bytes32(uint256(uint160(address(usds)))),
            bytes32(uint256(96)),
            bytes32(0),
            bytes32(0),
            bytes32(uint256(64)),
            bytes32(0)
        );

        _expectInvalidYieldAssetRoutingPayload(payload);
    }

    // queueAction
    // given target is not BurnerLoans
    //  when queueing through the raw harness
    //   then validation rejects the action
    function test_givenWrongTarget_reverts(address target_) public {
        vm.assume(target_ != address(burnerLoansConfig));
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _maxLtvUpdate();
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
                address(burnerLoansConfig),
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
                address(burnerLoansConfig),
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
    // given the asset debt cap payload is one byte shorter than its ABI encoding
    //  when the action is queued
    //   then validation rejects the action
    function test_givenAssetDebtCapPayloadOneByteShort_whenQueued_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetDebtCap.selector, 63);
    }

    // queueAction
    // given the asset debt cap payload is one byte longer than its ABI encoding
    //  when the action is queued
    //   then validation rejects the action
    function test_givenAssetDebtCapPayloadOneByteLong_whenQueued_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetDebtCap.selector, 65);
    }

    // queueAction
    // given the asset debt cap word is not a canonical uint128 encoding
    //  when the action is queued
    //   then ABI decoding rejects the action
    function test_givenAssetDebtCapEncodingNonCanonical_whenQueued_reverts() public {
        _authorizeHarness();

        // Solidity's ABI decoder returns no stable custom error for a non-canonical uint128 word.
        vm.expectRevert(bytes(""));
        vm.prank(burnerLoansAdmin);
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetDebtCap.selector,
            abi.encode(address(usds), uint256(type(uint128).max) + 1)
        );
    }

    // queueAction
    // given the asset originations payload is one byte shorter than its ABI encoding
    //  when the action is queued
    //   then validation rejects the action
    function test_givenAssetOriginationsPayloadOneByteShort_whenQueued_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetOriginationsEnabled.selector, 63);
    }

    // queueAction
    // given the asset originations payload is one byte longer than its ABI encoding
    //  when the action is queued
    //   then validation rejects the action
    function test_givenAssetOriginationsPayloadOneByteLong_whenQueued_reverts() public {
        _expectInvalidPayloadLength(IBurnerLoansConfig.setAssetOriginationsEnabled.selector, 65);
    }

    // queueAction
    // given the asset originations word is not a canonical bool encoding
    //  when the action is queued
    //   then ABI decoding rejects the action
    function test_givenAssetOriginationsEncodingNonCanonical_whenQueued_reverts() public {
        _authorizeHarness();

        // Solidity's ABI decoder returns no stable custom error for a non-canonical bool word.
        vm.expectRevert(bytes(""));
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
                address(burnerLoansConfig),
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

    function _queueYieldAssetRoutingPayload(bytes memory payload_) internal {
        _authorizeHarness();
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setYieldAssetRouting.selector,
            payload_
        );
        assertEq(actionId, 1, "action id");
    }

    function _expectInvalidYieldAssetRoutingPayload(bytes memory payload_) internal {
        _authorizeHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(burnerLoansConfig),
                IBurnerLoansConfig.setYieldAssetRouting.selector
            )
        );
        vm.prank(burnerLoansAdmin);
        configTimelockHarness.queueAction(
            address(burnerLoansConfig),
            IBurnerLoansConfig.setYieldAssetRouting.selector,
            payload_
        );
    }

    function _authorizeHarness() internal {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(configTimelockHarness));
    }
}
