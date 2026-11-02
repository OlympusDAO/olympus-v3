// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";

contract BurnerLoansConfigVERSIONTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-VERSION-P01.
    function test_whenVersionRead(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _config.VERSION();
        assertEq(major, 1, "Major version");
        assertEq(minor, 0, "Minor version");
    }
}
