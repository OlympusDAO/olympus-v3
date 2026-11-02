// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

contract BurnerLoansCompositesVersionTest is BurnerLoansModularTest {
    // Scenarios: BLCOMP-VERSION-P01.
    function test_whenVersionQueried_thenVersionIsDiscoverable(address caller_) public {
        BurnerLoansComposites composites = new BurnerLoansComposites(
            address(_core),
            address(_ohm),
            _collateral,
            _debt
        );
        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        vm.prank(caller_);
        (uint8 major, uint8 minor) = IVersioned(address(composites)).VERSION();
        assertEq(major, 1, "Composites major version");
        assertEq(minor, 0, "Composites minor version");
        vm.prank(caller_);
        assertTrue(
            composites.supportsInterface(type(IVersioned).interfaceId),
            "Composites advertises versioning independently of Core lifecycle"
        );
    }
}
