// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableImmutableArgsTest is MorphoOracleCloneableTest {
    // ========== TESTS ========== //

    // factory
    //  [X] it returns factory address from immutable args

    function test_factory() public view {
        // Cast to access factory() function which is not in the interface
        MorphoOracleCloneable oracleContract = MorphoOracleCloneable(address(oracle));
        assertEq(
            address(oracleContract.factory()),
            address(factory),
            "Should return factory address"
        );
    }

    // collateralToken
    //  [X] it returns collateral token address from immutable args

    function test_collateralToken() public view {
        assertEq(
            oracle.collateralToken(),
            address(collateralToken),
            "Should return collateral token address"
        );
    }

    // loanToken
    //  [X] it returns loan token address from immutable args

    function test_loanToken() public view {
        assertEq(oracle.loanToken(), address(loanToken), "Should return loan token address");
    }

    // scaleFactor
    //  [X] it returns scale factor from immutable args

    function test_scaleFactor() public view {
        // Scale factor = 10^(36 + loanDecimals - collateralDecimals)
        // Both tokens have 18 decimals, so scale factor = 10^36
        uint256 expectedScaleFactor = 10 ** (36 + 18 - 18); // 10^36

        assertEq(oracle.scaleFactor(), expectedScaleFactor, "Should return correct scale factor");
    }

    // name
    //  [X] it returns name from immutable args

    function test_name() public view {
        assertEq(oracle.name(), "COL/LOAN Morpho Oracle", "Should return correct name");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
