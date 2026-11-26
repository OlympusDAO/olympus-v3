// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

// Test
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSupportsInterfaceTest is FLOANTest {
    // supportsInterface
    // given a supported FLOAN, ERC-165, or version interface
    //  when supportsInterface is called
    //   then it returns true
    function test_givenSupportedInterface_returnsTrue() public view {
        assertTrue(floan.supportsInterface(type(IFLOANv1).interfaceId), "FLOAN interface");
        assertTrue(floan.supportsInterface(type(IERC165).interfaceId), "ERC-165 interface");
        assertTrue(floan.supportsInterface(type(IVersioned).interfaceId), "version interface");
    }

    // supportsInterface
    // given an unsupported interface
    //  when supportsInterface is called
    //   then it returns false
    function test_givenUnsupportedInterface_returnsFalse(bytes4 interfaceId_) public view {
        vm.assume(interfaceId_ != type(IFLOANv1).interfaceId);
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        assertFalse(floan.supportsInterface(interfaceId_), "unsupported interface");
    }
}
