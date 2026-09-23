// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {SafeCall} from "src/libraries/SafeCall.sol";

contract SafeCallTarget {
    function returnBytes() external pure returns (bytes memory) {
        return new bytes(1024);
    }

    function revertBytes() external pure {
        bytes memory reason = new bytes(1024);
        assembly {
            revert(add(reason, 0x20), mload(reason))
        }
    }
}

contract SafeCallTest is Test {
    using SafeCall for address;

    SafeCallTarget internal _target;

    function setUp() public {
        _target = new SafeCallTarget();
    }

    function test_whenTargetHasNoCode_returnsFailure() public {
        (bool success, bytes memory result) = address(0).safeCall(100_000, 0, 4, hex"");
        assertFalse(success, "Call to an address without code must fail");
        assertEq(result.length, 0, "Call to an address without code must return no data");
    }

    function test_whenStaticTargetHasNoCode_returnsFailure() public view {
        (bool success, bytes memory result) = address(0).safeStaticCall(100_000, 4, hex"");
        assertFalse(success, "Static call to an address without code must fail");
        assertEq(result.length, 0, "Static call to an address without code must return no data");
    }

    function test_whenTargetReturnsOversizedData_capsCopy() public {
        (bool success, bytes memory result) = address(_target).safeCall(
            gasleft(),
            0,
            4,
            abi.encodeCall(SafeCallTarget.returnBytes, ())
        );
        assertTrue(success, "Call must succeed");
        assertEq(result.length, 4, "Call must copy at most four bytes");
    }

    function test_whenStaticTargetReturnsOversizedData_capsCopy() public view {
        (bool success, bytes memory result) = address(_target).safeStaticCall(
            gasleft(),
            4,
            abi.encodeCall(SafeCallTarget.returnBytes, ())
        );
        assertTrue(success, "Static call must succeed");
        assertEq(result.length, 4, "Static call must copy at most four bytes");
    }

    function test_whenTargetRevertsWithOversizedData_capsCopy() public {
        (bool success, bytes memory result) = address(_target).safeCall(
            gasleft(),
            0,
            4,
            abi.encodeCall(SafeCallTarget.revertBytes, ())
        );
        assertFalse(success, "Reverting call must fail");
        assertEq(result.length, 4, "Reverting call must copy at most four bytes");
    }
}
