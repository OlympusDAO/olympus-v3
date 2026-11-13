// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Libraries
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {SafeCallTarget} from "src/test/libraries/fixtures/SafeCallTarget.sol";

contract SafeReadBoolTest is Test {
    using SafeCallDecoder for address;

    bytes4 internal constant _SELECTOR = SafeCallTarget.returnBytes.selector;
    uint256 internal constant _ABI_WORD_SIZE = 32;
    uint256 internal constant _MAX_SHORT_RETURN_SIZE = _ABI_WORD_SIZE - 1;
    uint256 internal constant _MIN_OVERSIZED_RETURN_SIZE = _ABI_WORD_SIZE + 1;
    uint256 internal constant _LARGE_RETURN_SIZE = 64;

    SafeCallTarget internal _target;

    function setUp() public {
        _target = new SafeCallTarget();
    }

    // Scenarios: BOOL-I01
    function test_whenTargetHasNoCode() public view {
        (bool success, bool value) = address(0).safeReadBool(_SELECTOR);

        assertFalse(success, "no-code bool read success");
        assertFalse(value, "no-code bool read value");
    }

    // Scenarios: BOOL-I02
    function test_whenCallReverts() public {
        _assertRevertingBoolReadFails(new bytes(0));
        _assertRevertingBoolReadFails(new bytes(_ABI_WORD_SIZE));
        _assertRevertingBoolReadFails(new bytes(_LARGE_RETURN_SIZE));
    }

    // Scenarios: BOOL-I03
    function test_whenBoolReturnIsShort(uint256 returnLength_) public {
        uint256 returnLength = bound(returnLength_, 0, _MAX_SHORT_RETURN_SIZE);

        _assertBoolReadFails(new bytes(returnLength));
    }

    // Scenarios: BOOL-I03
    function test_whenBoolReturnIsShortAtBoundaries() public {
        _assertBoolReadFails(new bytes(0));
        _assertBoolReadFails(new bytes(1));
        _assertBoolReadFails(new bytes(_MAX_SHORT_RETURN_SIZE));
    }

    // Scenarios: BOOL-I04
    function test_whenBoolReturnIsOversized() public {
        _assertBoolReadFails(new bytes(_MIN_OVERSIZED_RETURN_SIZE));
        _assertBoolReadFails(new bytes(_LARGE_RETURN_SIZE));
    }

    // Scenarios: BOOL-I05
    function test_whenBoolWordIsNotCanonical(uint256 word_) public {
        uint256 word = bound(word_, 2, type(uint256).max);

        _assertBoolWordReadFails(word);
    }

    // Scenarios: BOOL-I05
    function test_whenBoolWordIsNotCanonicalAtBoundaries() public {
        _assertBoolWordReadFails(2);
        _assertBoolWordReadFails(type(uint256).max);
    }

    // Scenarios: BOOL-P01, BOOL-P02
    function test_whenBoolWordIsCanonical() public {
        _assertBoolRead(false);
        _assertBoolRead(true);
    }

    function _assertBoolRead(bool expected_) internal {
        vm.mockCall(address(_target), abi.encodeWithSelector(_SELECTOR), abi.encode(expected_));

        (bool success, bool value) = address(_target).safeReadBool(_SELECTOR);

        assertTrue(success, "canonical bool read success");
        assertEq(value, expected_, "canonical bool value");
        vm.clearMockedCalls();
    }

    function _assertBoolReadFails(bytes memory returnData_) internal {
        vm.mockCall(address(_target), abi.encodeWithSelector(_SELECTOR), returnData_);

        (bool success, bool value) = address(_target).safeReadBool(_SELECTOR);

        assertFalse(success, "invalid bool read success");
        assertFalse(value, "invalid bool read value");
        vm.clearMockedCalls();
    }

    function _assertRevertingBoolReadFails(bytes memory revertData_) internal {
        vm.mockCallRevert(address(_target), abi.encodeWithSelector(_SELECTOR), revertData_);

        (bool success, bool value) = address(_target).safeReadBool(_SELECTOR);

        assertFalse(success, "reverting bool read success");
        assertFalse(value, "reverting bool read value");
        vm.clearMockedCalls();
    }

    function _assertBoolWordReadFails(uint256 word_) internal {
        vm.mockCall(address(_target), abi.encodeWithSelector(_SELECTOR), abi.encode(word_));

        (bool success, bool value) = address(_target).safeReadBool(_SELECTOR);

        assertFalse(success, "non-canonical bool read success");
        assertFalse(value, "non-canonical bool value");
        vm.clearMockedCalls();
    }
}
