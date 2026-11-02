// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockSupportsInterfaceTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-ERC165-P01.
    function test_givenAnyCaller_whenIBurnerLoansConfigTimelockQueried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IBurnerLoansConfigTimelock).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P02.
    function test_givenAnyCaller_whenIConfigTimelockBatchQueueQueried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IConfigTimelockBatchQueue).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P03.
    function test_givenAnyCaller_whenITimelockBatchQueueQueried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P04.
    function test_givenAnyCaller_whenIVersionedQueried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IVersioned).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P05.
    function test_givenAnyCaller_whenIERC165Queried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IERC165).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P06.
    function test_givenAnyCaller_whenIEnablerQueried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IEnabler).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P07.
    function test_givenAnyCaller_whenIEnablerV2Queried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IEnablerV2).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P08.
    function test_givenAnyCaller_whenIReEnablerQueried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IReEnabler).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P09.
    function test_givenAnyCaller_whenIGracePeriodQueried_thenSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        assertTrue(
            _timelock.supportsInterface(type(IGracePeriod).interfaceId),
            "Required interface supported"
        );
        assertEq(_lifecycleDigest(), beforeState, "Interface query read-only");
    }

    // Scenarios: BLCT-ERC165-P10.
    function test_givenAnyCaller_whenInvalidErc165InterfaceQueried_thenFalse(
        address caller_
    ) public {
        vm.prank(caller_);
        assertFalse(_timelock.supportsInterface(0xffffffff), "Unsupported identifier");
    }

    // Scenarios: BLCT-ERC165-P11.
    function test_givenAnyCaller_whenZeroInterfaceQueried_thenFalse(address caller_) public {
        vm.prank(caller_);
        assertFalse(_timelock.supportsInterface(0x00000000), "Unsupported identifier");
    }

    // Scenarios: BLCT-ERC165-P12.
    function test_givenAnyCaller_whenUnknownInterfaceQueried_thenFalse(
        address caller_,
        bytes4 interface_
    ) public {
        vm.assume(interface_ != 0xffffffff && interface_ != 0);
        vm.assume(interface_ != type(IBurnerLoansConfigTimelock).interfaceId);
        vm.assume(interface_ != type(IConfigTimelockBatchQueue).interfaceId);
        vm.assume(interface_ != type(ITimelockBatchQueue).interfaceId);
        vm.assume(interface_ != type(IVersioned).interfaceId);
        vm.assume(interface_ != type(IERC165).interfaceId);
        vm.assume(interface_ != type(IEnabler).interfaceId);
        vm.assume(interface_ != type(IEnablerV2).interfaceId);
        vm.assume(interface_ != type(IReEnabler).interfaceId);
        vm.assume(interface_ != type(IGracePeriod).interfaceId);
        vm.prank(caller_);
        assertFalse(_timelock.supportsInterface(interface_), "Unknown interface rejected");
    }
}
