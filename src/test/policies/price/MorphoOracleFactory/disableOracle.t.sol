// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IMorphoOracleFactory} from "src/policies/interfaces/price/IMorphoOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract MorphoOracleFactoryDisableOracleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when caller does not have the admin, manager, oracle_manager, or emergency role
    //  [X] it reverts with NotAuthorised

    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled givenOracleIsCreated {
        vm.assume(
            caller_ != admin &&
                caller_ != manager &&
                caller_ != oracleManager &&
                caller_ != emergency
        );

        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.disableOracle(oracle);
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
        factory.disableOracle(oracle);
    }

    // when oracle does not exist
    //  [X] it reverts with InvalidOracle

    function test_whenOracleDoesNotExist_reverts() public givenFactoryIsEnabled {
        address nonExistentOracle = makeAddr("NON_EXISTENT_ORACLE");

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_InvalidOracle.selector,
                nonExistentOracle
            )
        );

        vm.prank(admin);
        factory.disableOracle(nonExistentOracle);
    }

    // when oracle is already disabled
    //  [X] it reverts with OracleAlreadyDisabled

    function test_whenOracleIsAlreadyDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracleFactory.MorphoOracleFactory_OracleAlreadyDisabled.selector,
                oracle
            )
        );

        vm.prank(admin);
        factory.disableOracle(oracle);
    }

    // when oracle is enabled
    //  [X] it disables oracle
    //  [X] it emits OracleDisabled event

    function test_success() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.expectEmit(true, false, false, false);
        emit IMorphoOracleFactory.OracleDisabled(oracle);

        vm.prank(admin);
        factory.disableOracle(oracle);

        assertFalse(factory.isOracleEnabled(oracle), "Oracle should be disabled");
    }

    // when the caller has the oracle_manager role
    //  [X] it succeeds

    function test_whenCallerHasOracleManagerRole()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.prank(oracleManager);
        factory.disableOracle(oracle);

        assertFalse(factory.isOracleEnabled(oracle), "Oracle should be disabled");
    }

    // when the caller has the manager role
    //  [X] it succeeds

    function test_whenCallerHasManagerRole() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.prank(manager);
        factory.disableOracle(oracle);

        assertFalse(factory.isOracleEnabled(oracle), "Oracle should be disabled");
    }

    // when the caller has the admin role
    //  [X] it succeeds

    function test_whenCallerHasAdminRole() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.prank(admin);
        factory.disableOracle(oracle);
    }

    // when the caller has the emergency role
    //  [X] it succeeds

    function test_whenCallerHasEmergencyRole() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        vm.prank(emergency);
        factory.disableOracle(oracle);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
