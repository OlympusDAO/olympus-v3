// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleCloneable} from "src/policies/price/ChainlinkOracleCloneable.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";

contract ChainlinkOracleCloneableImmutableArgsTest is ChainlinkOracleCloneableTest {
    // ========== TESTS ========== //

    // factory
    //  [X] it returns factory address from immutable args

    function test_factory() public view {
        // Cast to access factory() function which is not in the interface
        ChainlinkOracleCloneable oracleContract = ChainlinkOracleCloneable(address(oracle));
        assertEq(
            address(oracleContract.factory()),
            address(factory),
            "Should return factory address"
        );
    }

    // baseToken
    //  [X] it returns base token address from immutable args

    function test_baseToken() public view {
        assertEq(oracle.baseToken(), address(baseToken), "Should return base token address");
    }

    // quoteToken
    //  [X] it returns quote token address from immutable args

    function test_quoteToken() public view {
        assertEq(oracle.quoteToken(), address(quoteToken), "Should return quote token address");
    }

    // decimals
    //  [X] it returns PRICE decimals from immutable args

    function test_decimals() public view {
        assertEq(oracle.decimals(), PRICE_DECIMALS, "Should return PRICE decimals");
    }

    // name
    //  [X] it returns name from immutable args

    function test_name() public view {
        assertEq(oracle.name(), "BASE/QUOTE Chainlink Oracle", "Should return correct name");
    }

    // description
    //  [X] it returns name (same as description)

    function test_description() public view {
        assertEq(oracle.description(), oracle.name(), "Description should equal name");
    }

    // version
    //  [X] it returns version 1

    function test_version() public view {
        assertEq(oracle.version(), 1, "Should return version 1");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
