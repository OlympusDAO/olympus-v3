// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";

// Contracts
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";

contract PriceCacherTaskSupportsInterfaceTest is PriceCacherTaskTest {
    // given supported interfaces
    //  when the interface is queried
    //   then the query returns true
    // Scenarios: PCACHER-INTERFACES-P01.
    function test_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(cacher.supportsInterface(type(IPeriodicTask).interfaceId), "IPeriodicTask");
        assertTrue(
            cacher.supportsInterface(type(IPriceCacherTask).interfaceId),
            "IPriceCacherTask"
        );
        assertTrue(cacher.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
    }

    // given unsupported interface
    //  when the interface is queried
    //   then the query returns false
    // Scenarios: PCACHER-INTERFACES-N01.
    function test_givenUnsupportedInterface_returnsFalse() public view {
        assertFalse(cacher.supportsInterface(bytes4(0xffffffff)), "unsupported interface");
    }

    // Scenarios: PCACHER-INTERFACES-P02.
    function test_whenLifecycleInterfacesQueried(address caller_) public {
        vm.startPrank(caller_);
        assertTrue(cacher.supportsInterface(type(IERC165).interfaceId), "ERC165 supported");
        assertTrue(
            cacher.supportsInterface(type(IEnabler).interfaceId),
            "legacy lifecycle supported"
        );
        assertTrue(
            cacher.supportsInterface(type(IEnablerV2).interfaceId),
            "timestamp lifecycle supported"
        );
        assertTrue(cacher.supportsInterface(type(IReEnabler).interfaceId), "reEnable supported");
        assertTrue(cacher.supportsInterface(type(IGracePeriod).interfaceId), "grace supported");
        vm.stopPrank();
    }

    // Scenarios: PCACHER-INTERFACES-P03.
    function test_whenUnknownInterfaceQueried(address caller_, bytes4 id_) public {
        vm.assume(
            id_ != type(IERC165).interfaceId &&
                id_ != type(IVersioned).interfaceId &&
                id_ != type(IPeriodicTask).interfaceId &&
                id_ != type(IPriceCacherTask).interfaceId &&
                id_ != type(IEnabler).interfaceId &&
                id_ != type(IEnablerV2).interfaceId &&
                id_ != type(IReEnabler).interfaceId &&
                id_ != type(IGracePeriod).interfaceId
        );
        vm.prank(caller_);
        assertFalse(cacher.supportsInterface(id_), "unknown interface rejected");
    }

    // Scenarios: PCACHER-INTERFACES-L01.
    function test_givenInactivePausedAndBrokenCache_whenDiscoveryQueried(address caller_) public {
        vm.prank(admin);
        cacher.disable("");
        _setTaskMembership(false);
        vm.mockCallRevert(address(priceCache), bytes(""), hex"deadbeef");
        vm.record();
        test_givenSupportedInterfaces_returnsTrue();
        test_whenLifecycleInterfacesQueried(caller_);
        test_whenUnknownInterfaceQueried(caller_, bytes4(0));
        test_givenUnsupportedInterface_returnsFalse();
        (, bytes32[] memory writes) = vm.accesses(address(cacher));
        assertEq(writes.length, 0, "discovery writes nothing");
    }
}
