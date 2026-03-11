// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

// Test
import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

// Interfaces
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ERC7726OracleSupportsInterfaceTest is ERC7726OracleTest {
    // ========== TESTS ========== //

    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(oracle));
        assertTrue(
            oracle.supportsInterface(type(IERC7726Oracle).interfaceId),
            "IERC7726Oracle mismatch"
        );
        assertTrue(oracle.supportsInterface(type(IERC165).interfaceId), "IERC165 mismatch");
        assertTrue(oracle.supportsInterface(type(IVersioned).interfaceId), "IVersioned mismatch");
        assertTrue(oracle.supportsInterface(type(IEnabler).interfaceId), "IEnabler mismatch");
        assertFalse(
            oracle.supportsInterface(type(IERC20).interfaceId),
            "Should not support IERC20"
        );
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
