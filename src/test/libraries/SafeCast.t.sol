// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "libraries/SafeCast.sol";

contract SafeCastTest is Test {
    function test_encodeUInt96_success() public pure {
        assertEq(SafeCast.encodeUInt96(uint256(type(uint96).max)), type(uint96).max);
        assertEq(SafeCast.encodeUInt96(uint256(0)), uint96(0));
    }

    function test_encodeUInt128_success() public pure {
        assertEq(SafeCast.encodeUInt128(uint256(type(uint128).max)), type(uint128).max);
        assertEq(SafeCast.encodeUInt128(uint256(0)), uint128(0));
    }

    function test_encodeUInt128_failure() public {
        uint256 x = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, x));
        SafeCast.encodeUInt128(x);
    }
}
