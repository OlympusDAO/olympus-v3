// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {PriceCacheLifecycleTest} from "./fixtures/PriceCacheLifecycleTest.sol";

contract PriceCacheSupportsInterfaceTest is PriceCacheLifecycleTest {
    // Scenarios: PCACHE-INTERFACES-P01.
    function test_whenKnownInterfacesQueried(address caller_) public {
        vm.startPrank(caller_);
        assertTrue(cache.supportsInterface(type(IERC165).interfaceId), "ERC165 supported");
        assertTrue(
            cache.supportsInterface(type(IVersioned).interfaceId),
            "version discovery supported"
        );
        assertTrue(
            cache.supportsInterface(type(IEnabler).interfaceId),
            "legacy lifecycle supported"
        );
        assertTrue(
            cache.supportsInterface(type(IEnablerV2).interfaceId),
            "timestamp lifecycle supported"
        );
        assertTrue(cache.supportsInterface(type(IReEnabler).interfaceId), "reEnable supported");
        assertTrue(cache.supportsInterface(type(IGracePeriod).interfaceId), "grace supported");
        assertTrue(cache.supportsInterface(type(IPriceCache).interfaceId), "cache API supported");
        vm.stopPrank();
    }

    // Scenarios: PCACHE-INTERFACES-P02.
    function test_whenUnknownInterfaceQueried(address caller_, bytes4 id_) public {
        vm.assume(
            id_ != type(IERC165).interfaceId &&
                id_ != type(IVersioned).interfaceId &&
                id_ != type(IEnabler).interfaceId &&
                id_ != type(IEnablerV2).interfaceId &&
                id_ != type(IReEnabler).interfaceId &&
                id_ != type(IGracePeriod).interfaceId &&
                id_ != type(IPriceCache).interfaceId
        );
        vm.prank(caller_);
        assertFalse(cache.supportsInterface(id_), "unknown interface rejected");
    }

    // Scenarios: PCACHE-INTERFACES-L01.
    function test_givenInactivePaused_whenInterfacesQueried(
        address caller_
    ) public givenLifecycleDisabled givenLifecycleInactive {
        test_whenKnownInterfacesQueried(caller_);
        vm.prank(caller_);
        assertFalse(cache.supportsInterface(0xffffffff), "unknown interface remains false");
    }
}
