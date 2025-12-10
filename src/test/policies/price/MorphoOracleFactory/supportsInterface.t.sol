// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

// Test
import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

// Interfaces
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract MorphoOracleFactorySupportsInterfaceTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(factory));
        assertTrue(
            factory.supportsInterface(type(IOracleFactory).interfaceId),
            "IOracleFactory mismatch"
        );
        assertTrue(factory.supportsInterface(type(IERC165).interfaceId), "IERC165 mismatch");
        assertTrue(factory.supportsInterface(type(IEnabler).interfaceId), "IEnabler mismatch");
        assertTrue(factory.supportsInterface(type(IVersioned).interfaceId), "IVersioned mismatch");
        assertFalse(
            factory.supportsInterface(type(IERC20).interfaceId),
            "Should not support IERC20"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
