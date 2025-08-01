// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {TimestampLinkedList} from "src/libraries/TimestampLinkedList.sol";

contract TimestampLinkedListTest is Test {
    using TimestampLinkedList for TimestampLinkedList.List;

    TimestampLinkedList.List private list;

    function setUp() public {
        // List starts empty
    }

    // ========== EMPTY LIST TESTS ========== //

    function test_emptyList_isEmpty() public view {
        assertTrue(list.isEmpty());
    }

    function test_emptyList_getHead() public view {
        assertEq(list.getHead(), 0);
    }

    function test_emptyList_length() public view {
        assertEq(list.length(), 0);
    }

    function test_emptyList_contains() public view {
        assertFalse(list.contains(100));
        assertFalse(list.contains(0));
    }

    function test_emptyList_findLastBefore() public view {
        assertEq(list.findLastBefore(100), 0);
        assertEq(list.findLastBefore(0), 0);
    }

    function test_emptyList_findFirstAfter() public view {
        assertEq(list.findFirstAfter(100), 0);
        assertEq(list.findFirstAfter(0), 0);
    }

    function test_emptyList_toArray() public view {
        uint48[] memory result = list.toArray();
        assertEq(result.length, 0);
    }

    function test_emptyList_getPrevious() public view {
        assertEq(list.getPrevious(100), 0);
    }

    // ========== SINGLE ELEMENT TESTS ========== //

    function test_singleElement_add() public {
        list.add(100);

        assertFalse(list.isEmpty());
        assertEq(list.getHead(), 100);
        assertEq(list.length(), 1);
        assertTrue(list.contains(100));
        assertFalse(list.contains(99));
    }

    function test_singleElement_findLastBefore() public {
        list.add(100);

        assertEq(list.findLastBefore(150), 100); // Target larger
        assertEq(list.findLastBefore(100), 100); // Target equal
        assertEq(list.findLastBefore(50), 0); // Target smaller
    }

    function test_singleElement_findFirstAfter() public {
        list.add(100);

        assertEq(list.findFirstAfter(50), 100); // Target smaller
        assertEq(list.findFirstAfter(100), 0); // Target equal
        assertEq(list.findFirstAfter(150), 0); // Target larger
    }

    function test_singleElement_toArray() public {
        list.add(100);

        uint48[] memory result = list.toArray();
        assertEq(result.length, 1);
        assertEq(result[0], 100);
    }

    // ========== MULTIPLE ELEMENTS - ASCENDING ORDER ========== //

    function test_multipleElements_addAscending() public {
        list.add(100);
        list.add(200);
        list.add(300);

        assertEq(list.length(), 3);
        assertEq(list.getHead(), 300); // Newest should be head

        // Verify order: 300 -> 200 -> 100
        assertEq(list.getPrevious(300), 200);
        assertEq(list.getPrevious(200), 100);
        assertEq(list.getPrevious(100), 0);
    }

    function test_multipleElements_addAscending_toArray() public {
        list.add(100);
        list.add(200);
        list.add(300);

        uint48[] memory result = list.toArray();
        assertEq(result.length, 3);
        assertEq(result[0], 300); // Descending order
        assertEq(result[1], 200);
        assertEq(result[2], 100);
    }

    // ========== MULTIPLE ELEMENTS - DESCENDING ORDER ========== //

    function test_multipleElements_addDescending() public {
        list.add(300);
        list.add(200);
        list.add(100);

        assertEq(list.length(), 3);
        assertEq(list.getHead(), 300); // Still newest

        // Verify order: 300 -> 200 -> 100
        assertEq(list.getPrevious(300), 200);
        assertEq(list.getPrevious(200), 100);
        assertEq(list.getPrevious(100), 0);
    }

    // ========== MULTIPLE ELEMENTS - MIXED ORDER ========== //

    function test_multipleElements_addMixed() public {
        list.add(200);
        list.add(400);
        list.add(100);
        list.add(300);
        list.add(500);

        assertEq(list.length(), 5);
        assertEq(list.getHead(), 500);

        // Verify descending order maintained: 500 -> 400 -> 300 -> 200 -> 100
        uint48[] memory result = list.toArray();
        assertEq(result[0], 500);
        assertEq(result[1], 400);
        assertEq(result[2], 300);
        assertEq(result[3], 200);
        assertEq(result[4], 100);
    }

    // ========== DUPLICATE HANDLING ========== //

    function test_duplicateAdd_noOp() public {
        list.add(100);
        list.add(200);
        list.add(100); // Duplicate

        assertEq(list.length(), 2); // Should still be 2
        assertTrue(list.contains(100));
        assertTrue(list.contains(200));

        uint48[] memory result = list.toArray();
        assertEq(result.length, 2);
        assertEq(result[0], 200);
        assertEq(result[1], 100);
    }

    // ========== ZERO TIMESTAMP EDGE CASE ========== //

    function test_zeroTimestamp_contains() public {
        assertFalse(list.contains(0)); // Zero should always return false

        list.add(100);
        assertFalse(list.contains(0)); // Still false even with elements
    }

    // ========== BOUNDARY VALUES ========== //

    function test_maxUint48() public {
        uint48 maxVal = type(uint48).max;
        list.add(maxVal);
        list.add(maxVal - 1);

        assertEq(list.getHead(), maxVal);
        assertEq(list.getPrevious(maxVal), maxVal - 1);
    }

    // ========== SEARCH OPERATIONS - COMPREHENSIVE ========== //

    function test_findLastBefore_comprehensive() public {
        // Setup: 500 -> 300 -> 200 -> 100
        list.add(300);
        list.add(100);
        list.add(500);
        list.add(200);

        // Test exact matches
        assertEq(list.findLastBefore(500), 500);
        assertEq(list.findLastBefore(300), 300);
        assertEq(list.findLastBefore(200), 200);
        assertEq(list.findLastBefore(100), 100);

        // Test between values
        assertEq(list.findLastBefore(450), 300); // Between 500 and 300
        assertEq(list.findLastBefore(250), 200); // Between 300 and 200
        assertEq(list.findLastBefore(150), 100); // Between 200 and 100

        // Test boundaries
        assertEq(list.findLastBefore(600), 500); // Larger than all
        assertEq(list.findLastBefore(50), 0); // Smaller than all
        assertEq(list.findLastBefore(0), 0); // Zero
    }

    function test_findFirstAfter_comprehensive() public {
        // Setup: 500 -> 300 -> 200 -> 100
        list.add(300);
        list.add(100);
        list.add(500);
        list.add(200);

        // Test finding next larger values
        assertEq(list.findFirstAfter(50), 100); // Smaller than all -> smallest
        assertEq(list.findFirstAfter(150), 200); // Between 100 and 200 -> 200
        assertEq(list.findFirstAfter(250), 300); // Between 200 and 300 -> 300
        assertEq(list.findFirstAfter(350), 500); // Between 300 and 500 -> 500

        // Test exact matches (should return 0, as we want AFTER)
        assertEq(list.findFirstAfter(100), 200);
        assertEq(list.findFirstAfter(200), 300);
        assertEq(list.findFirstAfter(300), 500);
        assertEq(list.findFirstAfter(500), 0); // Largest value -> none after

        // Test larger than all
        assertEq(list.findFirstAfter(600), 0);
    }

    // ========== CHAIN INTEGRITY ========== //

    function test_chainIntegrity_afterMixedInsertions() public {
        // Add in random order
        uint48[] memory timestamps = new uint48[](7);
        timestamps[0] = 1000;
        timestamps[1] = 300;
        timestamps[2] = 1500;
        timestamps[3] = 700;
        timestamps[4] = 100;
        timestamps[5] = 2000;
        timestamps[6] = 500;

        for (uint256 i = 0; i < timestamps.length; i++) {
            list.add(timestamps[i]);
        }

        // Verify we can traverse the entire chain
        uint48 current = list.getHead();
        uint256 count = 0;
        uint48 previous = type(uint48).max; // Start with max value

        while (current != 0) {
            // Verify descending order
            assertLt(current, previous, "List not in descending order");
            previous = current;
            current = list.getPrevious(current);
            count++;
        }

        assertEq(count, 7, "Chain traversal didn't visit all elements");
    }

    // ========== FUZZ TESTS ========== //

    function testFuzz_addAndFind(uint48[] calldata timestamps) public {
        vm.assume(timestamps.length <= 20); // Reasonable limit for gas

        // Add all timestamps
        for (uint256 i = 0; i < timestamps.length; i++) {
            if (timestamps[i] != 0) {
                // Skip zero values
                list.add(timestamps[i]);
            }
        }

        // Verify all non-zero timestamps can be found
        for (uint256 i = 0; i < timestamps.length; i++) {
            if (timestamps[i] != 0) {
                assertTrue(list.contains(timestamps[i]), "Added timestamp not found");
                assertEq(
                    list.findLastBefore(timestamps[i]),
                    timestamps[i],
                    "findLastBefore failed for exact match"
                );
            }
        }

        // Verify chain integrity
        if (!list.isEmpty()) {
            uint48 current = list.getHead();
            uint48 previous = type(uint48).max;
            bool first = true;

            while (current != 0) {
                if (first) {
                    assertLe(current, previous, "Fuzz test: First element should be <= max");
                    first = false;
                } else {
                    assertLt(current, previous, "Fuzz test: List not in descending order");
                }
                previous = current;
                current = list.getPrevious(current);
            }
        }
    }

    function testFuzz_findLastBefore(uint48 target, uint48[] calldata timestamps) public {
        vm.assume(timestamps.length <= 10);

        // Add timestamps
        for (uint256 i = 0; i < timestamps.length; i++) {
            if (timestamps[i] != 0) {
                list.add(timestamps[i]);
            }
        }

        uint48 result = list.findLastBefore(target);

        if (result != 0) {
            // Result should be <= target
            assertLe(result, target, "findLastBefore returned value > target");

            // Result should exist in the list
            assertTrue(list.contains(result), "findLastBefore returned non-existent timestamp");

            // There should be no element in the list that is > result and <= target
            uint48 current = list.getHead();
            while (current != 0) {
                if (current > result && current <= target) {
                    // solhint-disable-next-line gas-custom-errors
                    revert("Found larger valid timestamp than findLastBefore result");
                }
                current = list.getPrevious(current);
            }
        }
    }
}
