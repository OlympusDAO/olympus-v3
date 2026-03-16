// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";

contract MorphoOracleFactoryGetOracleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when oracle exists
    //  [X] it returns oracle address

    function test_whenOracleExists() public givenFactoryIsEnabled {
        address oracle = _createOracle(
            address(collateralToken),
            address(loanToken),
            DEFAULT_MAX_AGE
        );

        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE),
            oracle,
            "Should return oracle address"
        );
        assertEq(
            factory.getOracle(address(loanToken), address(collateralToken), DEFAULT_MAX_AGE),
            address(0),
            "There should be no oracle for a different ordering"
        );
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE + 1),
            address(0),
            "There should be no oracle for a different maxAge"
        );
    }

    // when oracle does not exist
    //  [X] it returns address(0)

    function test_whenOracleDoesNotExist() public view {
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken), DEFAULT_MAX_AGE),
            address(0),
            "Should return address(0) when oracle does not exist"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
