// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "libraries/SafeCast.sol";

contract SafeCastTest is Test {
    function test_encodeUInt128_success() public pure {
        assertEq(SafeCast.encodeUInt128(uint256(type(uint128).max)), type(uint128).max);
        assertEq(SafeCast.encodeUInt128(uint256(0)), uint128(0));
    }

    function test_encodeUInt128_failure() public {
        uint256 x = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, x));
        SafeCast.encodeUInt128(x);
    }

    function test_encodeUInt112_success() public pure {
        assertEq(SafeCast.encodeUInt112(uint256(type(uint112).max)), type(uint112).max);
        assertEq(SafeCast.encodeUInt112(uint256(0)), uint112(0));
    }

    function test_encodeUInt112_failure() public {
        uint256 x = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, x));
        SafeCast.encodeUInt128(x);
    }
}
