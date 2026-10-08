// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerSetConfigOperatorTest is DepositManagerTest {
    modifier givenConfigOperatorIsSet() {
        _setConfigOperator(CONFIG_OPERATOR);
        _;
    }

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

    // given the config operator is set
    //  given the contract is disabled
    //   when the config operator is unchanged
    //    [X] it reverts with NotEnabled
    // The enabled-state check answers before the unchanged check
    function test_givenConfigOperatorIsSet_givenContractIsDisabled_whenConfigOperatorIsUnchanged_reverts()
        public
        givenIsEnabled
        givenConfigOperatorIsSet
        givenIsDisabled
    {
        _expectRevertNotEnabled();
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);

        assertEq(
            depositManager.configOperator(),
            CONFIG_OPERATOR,
            "config operator should be unchanged"
        );
    }

    // given the config operator is set
    //  when the caller is not admin
    //   when the config operator is unchanged
    //    [X] it reverts with ROLES_RequireRole
    // The admin-role check answers before the unchanged check
    function test_givenConfigOperatorIsSet_whenCallerIsNotAdmin_whenConfigOperatorIsUnchanged_reverts(
        address caller_
    ) public givenIsEnabled givenConfigOperatorIsSet {
        vm.assume(caller_ != ADMIN);

        _expectRevertNotAdmin();
        vm.prank(caller_);
        depositManager.setConfigOperator(CONFIG_OPERATOR);

        assertEq(
            depositManager.configOperator(),
            CONFIG_OPERATOR,
            "config operator should be unchanged"
        );
    }

    // given the config operator is set
    //  when the config operator is unchanged
    //   [X] it reverts with ConfigOperator_Unchanged
    //   [X] it keeps the config operator
    function test_givenConfigOperatorIsSet_whenConfigOperatorIsUnchanged_reverts()
        public
        givenIsEnabled
        givenConfigOperatorIsSet
    {
        vm.expectRevert(abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unchanged.selector));
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);

        assertEq(
            depositManager.configOperator(),
            CONFIG_OPERATOR,
            "config operator should be unchanged"
        );
    }

    // given the config operator is unset
    //  when the config operator is zero
    //   [X] it reverts with ConfigOperator_Unchanged
    // Zero is a value in its own right: clearing an operator that is already unset is an
    // unchanged write, not a no-op
    function test_givenConfigOperatorIsUnset_whenConfigOperatorIsZero_reverts()
        public
        givenIsEnabled
    {
        assertEq(depositManager.configOperator(), address(0), "config operator should start unset");

        vm.expectRevert(abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unchanged.selector));
        vm.prank(ADMIN);
        depositManager.setConfigOperator(address(0));

        assertEq(depositManager.configOperator(), address(0), "config operator should stay unset");
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
