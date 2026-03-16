// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract ERC7726OracleFactoryEnableCreationTest is ERC7726OracleFactoryTest {
    function test_whenCallerDoesNotHaveRequiredRole_reverts(
        address caller_
    ) public givenFactoryIsEnabled {
        vm.assume(caller_ != admin && caller_ != oracleManager);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        factory.enableCreation();
    }

    function test_whenFactoryIsDisabled_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);

        vm.prank(admin);
        factory.enableCreation();
    }

    function test_whenCreationIsAlreadyEnabled_reverts()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
        givenCreationIsEnabled
    {
        vm.expectRevert(IERC7726OracleFactory.ERC7726OracleFactory_CreationAlreadyEnabled.selector);

        vm.prank(admin);
        factory.enableCreation();
    }

    function test_success() public givenFactoryIsEnabled givenCreationIsDisabled {
        vm.expectEmit(false, false, false, false);
        emit IERC7726OracleFactory.CreationEnabled();

        vm.prank(admin);
        factory.enableCreation();

        assertTrue(factory.isCreationEnabled(), "Creation should be enabled");
    }

    function test_whenCallerHasOracleManagerRole_succeeds()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
    {
        vm.prank(oracleManager);
        factory.enableCreation();

        assertTrue(factory.isCreationEnabled(), "Creation should be enabled");
    }

    function test_whenCallerHasManagerRole_reverts()
        public
        givenFactoryIsEnabled
        givenCreationIsDisabled
    {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(manager);
        factory.enableCreation();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
