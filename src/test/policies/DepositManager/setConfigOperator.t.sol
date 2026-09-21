// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerSetConfigOperatorTest is DepositManagerTest {
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN);

        _expectRevertNotAdmin();
        vm.prank(caller_);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
    }

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
    }

    function test_whenConfigOperatorIsNonzero_setsConfigOperator() public givenIsEnabled {
        vm.expectEmit(true, false, false, true, address(depositManager));
        emit IConfigOperator.ConfigOperatorSet(CONFIG_OPERATOR);

        _setConfigOperator(CONFIG_OPERATOR);

        assertEq(
            depositManager.configOperator(),
            CONFIG_OPERATOR,
            "config operator should be stored"
        );
    }

    function test_whenConfigOperatorIsZero_revokesConfigOperator() public givenIsEnabled {
        _setConfigOperator(CONFIG_OPERATOR);

        vm.expectEmit(true, false, false, true, address(depositManager));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        _setConfigOperator(address(0));

        assertEq(depositManager.configOperator(), address(0), "config operator should be cleared");
    }
}
