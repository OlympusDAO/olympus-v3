// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Libraries
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {SafeCallTarget} from "src/test/libraries/fixtures/SafeCallTarget.sol";

contract SafeReadAddressTest is Test {
    using SafeCallDecoder for address;

    bytes4 internal constant _SELECTOR = SafeCallTarget.returnBytes.selector;
    uint256 internal constant _ABI_WORD_SIZE = 32;
    uint256 internal constant _MAX_SHORT_RETURN_SIZE = _ABI_WORD_SIZE - 1;
    uint256 internal constant _MIN_OVERSIZED_RETURN_SIZE = _ABI_WORD_SIZE + 1;
    uint256 internal constant _LARGE_RETURN_SIZE = 64;
    uint256 internal constant _MIN_DIRTY_ADDRESS_WORD = uint256(type(uint160).max) + 1;

    SafeCallTarget internal _target;

    function setUp() public {
        _target = new SafeCallTarget();
    }

    // Scenarios: ADDR-I01
    function test_whenTargetHasNoCode() public view {
        (bool success, address value) = address(0).safeReadAddress(_SELECTOR);

        assertFalse(success, "no-code address read success");
        assertEq(value, address(0), "no-code address value");
    }

    // Scenarios: ADDR-I02
    function test_whenCallReverts() public {
        _assertRevertingAddressReadFails(new bytes(0));
        _assertRevertingAddressReadFails(new bytes(_ABI_WORD_SIZE));
        _assertRevertingAddressReadFails(new bytes(_LARGE_RETURN_SIZE));
    }

    // Scenarios: ADDR-I03
    function test_whenAddressReturnIsShort(uint256 returnLength_) public {
        uint256 returnLength = bound(returnLength_, 0, _MAX_SHORT_RETURN_SIZE);

        _assertAddressReadFails(new bytes(returnLength));
    }

    // Scenarios: ADDR-I03
    function test_whenAddressReturnIsShortAtBoundaries() public {
        _assertAddressReadFails(new bytes(0));
        _assertAddressReadFails(new bytes(1));
        _assertAddressReadFails(new bytes(_MAX_SHORT_RETURN_SIZE));
    }

    // Scenarios: ADDR-I04
    function test_whenAddressReturnIsOversized() public {
        _assertAddressReadFails(new bytes(_MIN_OVERSIZED_RETURN_SIZE));
        _assertAddressReadFails(new bytes(_LARGE_RETURN_SIZE));
    }

    // Scenarios: ADDR-I05
    function test_whenAddressWordHasDirtyUpperBits(uint256 word_) public {
        uint256 word = bound(word_, _MIN_DIRTY_ADDRESS_WORD, type(uint256).max);

        _assertDirtyAddressReadFails(word);
    }

    // Scenarios: ADDR-I05
    function test_whenAddressWordHasDirtyUpperBitsAtBoundaries() public {
        _assertDirtyAddressReadFails(_MIN_DIRTY_ADDRESS_WORD);
        _assertDirtyAddressReadFails(type(uint256).max);
    }

    // Scenarios: ADDR-P01
    function test_whenAddressWordIsCanonical(address expected_) public {
        _assertAddressRead(expected_);
    }

    // Scenarios: ADDR-P01
    function test_whenAddressWordIsCanonicalAtBoundaries() public {
        _assertAddressRead(address(0));
        _assertAddressRead(address(1));
        _assertAddressRead(address(type(uint160).max));
    }

    function _assertAddressRead(address expected_) internal {
        vm.mockCall(address(_target), abi.encodeWithSelector(_SELECTOR), abi.encode(expected_));

        (bool success, address value) = address(_target).safeReadAddress(_SELECTOR);

        assertTrue(success, "canonical address read success");
        assertEq(value, expected_, "canonical address value");
        vm.clearMockedCalls();
    }

    function _assertAddressReadFails(bytes memory returnData_) internal {
        vm.mockCall(address(_target), abi.encodeWithSelector(_SELECTOR), returnData_);

        (bool success, address value) = address(_target).safeReadAddress(_SELECTOR);

        assertFalse(success, "invalid address read success");
        assertEq(value, address(0), "invalid address read value");
        vm.clearMockedCalls();
    }

    function _assertRevertingAddressReadFails(bytes memory revertData_) internal {
        vm.mockCallRevert(address(_target), abi.encodeWithSelector(_SELECTOR), revertData_);

        (bool success, address value) = address(_target).safeReadAddress(_SELECTOR);

        assertFalse(success, "reverting address read success");
        assertEq(value, address(0), "reverting address read value");
        vm.clearMockedCalls();
    }

    function _assertDirtyAddressReadFails(uint256 word_) internal {
        vm.mockCall(address(_target), abi.encodeWithSelector(_SELECTOR), abi.encode(word_));

        (bool success, address value) = address(_target).safeReadAddress(_SELECTOR);

        assertFalse(success, "non-canonical address read success");
        assertEq(value, address(0), "non-canonical address value");
        vm.clearMockedCalls();
    }
}
