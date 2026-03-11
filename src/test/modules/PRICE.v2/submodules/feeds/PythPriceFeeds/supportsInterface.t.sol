// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

// Test
import {PythPriceFeedsTest} from "./PythPriceFeedsTest.sol";

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

contract PythPriceFeedsSupportsInterfaceTest is PythPriceFeedsTest {
    // =========  IERC165 FUNCTIONS ========= //

    // given supportsInterface is called with IERC165 interface ID
    //  [X] it returns true
    function test_supportsInterface_IERC165_returnsTrue() public view {
        bytes4 interfaceId = type(IERC165).interfaceId;
        bool supported = pythSubmodule.supportsInterface(interfaceId);
        assertTrue(supported, "Should support IERC165 interface");
    }

    // given supportsInterface is called with IVersioned interface ID
    //  [X] it returns true
    function test_supportsInterface_IVersioned_returnsTrue() public view {
        bytes4 interfaceId = type(IVersioned).interfaceId;
        bool supported = pythSubmodule.supportsInterface(interfaceId);
        assertTrue(supported, "Should support IVersioned interface");
    }

    // given supportsInterface is called with an unsupported interface ID
    //  [X] it returns false
    function test_supportsInterface_unsupported_returnsFalse() public view {
        bytes4 interfaceId = 0x12345678;
        bool supported = pythSubmodule.supportsInterface(interfaceId);
        assertFalse(supported, "Should not support unsupported interface");
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
