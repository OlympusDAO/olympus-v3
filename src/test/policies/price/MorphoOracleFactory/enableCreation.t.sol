// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IMorphoOracleFactory} from "src/policies/interfaces/price/IMorphoOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract MorphoOracleFactoryEnableCreationTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when caller does not have the admin, manager, or oracle_manager role
    //  [X] it reverts with NotAuthorised

    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin && caller_ != manager && caller_ != oracleManager);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.enableCreation();
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.enableCreation();
    }

    // when creation is already enabled
    //  [X] it reverts with CreationAlreadyEnabled

    function test_whenCreationIsAlreadyEnabled_reverts()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
        givenCreationIsEnabled
    {
        vm.expectRevert(IMorphoOracleFactory.MorphoOracleFactory_CreationAlreadyEnabled.selector);

        vm.prank(admin);
        factory.enableCreation();
    }

    // when creation is disabled
    //  [X] it enables creation
    //  [X] it emits CreationEnabled event

    function test_success() public givenFactoryIsEnabled givenCreationIsDisabled {
        vm.expectEmit(false, false, false, false);
        emit IMorphoOracleFactory.CreationEnabled();

        vm.prank(admin);
        factory.enableCreation();

        assertTrue(factory.isCreationEnabled(), "Creation should be enabled");
    }

    // when the caller has the oracle_manager role
    //  [X] it succeeds

    function test_whenCallerHasOracleManagerRole()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
    {
        vm.prank(oracleManager);
        factory.enableCreation();

        assertTrue(factory.isCreationEnabled(), "Creation should be enabled");
    }

    // when the caller has the manager role
    //  [X] it succeeds

    function test_whenCallerHasManagerRole() public givenFactoryIsEnabled givenCreationIsDisabled {
        vm.prank(manager);
        factory.enableCreation();

        assertTrue(factory.isCreationEnabled(), "Creation should be enabled");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
