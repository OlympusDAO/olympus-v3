// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {BackingOracleTest, IBackingOracle, ITimelockQueue} from "./fixtures/BackingOracleTest.sol";
import {Kernel, Keycode, toKeycode} from "src/Kernel.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleMetadataTest is BackingOracleTest {
    // Scenarios: BO-METADATA-01.
    function test_whenMetadata() public view {
        assertFalse(_roles.hasRole(address(this), ADMIN_ROLE), "harness has no policy ADMIN role");
        assertFalse(_oracle.isEnabled(), "starts disabled");
        assertEq(_oracle.backing(), 0, "starts uninitialized");
        assertEq(_oracle.decimals(), 18, "18 decimals");
        (uint8 major, uint8 minor) = _oracle.VERSION();
        assertEq(major, 1, "major");
        assertEq(minor, 0, "minor");
        assertTrue(_oracle.supportsInterface(type(IBackingOracle).interfaceId), "source oracle ID");
        assertFalse(
            _oracle.supportsInterface(
                bytes4(keccak256("backing()")) ^ bytes4(keccak256("setBacking(uint256)"))
            ),
            "removed interface is not advertised"
        );
        assertFalse(
            _oracle.supportsInterface(type(IBackingOracleConfigTimelock).interfaceId),
            "timelock ID"
        );
        assertFalse(
            _oracle.supportsInterface(type(ITimelockQueue).interfaceId),
            "oracle has no queue"
        );
        assertTrue(
            _oracle.supportsInterface(type(IConfigOperator).interfaceId),
            "replaceable operator ID"
        );
        assertTrue(_oracle.supportsInterface(type(IVersioned).interfaceId), "version ID");
        assertTrue(_oracle.supportsInterface(type(IEnabler).interfaceId), "enabler ID");
        assertTrue(_oracle.supportsInterface(type(IEnablerV2).interfaceId), "enabler V2 ID");
        assertTrue(_oracle.supportsInterface(0x01ffc9a7), "ERC165 ID");
        assertTrue(_oracle.supportsInterface(type(IReEnabler).interfaceId), "re-enable interface");
        assertTrue(_oracle.supportsInterface(type(IGracePeriod).interfaceId), "grace interface");
        assertEq(_oracle.gracePeriod(), 7 days, "default recovery grace");
        assertFalse(_oracle.supportsInterface(0xffffffff), "invalid ID");
    }

    // Scenarios: BO-METADATA-02.
    function test_whenZeroKernel_reverts() public {
        vm.expectRevert(IBackingOracle.BackingOracle_ZeroKernelAddress.selector);
        new BackingOracle(Kernel(address(0)));
    }

    // Scenarios: BO-METADATA-03.
    function test_whenFrameworkHooks() public {
        Keycode[] memory dependencies = _oracle.configureDependencies();
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "ROLES binding"
        );
        assertEq(dependencies.length, 1, "one dependency");
        assertEq(_oracle.requestPermissions().length, 0, "read only policy");
    }
}
