// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract ERC7726OracleFactoryDisableOracleTest is ERC7726OracleFactoryTest {
    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled givenOracleIsCreated {
        vm.assume(caller_ != admin && caller_ != oracleManager && caller_ != emergency);

        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        factory.disableOracle(oracle);
    }

    function test_whenFactoryIsDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenFactoryIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        factory.disableOracle(oracle);
    }

    function test_whenOracleDoesNotExist_reverts() public givenFactoryIsEnabled {
        address nonExistentOracle = makeAddr("NON_EXISTENT_ORACLE");

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidOracle.selector,
                nonExistentOracle
            )
        );

        vm.prank(admin);
        factory.disableOracle(nonExistentOracle);
    }

    function test_whenOracleIsAlreadyDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_OracleAlreadyDisabled.selector,
                oracle
            )
        );

        vm.prank(admin);
        factory.disableOracle(oracle);
    }

    function test_success() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectEmit(true, false, false, false);
        emit IERC7726OracleFactory.OracleDisabled(oracle);

        vm.prank(admin);
        factory.disableOracle(oracle);

        assertFalse(factory.isOracleEnabled(oracle), "Oracle should be disabled");
    }

    function test_whenCallerHasOracleManagerRole()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.prank(oracleManager);
        factory.disableOracle(oracle);

        assertFalse(factory.isOracleEnabled(oracle), "Oracle should be disabled");
    }

    function test_whenCallerHasManagerRole_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(manager);
        factory.disableOracle(oracle);
    }

    function test_whenCallerHasAdminRole() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.prank(admin);
        factory.disableOracle(oracle);
    }

    function test_whenCallerHasEmergencyRole() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.prank(emergency);
        factory.disableOracle(oracle);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
