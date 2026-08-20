// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {Actions} from "src/Kernel.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";

contract ERC7726OracleFactoryIsOracleEnabledTest is ERC7726OracleFactoryTest {
    function test_givenFactoryIsEnabled_givenOracleIsCreated_isOracleEnabled_returnsTrue()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        assertTrue(factory.isOracleEnabled(oracle), "Oracle should be enabled");
    }

    function test_givenFactoryIsEnabled_givenOracleIsCreated_whenFactoryPolicyDeactivated_isOracleEnabled_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IERC7726OracleFactory.ERC7726OracleFactory_PolicyNotActive.selector);
        factory.isOracleEnabled(oracle);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
