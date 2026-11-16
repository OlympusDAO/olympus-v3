// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {SafeCall} from "src/libraries/SafeCall.sol";
import {SafeCallTarget} from "src/test/libraries/fixtures/SafeCallTarget.sol";

contract SafeCallTest is Test {
    using SafeCall for address;

    uint256 internal constant _NO_CODE_GAS = 100_000;
    uint256 internal constant _NO_VALUE = 0;
    uint16 internal constant _MAX_COPY_BYTES = 4;

    SafeCallTarget internal _target;

    function setUp() public {
        _target = new SafeCallTarget();
    }

    function test_whenTargetHasNoCode_returnsFailure() public {
        (bool success, bytes memory result) = address(0).safeCall(
            _NO_CODE_GAS,
            _NO_VALUE,
            _MAX_COPY_BYTES,
            abi.encodeCall(SafeCallTarget.returnBytes, ())
        );
        assertFalse(success, "Call to an address without code must fail");
        assertEq(result.length, 0, "Call to an address without code must return no data");
    }

    function test_whenStaticTargetHasNoCode_returnsFailure() public view {
        (bool success, bytes memory result) = address(0).safeStaticCall(
            _NO_CODE_GAS,
            _MAX_COPY_BYTES,
            abi.encodeCall(SafeCallTarget.returnBytes, ())
        );
        assertFalse(success, "Static call to an address without code must fail");
        assertEq(result.length, 0, "Static call to an address without code must return no data");
    }

    function test_whenTargetReturnsOversizedData_capsCopy() public {
        (bool success, bytes memory result) = address(_target).safeCall(
            gasleft(),
            _NO_VALUE,
            _MAX_COPY_BYTES,
            abi.encodeCall(SafeCallTarget.returnBytes, ())
        );
        assertTrue(success, "Call must succeed");
        assertEq(result.length, _MAX_COPY_BYTES, "Call must copy at most four bytes");
    }

    function test_whenStaticTargetReturnsOversizedData_capsCopy() public view {
        (bool success, bytes memory result) = address(_target).safeStaticCall(
            gasleft(),
            _MAX_COPY_BYTES,
            abi.encodeCall(SafeCallTarget.returnBytes, ())
        );
        assertTrue(success, "Static call must succeed");
        assertEq(result.length, _MAX_COPY_BYTES, "Static call must copy at most four bytes");
    }

    function test_whenTargetRevertsWithOversizedData_capsCopy() public {
        (bool success, bytes memory result) = address(_target).safeCall(
            gasleft(),
            _NO_VALUE,
            _MAX_COPY_BYTES,
            abi.encodeCall(SafeCallTarget.revertBytes, ())
        );
        assertFalse(success, "Reverting call must fail");
        assertEq(result.length, _MAX_COPY_BYTES, "Reverting call must copy at most four bytes");
    }
}
