// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {Actions} from "src/Kernel.sol";
import {IERC7726OracleFactory} from "src/policies/interfaces/price/IERC7726OracleFactory.sol";
import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";

contract ERC7726OracleFactoryGetOracleContextTest is ERC7726OracleFactoryTest {
    function test_whenOracleIsEnabled_returnsEnabledAndPriceCache()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        (bool enabled, address policy) = factory.getOracleContext(oracle);

        assertTrue(enabled, "Oracle should be enabled");
        assertEq(policy, address(priceCache), "Price cache should match configured policy");
    }

    function test_whenFactoryIsDisabled_returnsDisabledAndPriceCache()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenFactoryIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        (bool enabled, address policy) = factory.getOracleContext(oracle);

        assertFalse(enabled, "Oracle should be disabled when factory is disabled");
        assertEq(policy, address(priceCache), "Price cache should match configured policy");
    }

    function test_whenOracleDoesNotExist_reverts() public givenFactoryIsEnabled {
        address oracle = makeAddr("NON_EXISTENT_ORACLE");

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726OracleFactory.ERC7726OracleFactory_InvalidOracle.selector,
                oracle
            )
        );
        factory.getOracleContext(oracle);
    }

    function test_whenOracleIsDisabled_returnsDisabledAndPriceCache()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);

        (bool enabled, address policy) = factory.getOracleContext(oracle);

        assertFalse(enabled, "Oracle should be disabled");
        assertEq(policy, address(priceCache), "Price cache should match configured policy");
    }

    function test_whenFactoryPolicyIsDeactivated_reverts()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
    {
        address oracle = factory.getOracle(DEFAULT_MAX_AGE);
        kernel.executeAction(Actions.DeactivatePolicy, address(factory));

        vm.expectRevert(IERC7726OracleFactory.ERC7726OracleFactory_PolicyNotActive.selector);
        factory.getOracleContext(oracle);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
