// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

// Contracts
import {ConfigOperatorSingleStepHarness} from "src/test/policies/utils/ConfigOperatorSingleStep/fixtures/ConfigOperatorSingleStepHarness.sol";

abstract contract ConfigOperatorSingleStepTest is Test {
    address internal _authorizedCaller;
    address internal _operator;
    address internal _other;

    ConfigOperatorSingleStepHarness internal _configOperator;

    function setUp() public virtual {
        _authorizedCaller = makeAddr("authorizedCaller");
        _operator = makeAddr("operator");
        _other = makeAddr("other");
        _configOperator = new ConfigOperatorSingleStepHarness(_authorizedCaller);
    }

    modifier givenExistingOperator() {
        vm.prank(_authorizedCaller);
        _configOperator.setConfigOperator(_operator);
        _;
    }
}
