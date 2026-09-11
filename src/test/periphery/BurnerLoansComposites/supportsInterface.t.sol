// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesSupportsInterfaceTest is BurnerLoansCompositesTest {
    // supportsInterface
    // given the composite contract is deployed
    //  when interface support is queried
    //   then it advertises ERC165 and the composite interface only
    function test_givenDeployed_returnsExpectedSupport() public view {
        assertTrue(composites.supportsInterface(type(IERC165).interfaceId), "ERC165 interface");
        assertTrue(
            composites.supportsInterface(type(IBurnerLoansComposites).interfaceId),
            "composite interface"
        );
        assertFalse(composites.supportsInterface(bytes4(0xffffffff)), "unknown interface");
    }
}
