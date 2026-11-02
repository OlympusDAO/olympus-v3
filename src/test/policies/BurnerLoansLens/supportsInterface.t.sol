// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";

// Contracts
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

contract BurnerLoansLensSupportsInterfaceTest is BurnerLoansModularTest {
    bytes4 internal constant _INVALID_INTERFACE_ID = 0xffffffff;

    modifier givenCoreUnavailable() {
        vm.etch(address(_core), hex"");
        vm.expectCall(address(_core), bytes(""), uint64(0));
        _;
    }

    // Scenarios: BLLENS-CONSTRUCTOR-V01.
    function test_givenCoreUnavailable_whenLensInterfaceQueried(
        address caller_
    ) public givenCoreUnavailable {
        vm.prank(caller_);
        assertTrue(
            _lens.supportsInterface(type(IBurnerLoansLens).interfaceId),
            "Lens advertises its public interface"
        );
    }

    // Scenarios: BLLENS-CONSTRUCTOR-V06.
    function test_givenCoreUnavailable_whenCoreBindingQueried(
        address caller_
    ) public givenCoreUnavailable {
        vm.prank(caller_);
        assertTrue(
            _lens.supportsInterface(type(IBurnerLoansCoreBound).interfaceId),
            "Lens advertises the shared Core binding"
        );
    }

    // Scenarios: BLLENS-CONSTRUCTOR-V02.
    function test_givenCoreUnavailable_whenERC165Queried(
        address caller_
    ) public givenCoreUnavailable {
        vm.prank(caller_);
        assertTrue(_lens.supportsInterface(type(IERC165).interfaceId), "Lens advertises ERC165");
    }

    // Scenarios: BLLENS-CONSTRUCTOR-V03.
    function test_givenCoreUnavailable_whenInvalidInterfaceQueried(
        address caller_
    ) public givenCoreUnavailable {
        vm.prank(caller_);
        assertFalse(
            _lens.supportsInterface(_INVALID_INTERFACE_ID),
            "Invalid ERC165 identifier is rejected"
        );
    }

    // Scenarios: BLLENS-CONSTRUCTOR-V05.
    function test_givenCoreUnavailable_whenVersionedInterfaceQueried(
        address caller_
    ) public givenCoreUnavailable {
        // Implicit assignment proves nominal IVersioned inheritance as well as ABI compatibility.
        IVersioned versioned = _lens;
        vm.startPrank(caller_);
        assertTrue(
            _lens.supportsInterface(type(IVersioned).interfaceId),
            "Lens advertises IVersioned"
        );
        (uint8 major, uint8 minor) = versioned.VERSION();
        vm.stopPrank();

        assertEq(major, 1, "Lens major version is 1");
        assertEq(minor, 0, "Lens minor version is 0");
    }

    // Scenarios: BLLENS-CONSTRUCTOR-V04.
    function test_givenCoreUnavailable_whenUnsupportedInterfaceQueried(
        address caller_,
        bytes4 interfaceId_
    ) public givenCoreUnavailable {
        vm.assume(interfaceId_ != type(IBurnerLoansLens).interfaceId);
        vm.assume(interfaceId_ != type(IBurnerLoansCoreBound).interfaceId);
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        vm.assume(interfaceId_ != _INVALID_INTERFACE_ID);

        vm.prank(caller_);
        assertFalse(_lens.supportsInterface(interfaceId_), "Unsupported interface is rejected");
    }

    // Scenarios: BLLENS-CONSTRUCTOR-V04.
    function test_givenCoreUnavailable_whenZeroInterfaceQueried(
        address caller_
    ) public givenCoreUnavailable {
        vm.prank(caller_);
        assertFalse(_lens.supportsInterface(bytes4(0)), "Zero interface identifier is rejected");
    }
}
