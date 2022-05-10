// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/users.sol";
import "test-utils/mocking.sol";
import "test-utils/sorting.sol";

import {OlympusIndex} from "src/modules/INDEX.sol";
//import {BaseKernel, Actions} from "src/Kernel.sol";
import {LarpKernel} from "./LarpKernel.sol";

contract IndexTest is Test {
    using mocking for *;
    using sorting for uint256[];

    LarpKernel kernel;
    OlympusIndex index;
    ERC20 ohm;

    uint256 constant INITIAL_INDEX = 10e6;

    function setUp() public {
        kernel = new LarpKernel();
        index = new OlympusIndex(kernel, INITIAL_INDEX);
    }

    function testKEYCODE() public {
        assertEq32("INDEX", index.KEYCODE());
    }

    function testIncreaseIndex(uint256 rate_) public {
        vm.assume(rate_ > 0);

        assertEq(index.increaseIndex(rate_), (INITIAL_INDEX * rate_) / 1e6);
    }

    function testLastUpdated() public {
        assertEq(index.lastUpdated(), block.timestamp);
        vm.warp(block.timestamp + 1);
        index.increaseIndex(1);
        assertEq(index.lastUpdated(), block.timestamp);
    }
}
