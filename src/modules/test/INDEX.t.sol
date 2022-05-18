// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/larping.sol";

import {OlympusIndex} from "src/modules/INDEX.sol";
import {LarpKernel} from "../../test/utils/LarpKernel.sol";

contract IndexTest is Test {
    using larping for *;
    using console2 for uint256;

    LarpKernel kernel;
    OlympusIndex index;
    ERC20 ohm;

    uint256 constant INITIAL_INDEX = 10 * RATE_UNITS;
    uint256 constant RATE_UNITS = 1e6;

    function setUp() public {
        kernel = new LarpKernel();
        index = new OlympusIndex(kernel, INITIAL_INDEX);

        kernel.installModule(address(index));
        kernel.grantWritePermissions(index.KEYCODE(), address(this));
    }

    function test_KEYCODE() public {
        assertEq32("INDEX", index.KEYCODE());
    }

    function test_IncreaseIndex(uint256 rate_) public {
        vm.assume(rate_ > 0);
        vm.assume(rate_ < RATE_UNITS); // Rate should be less than 1000%

        uint256 indexBefore = index.index();

        assertEq(
            index.increaseIndex(rate_),
            (indexBefore * (RATE_UNITS + rate_)) / RATE_UNITS
        );
    }

    function test_LastUpdated() public {
        assertEq(index.lastUpdated(), block.timestamp);

        vm.warp(block.timestamp + 1);
        index.increaseIndex(1);

        assertEq(index.lastUpdated(), block.timestamp);
    }
}
