// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySupportsInterfaceTest is BurnerLoansInventoryTest {
    // supportsInterface
    // [X] given supported and unknown identifiers, it reports ERC165 support accurately
    function test_reportsSupportedInterfaces() public view {
        assertTrue(
            inventory.supportsInterface(type(IBurnerLoansInventory).interfaceId),
            "inventory"
        );
        assertTrue(inventory.supportsInterface(type(IVersioned).interfaceId), "versioned");
        assertTrue(inventory.supportsInterface(type(IEnabler).interfaceId), "enabler");
        assertTrue(inventory.supportsInterface(type(IReEnabler).interfaceId), "re-enabler");
        assertTrue(inventory.supportsInterface(type(IGracePeriod).interfaceId), "grace period");
        assertFalse(inventory.supportsInterface(0xffffffff), "unknown interface");
    }
}
