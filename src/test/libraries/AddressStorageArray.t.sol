// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {AddressStorageArray} from "src/libraries/AddressStorageArray.sol";

contract AddressStorageArrayTest is Test {
    using AddressStorageArray for address[];

    address[] public array;

    function _expectRevertIndexOutOfBounds(uint256 index_, uint256 length_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressStorageArray.AddressStorageArray_IndexOutOfBounds.selector,
                index_,
                length_
            )
        );
    }

    // ========== TESTS ========== //
    // insert
    // given there are no elements in the array
    //  when index is >= 1
    //   [X] it reverts

    /// forge-config: default.allow_internal_expect_revert = true
    function test_insert_noElements_whenIndexGreaterThanLength_reverts(uint256 index_) public {
        index_ = bound(index_, 1, type(uint256).max);

        _expectRevertIndexOutOfBounds(index_, 0);

        array.insert(address(1), index_);
    }

    //  [X] it inserts the value at index 0
    //  [X] the array length is 1

    function test_insert_noElements() public {
        array.insert(address(1), 0);

        assertEq(array.length, 1);
        assertEq(array[0], address(1));
    }

    // when index is > the array length
    //  [X] it reverts

    /// forge-config: default.allow_internal_expect_revert = true
    function test_insert_whenIndexGreaterThanLength_reverts(uint256 index_) public {
        index_ = bound(index_, 2, type(uint256).max);

        array.push(address(1));

        _expectRevertIndexOutOfBounds(index_, 1);

        array.insert(address(2), index_);
    }

    // [X] it inserts the value at the index
    // [X] it does not shift the elements before the index
    // [X] it shifts the elements after the index to the right
    // [X] the array length is incremented

    function test_insert_indexZero() public {
        array.push(address(1));
        array.push(address(2));

        array.insert(address(3), 0);

        assertEq(array.length, 3);
        assertEq(array[0], address(3));
        assertEq(array[1], address(1));
        assertEq(array[2], address(2));
    }

    function test_insert_indexOne() public {
        array.push(address(1));
        array.push(address(2));

        array.insert(address(3), 1);

        assertEq(array.length, 3);
        assertEq(array[0], address(1));
        assertEq(array[1], address(3));
        assertEq(array[2], address(2));
    }

    function test_insert_indexTwo() public {
        array.push(address(1));
        array.push(address(2));

        array.insert(address(3), 2);

        assertEq(array.length, 3);
        assertEq(array[0], address(1));
        assertEq(array[1], address(2));
        assertEq(array[2], address(3));
    }

    // remove
    // given there are no elements in the array
    //  [X] it reverts

    /// forge-config: default.allow_internal_expect_revert = true
    function test_remove_noElements_whenIndexGreaterThanLength_reverts(uint256 index_) public {
        index_ = bound(index_, 0, type(uint256).max);

        _expectRevertIndexOutOfBounds(index_, 0);

        array.remove(index_);
    }

    // when index is >= the array length
    //  [X] it reverts

    /// forge-config: default.allow_internal_expect_revert = true
    function test_remove_whenIndexGreaterThanLength_reverts(uint256 index_) public {
        index_ = bound(index_, 1, type(uint256).max);

        array.push(address(1));

        _expectRevertIndexOutOfBounds(index_, 1);

        array.remove(index_);
    }

    // [X] it removes the value at the index
    // [X] it does not shift the elements before the index
    // [X] it shifts the elements after the index to the left
    // [X] the array length is decremented
    // [X] it returns the removed value

    function test_remove_indexZero() public {
        array.push(address(1));
        array.push(address(2));
        array.push(address(3));

        address removedValue = array.remove(0);

        assertEq(removedValue, address(1), "removed value");

        assertEq(array.length, 2, "array length");
        assertEq(array[0], address(2), "array[0]");
        assertEq(array[1], address(3), "array[1]");
    }

    function test_remove_indexOne() public {
        array.push(address(1));
        array.push(address(2));
        array.push(address(3));

        address removedValue = array.remove(1);

        assertEq(removedValue, address(2), "removed value");

        assertEq(array.length, 2, "array length");
        assertEq(array[0], address(1), "array[0]");
        assertEq(array[1], address(3), "array[1]");
    }

    function test_remove_indexTwo() public {
        array.push(address(1));
        array.push(address(2));
        array.push(address(3));

        address removedValue = array.remove(2);

        assertEq(removedValue, address(3), "removed value");

        assertEq(array.length, 2, "array length");
        assertEq(array[0], address(1), "array[0]");
        assertEq(array[1], address(2), "array[1]");
    }
}
