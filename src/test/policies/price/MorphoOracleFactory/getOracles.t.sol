// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";

contract MorphoOracleFactoryGetOraclesTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // when no oracles exist
    //  [X] it returns empty array

    function test_whenNoOraclesExist_returnsEmptyArray() public view {
        address[] memory oracles = factory.getOracles();

        assertEq(oracles.length, 0, "Should return empty array when no oracles exist");
    }

    // when one oracle exists
    //  [X] it returns array with one oracle

    function test_whenOneOracleExists_returnsArrayWithOneOracle() public givenFactoryIsEnabled {
        address oracle = _createOracle(address(collateralToken), address(loanToken));

        address[] memory oracles = factory.getOracles();

        assertEq(oracles.length, 1, "Should return array with one oracle");
        assertEq(oracles[0], oracle, "Should contain the created oracle");
    }

    // when multiple oracles exist
    //  [X] it returns array with all oracles

    function test_whenMultipleOraclesExist_returnsArrayWithAllOracles()
        public
        givenFactoryIsEnabled
    {
        // Create first oracle
        address oracle1 = _createOracle(address(collateralToken), address(loanToken));

        // Create second oracle with different tokens
        MockERC20 collateralToken2 = new MockERC20("Collateral Token 2", "COL2", 18);
        MockERC20 loanToken2 = new MockERC20("Loan Token 2", "LOAN2", 18);
        _setPRICEPrices(address(collateralToken2), 3e18);
        _setPRICEPrices(address(loanToken2), 1e18);

        address oracle2 = _createOracle(address(collateralToken2), address(loanToken2));

        // Create third oracle
        MockERC20 collateralToken3 = new MockERC20("Collateral Token 3", "COL3", 18);
        MockERC20 loanToken3 = new MockERC20("Loan Token 3", "LOAN3", 18);
        _setPRICEPrices(address(collateralToken3), 4e18);
        _setPRICEPrices(address(loanToken3), 1e18);

        address oracle3 = _createOracle(address(collateralToken3), address(loanToken3));

        address[] memory oracles = factory.getOracles();

        assertEq(oracles.length, 3, "Should return array with three oracles");
        assertEq(oracles[0], oracle1, "Should contain first oracle");
        assertEq(oracles[1], oracle2, "Should contain second oracle");
        assertEq(oracles[2], oracle3, "Should contain third oracle");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
