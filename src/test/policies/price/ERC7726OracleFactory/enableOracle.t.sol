// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract ERC7726OracleFactoryEnableOracleTest is ERC7726OracleFactoryTest {
    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled givenOracleIsCreated givenOracleIsDisabled {
        vm.assume(caller_ != admin && caller_ != oracleManager);

        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        factory.enableOracle(oracle);
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
        factory.enableOracle(oracle);
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
        factory.enableOracle(nonExistentOracle);
    }

    function test_whenOracleIsAlreadyEnabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_OracleAlreadyEnabled.selector,
                oracle
            )
        );

        vm.prank(admin);
        factory.enableOracle(oracle);
    }

    function test_success()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectEmit(true, false, false, false);
        emit IERC7726OracleFactory.OracleEnabled(oracle);

        vm.prank(admin);
        factory.enableOracle(oracle);

        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    function test_whenCallerHasOracleManagerRole()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.prank(oracleManager);
        factory.enableOracle(oracle);

        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    function test_whenCallerHasManagerRole_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(manager);
        factory.enableOracle(oracle);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
