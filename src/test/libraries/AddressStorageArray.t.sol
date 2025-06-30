// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {AddressStorageArray} from "src/libraries/AddressStorageArray.sol";

contract AddressStorageArrayTest is Test {
    // ========== TESTS ========== //
    // insert
    // given there are no elements in the array
    //  when index is >= 1
    //   [ ] it reverts
    //  [ ] it inserts the value at index 0
    //  [ ] the array length is 1
    // when index is > the array length
    //  [ ] it reverts
    // [ ] it inserts the value at the index
    // [ ] it does not shift the elements before the index
    // [ ] it shifts the elements after the index to the right
    // [ ] the array length is incremented
    // remove
    // given there are no elements in the array
    //  [ ] it reverts
    // when index is >= the array length
    //  [ ] it reverts
    // [ ] it removes the value at the index
    // [ ] it does not shift the elements before the index
    // [ ] it shifts the elements after the index to the left
    // [ ] the array length is decremented
}
