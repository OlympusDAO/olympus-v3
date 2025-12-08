// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {IMorphoOracleFactory} from "src/policies/interfaces/price/IMorphoOracleFactory.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract MorphoOracleFactorySupportsInterfaceTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // supportsInterface
    // when interface is IMorphoOracleFactory
    //  [X] it returns true

    function test_whenInterfaceIsIMorphoOracleFactory() public view {
        assertTrue(
            factory.supportsInterface(type(IMorphoOracleFactory).interfaceId),
            "Should return true for IMorphoOracleFactory interface"
        );
    }

    // when interface is IERC165
    //  [X] it returns true

    function test_whenInterfaceIsIERC165() public view {
        assertTrue(
            factory.supportsInterface(type(IERC165).interfaceId),
            "Should return true for IERC165 interface"
        );
    }

    // when interface is IEnabler (from PolicyEnabler)
    //  [X] it returns true

    function test_whenInterfaceIsIEnabler() public view {
        assertTrue(
            factory.supportsInterface(type(IEnabler).interfaceId),
            "Should return true for IEnabler interface"
        );
    }

    // when interface is not supported
    //  [X] it returns false

    function test_whenInterfaceIsNotSupported() public view {
        bytes4 invalidInterface = bytes4(0x12345678);

        assertFalse(
            factory.supportsInterface(invalidInterface),
            "Should return false for unsupported interface"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
