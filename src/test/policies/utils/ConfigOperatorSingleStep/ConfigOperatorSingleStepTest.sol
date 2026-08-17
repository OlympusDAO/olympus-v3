// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {ConfigOperatorSingleStepHarness} from "src/test/policies/utils/ConfigOperatorSingleStep/fixtures/ConfigOperatorSingleStepHarness.sol";

abstract contract ConfigOperatorSingleStepTest is Test {
    address internal authorizedCaller;
    address internal operator;
    address internal other;

    ConfigOperatorSingleStepHarness internal configOperator;

    function setUp() public virtual {
        authorizedCaller = makeAddr("authorizedCaller");
        operator = makeAddr("operator");
        other = makeAddr("other");
        configOperator = new ConfigOperatorSingleStepHarness(authorizedCaller);
    }
}
