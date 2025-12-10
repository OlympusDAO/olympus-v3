// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {AggregatorV2V3Interface, AggregatorV3Interface, AggregatorInterface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IChainlinkOracle} from "src/policies/interfaces/price/IChainlinkOracle.sol";
import {ChainlinkOracleCloneableTest} from "./ChainlinkOracleCloneableTest.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ChainlinkOracleCloneableSupportsInterfaceTest is ChainlinkOracleCloneableTest {
    // ========== TESTS ========== //

    // supportsInterface
    //  [X] it returns true for IChainlinkOracle
    //  [X] it returns true for AggregatorV2V3Interface
    //  [X] it returns true for AggregatorV3Interface
    //  [X] it returns true for AggregatorInterface
    //  [X] it returns true for IERC165

    function test_supportsInterface_returnsTrueForSupportedInterfaces() public view {
        ERC165Helper.validateSupportsInterface(address(oracle));
        assertTrue(
            IERC165(address(oracle)).supportsInterface(type(IChainlinkOracle).interfaceId),
            "Should support IChainlinkOracle"
        );
        assertTrue(
            IERC165(address(oracle)).supportsInterface(type(AggregatorV2V3Interface).interfaceId),
            "Should support AggregatorV2V3Interface"
        );
        assertTrue(
            IERC165(address(oracle)).supportsInterface(type(AggregatorV3Interface).interfaceId),
            "Should support AggregatorV3Interface"
        );
        assertTrue(
            IERC165(address(oracle)).supportsInterface(type(AggregatorInterface).interfaceId),
            "Should support AggregatorInterface"
        );
        assertTrue(
            IERC165(address(oracle)).supportsInterface(type(IERC165).interfaceId),
            "Should support IERC165"
        );
        assertFalse(
            IERC165(address(oracle)).supportsInterface(type(IERC20).interfaceId),
            "Should not support IERC20"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
