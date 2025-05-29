// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

contract MockRevert {
    function div(uint256 numerator, uint256 denominator) external pure returns (uint256) {
        return numerator / denominator;
    }
}

contract MockException {
    function tryDiv(
        MockRevert theContract,
        uint256 numerator,
        uint256 denominator
    ) external pure returns (uint256, bool) {
        try theContract.div(numerator, denominator) returns (uint256 v) {
            return (v, true);
        } catch Panic(uint256 errorCode) {
            return (errorCode, false);
        }
    }
}

contract TestException is Test {
    function test_tryDiv() public {
        MockRevert mockRevert = new MockRevert();
        MockException mockException = new MockException();
        (uint256 answer, bool success) = mockException.tryDiv(mockRevert, 100, 20);
        assertEq(answer, 5);
        assertEq(success, true);

        (answer, success) = mockException.tryDiv(mockRevert, 100, 0);

        assertEq(answer, 18);
        assertEq(success, false);
    }
}
