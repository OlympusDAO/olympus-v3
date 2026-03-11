// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";

contract MorphoOracleFactoryGetOracleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when oracle exists
    //  [X] it returns oracle address

    function test_whenOracleExists() public givenFactoryIsEnabled {
        address oracle = _createOracle(address(collateralToken), address(loanToken));

        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken)),
            oracle,
            "Should return oracle address"
        );
        assertEq(
            factory.getOracle(address(loanToken), address(collateralToken)),
            address(0),
            "There should be no oracle for a different ordering"
        );
    }

    // when oracle does not exist
    //  [X] it returns address(0)

    function test_whenOracleDoesNotExist() public view {
        assertEq(
            factory.getOracle(address(collateralToken), address(loanToken)),
            address(0),
            "Should return address(0) when oracle does not exist"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
