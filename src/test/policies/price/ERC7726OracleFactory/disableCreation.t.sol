// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract ERC7726OracleFactoryDisableCreationTest is ERC7726OracleFactoryTest {
    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin && caller_ != oracleManager && caller_ != emergency);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        factory.disableCreation();
    }

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.disableCreation();
    }

    function test_whenCreationIsAlreadyDisabled_reverts()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
    {
        vm.expectRevert(
            IERC7726OracleFactory.ERC7726OracleFactory_CreationAlreadyDisabled.selector
        );

        vm.prank(admin);
        factory.disableCreation();
    }

    function test_success() public givenFactoryIsEnabled {
        vm.expectEmit(false, false, false, false);
        emit IERC7726OracleFactory.CreationDisabled();

        vm.prank(admin);
        factory.disableCreation();

        assertFalse(factory.isCreationEnabled(), "Creation should be disabled");
    }

    function test_whenCallerHasOracleManagerRole_succeeds() public givenFactoryIsEnabled {
        vm.prank(oracleManager);
        factory.disableCreation();

        assertFalse(factory.isCreationEnabled(), "Creation should be disabled");
    }

    function test_whenCallerHasEmergencyRole_succeeds() public givenFactoryIsEnabled {
        vm.prank(emergency);
        factory.disableCreation();

        assertFalse(factory.isCreationEnabled(), "Creation should be disabled");
    }

    function test_whenCallerHasManagerRole_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(manager);
        factory.disableCreation();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
