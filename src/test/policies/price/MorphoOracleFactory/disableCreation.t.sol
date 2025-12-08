// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IMorphoOracleFactory} from "src/policies/interfaces/price/IMorphoOracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract MorphoOracleFactoryDisableCreationTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when caller does not have the admin, manager, oracle_manager or emergency role
    //  [X] it reverts with NotAuthorised

    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(
            caller_ != admin &&
                caller_ != manager &&
                caller_ != oracleManager &&
                caller_ != emergency
        );

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);

        vm.prank(caller_);
        factory.disableCreation();
    }

    // when factory is disabled
    //  [X] it reverts with NotEnabled

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.disableCreation();
    }

    // when creation is already disabled
    //  [X] it reverts with CreationAlreadyDisabled

    function test_whenCreationIsAlreadyDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
    {
        vm.expectRevert(IMorphoOracleFactory.MorphoOracleFactory_CreationAlreadyDisabled.selector);

        vm.prank(admin);
        factory.disableCreation();
    }

    // when creation is enabled
    //  [X] it disables creation
    //  [X] it emits CreationDisabled event

    function test_success() public givenFactoryIsEnabled {
        vm.expectEmit(false, false, false, false);
        emit IMorphoOracleFactory.CreationDisabled();

        vm.prank(admin);
        factory.disableCreation();

        assertFalse(factory.isCreationEnabled(), "Creation should be disabled");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
