// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleCloneable} from "src/policies/price/MorphoOracleCloneable.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {IOracle} from "src/interfaces/morpho/IOracle.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

contract MorphoOracleCloneableSupportsInterfaceTest is MorphoOracleCloneableTest {
    // ========== TESTS ========== //

    // supportsInterface
    // when interface is IMorphoOracle
    //  [X] it returns true

    function test_whenInterfaceIsIMorphoOracle() public view {
        MorphoOracleCloneable oracleContract = MorphoOracleCloneable(address(oracle));
        assertTrue(
            oracleContract.supportsInterface(type(IMorphoOracle).interfaceId),
            "Should return true for IMorphoOracle interface"
        );
    }

    // when interface is IOracle (from Morpho)
    //  [X] it returns true

    function test_whenInterfaceIsIOracle() public view {
        MorphoOracleCloneable oracleContract = MorphoOracleCloneable(address(oracle));
        assertTrue(
            oracleContract.supportsInterface(type(IOracle).interfaceId),
            "Should return true for IOracle interface"
        );
    }

    // when interface is IERC165
    //  [X] it returns true

    function test_whenInterfaceIsIERC165() public view {
        MorphoOracleCloneable oracleContract = MorphoOracleCloneable(address(oracle));
        assertTrue(
            oracleContract.supportsInterface(type(IERC165).interfaceId),
            "Should return true for IERC165 interface"
        );
    }

    // when interface is not supported
    //  [X] it returns false

    function test_whenInterfaceIsNotSupported() public view {
        MorphoOracleCloneable oracleContract = MorphoOracleCloneable(address(oracle));
        bytes4 invalidInterface = bytes4(0x12345678);

        assertFalse(
            oracleContract.supportsInterface(invalidInterface),
            "Should return false for unsupported interface"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
