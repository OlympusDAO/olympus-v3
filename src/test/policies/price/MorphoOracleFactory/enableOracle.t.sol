// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract MorphoOracleFactoryEnableOracleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when caller does not have the admin, manager, or oracle_manager role
    //  [X] it reverts with NotAuthorised

    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled givenOracleIsCreated givenOracleIsDisabled {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.assume(caller_ != admin && caller_ != manager && caller_ != oracleManager);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.enableOracle(oracle);
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenFactoryIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.enableOracle(oracle);
    }

    // when oracle does not exist
    //  [X] it reverts with InvalidOracle

    function test_whenOracleDoesNotExist_reverts() public givenFactoryIsEnabled {
        address nonExistentOracle = makeAddr("NON_EXISTENT_ORACLE");

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidOracle.selector,
                nonExistentOracle
            )
        );

        vm.prank(admin);
        factory.enableOracle(nonExistentOracle);
    }

    // when oracle is already enabled
    //  [X] it reverts with OracleAlreadyEnabled

    function test_whenOracleIsAlreadyEnabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_OracleAlreadyEnabled.selector,
                oracle
            )
        );

        vm.prank(admin);
        factory.enableOracle(oracle);
    }

    // when oracle is disabled
    //  [X] it enables oracle
    //  [X] it emits OracleEnabled event

    function test_success()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.expectEmit(true, false, false, false);
        emit IOracleFactory.OracleEnabled(oracle);

        vm.prank(admin);
        factory.enableOracle(oracle);

        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    // when the caller has the oracle_manager role
    //  [X] it succeeds

    function test_whenCallerHasOracleManagerRole()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.prank(oracleManager);
        factory.enableOracle(oracle);

        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    // when the caller has the manager role
    //  [X] it succeeds

    function test_whenCallerHasManagerRole()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.prank(manager);
        factory.enableOracle(oracle);

        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
