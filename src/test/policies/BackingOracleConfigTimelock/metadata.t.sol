// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Contracts
import {BackingOracleConfigTimelockTest, ITimelockBatchQueue, IEnabler} from "./fixtures/BackingOracleConfigTimelockTest.sol";
import {Keycode, toKeycode} from "src/Kernel.sol";

contract BackingOracleTimelockMetadataTest is BackingOracleConfigTimelockTest {
    // Scenarios: BO-TIMELOCK-METADATA-04.
    function test_whenFixedNotice() public view {
        assertEq(_timelock.TIMELOCK_DELAY(), 1 days, "fixed notice constant");
        assertEq(
            _timelock.timelockDelay(),
            _timelock.TIMELOCK_DELAY(),
            "configured notice matches fixed constant"
        );
    }

    // Scenarios: BO-TIMELOCK-METADATA-03.
    function test_whenDelayChangeSelectorIsCalled() public {
        vm.prank(_ADMIN);
        (bool success, bytes memory result) = address(_timelock).call(
            abi.encodeWithSignature("setTimelockDelay(uint48)", uint48(2 days))
        );
        assertFalse(success, "delay setter is not part of the deployed API");
        // An absent selector is rejected by the EVM dispatcher with empty return data.
        assertEq(result.length, 0, "unknown selector has no application error");
        assertEq(_timelock.timelockDelay(), 1 days, "notice is fixed at construction");
    }

    // Scenarios: BO-TIMELOCK-METADATA-01.
    function test_whenInterfaces() public view {
        assertTrue(
            _timelock.supportsInterface(type(IBackingOracleConfigTimelock).interfaceId),
            "product queue interface"
        );
        assertTrue(
            _timelock.supportsInterface(type(IConfigTimelockBatchQueue).interfaceId),
            "config queue interface"
        );
        assertTrue(
            _timelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "batch queue interface"
        );
        assertTrue(_timelock.supportsInterface(type(IEnabler).interfaceId), "enabler interface");
        assertTrue(_timelock.supportsInterface(type(IVersioned).interfaceId), "version interface");
        assertTrue(
            _timelock.supportsInterface(type(IReEnabler).interfaceId),
            "re-enable interface"
        );
        assertTrue(_timelock.supportsInterface(type(IGracePeriod).interfaceId), "grace interface");
        assertEq(_timelock.gracePeriod(), 7 days, "default recovery grace");
        assertFalse(_timelock.supportsInterface(0xffffffff), "invalid interface");
        (uint8 major, uint8 minor) = _timelock.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }

    // Scenarios: BO-TIMELOCK-METADATA-02.
    function test_whenFrameworkHooks() public {
        Keycode[] memory dependencies = _timelock.configureDependencies();
        assertEq(dependencies.length, 1, "one dependency");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES dependency"
        );
        assertEq(_timelock.requestPermissions().length, 0, "no module writes");
        assertEq(_timelock.maxConfigKeysPerBatch(), 1, "one configuration domain");
    }
}
