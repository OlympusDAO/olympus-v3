// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockSupportsInterfaceTest is DepositManagerConfigTimelockTest {
    function test_supportsExpectedInterfaces() public view {
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
    }

    function test_whenInterfaceIsUnsupported_returnsFalse() public view {
        assertFalse(_configTimelock.supportsInterface(0xffffffff), "unknown interface supported");
    }
}
