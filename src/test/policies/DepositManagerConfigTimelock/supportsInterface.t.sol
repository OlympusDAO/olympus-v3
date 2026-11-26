// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockSupportsInterfaceTest is DepositManagerConfigTimelockTest {
    // Scenarios: DMCT-INTERFACES-P01.
    function test_supportsExpectedInterfaces(address caller_) public {
        vm.startPrank(caller_);
        assertTrue(
            _configTimelock.supportsInterface(type(IERC165).interfaceId),
            "IERC165 unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(IEnabler).interfaceId),
            "IEnabler unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "ITimelockBatchQueue unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(IConfigTimelockBatchQueue).interfaceId),
            "IConfigTimelockBatchQueue unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(IDepositManagerConfigTimelock).interfaceId),
            "IDepositManagerConfigTimelock unsupported"
        );
        assertTrue(
            _configTimelock.supportsInterface(type(IVersioned).interfaceId),
            "IVersioned unsupported"
        );
        vm.stopPrank();
    }

    // Scenarios: DMCT-INTERFACES-I01.
    function test_whenInterfaceIsUnsupported_returnsFalse() public view {
        assertFalse(_configTimelock.supportsInterface(0xffffffff), "unknown interface supported");
    }

    // Scenarios: DMCT-INTERFACES-L01.
    function test_givenPausedInactive_whenInterfacesQueried(address caller_) public {
        _pausePolicy(address(_configTimelock));
        _setPolicyActive(address(_configTimelock), false);
        test_supportsExpectedInterfaces(caller_);
    }

    // Scenarios: DMCT-INTERFACES-I01.
    function test_whenUnknownInterfaceQueried(address caller_, bytes4 id_) public {
        vm.assume(
            id_ != type(IERC165).interfaceId &&
                id_ != type(IEnabler).interfaceId &&
                id_ != type(IEnablerV2).interfaceId &&
                id_ != type(IReEnabler).interfaceId &&
                id_ != type(IGracePeriod).interfaceId &&
                id_ != type(ITimelockBatchQueue).interfaceId &&
                id_ != type(IConfigTimelockBatchQueue).interfaceId &&
                id_ != type(IDepositManagerConfigTimelock).interfaceId &&
                id_ != type(IVersioned).interfaceId
        );
        vm.prank(caller_);
        assertFalse(_configTimelock.supportsInterface(id_), "unknown interface rejected");
    }
}
