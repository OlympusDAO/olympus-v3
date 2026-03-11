// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";

contract MorphoOracleFactoryIsOracleEnabledTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when factory is disabled
    //  [X] it returns false

    function test_whenFactoryIsDisabled()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenFactoryIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        assertFalse(
            factory.isOracleEnabled(oracle),
            "Should return false when factory is disabled"
        );
    }

    // when oracle does not exist
    //  [X] it returns false

    function test_whenOracleDoesNotExist() public givenFactoryIsEnabled {
        address nonExistentOracle = makeAddr("NON_EXISTENT_ORACLE");

        assertFalse(
            factory.isOracleEnabled(nonExistentOracle),
            "Should return false when oracle does not exist"
        );
    }

    // when oracle creation is disabled
    //  [X] it returns the status of the oracle

    function test_whenOracleCreationIsDisabled()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenCreationIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        assertTrue(
            factory.isOracleEnabled(oracle),
            "Should return oracle status when oracle creation is disabled"
        );
    }

    // when oracle is disabled
    //  [X] it returns false

    function test_whenOracleIsDisabled()
        public
        givenFactoryIsEnabled
        givenOracleIsCreated
        givenOracleIsDisabled
    {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        assertFalse(factory.isOracleEnabled(oracle), "Should return false when oracle is disabled");
    }

    // when oracle is enabled
    //  [X] it returns true

    function test_whenOracleIsEnabled() public givenFactoryIsEnabled givenOracleIsCreated {
        address oracle = factory.getOracle(address(collateralToken), address(loanToken));

        assertTrue(factory.isOracleEnabled(oracle), "Should return true when oracle is enabled");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
