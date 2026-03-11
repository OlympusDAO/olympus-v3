// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";

contract MorphoOracleFactoryGetPriceModuleTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when PRICE module is set
    //  [X] it returns PRICE module address

    function test_whenPRICEModuleIsSet() public view {
        assertEq(
            factory.getPriceModule(),
            address(priceModule),
            "Should return PRICE module address"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
