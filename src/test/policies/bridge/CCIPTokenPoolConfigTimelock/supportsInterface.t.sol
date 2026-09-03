// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPTokenPoolConfig} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfig.sol";
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

contract CCIPTokenPoolConfigTimelockTests_supportsInterface is CCIPTokenPoolConfigTimelockTest {
    // ========== FILE-LOCAL HELPERS ========== //

    /// @notice The nine interface identifiers the policy advertises, in the order of the
    ///         override and its super chain.
    function _advertisedInterfaceIds() internal pure returns (bytes4[] memory interfaceIds) {
        interfaceIds = new bytes4[](9);
        interfaceIds[0] = type(ICCIPTokenPoolConfigTimelock).interfaceId;
        interfaceIds[1] = type(IVersioned).interfaceId;
        interfaceIds[2] = type(IConfigTimelockBatchQueue).interfaceId;
        interfaceIds[3] = type(ITimelockBatchQueue).interfaceId;
        interfaceIds[4] = type(IGracePeriod).interfaceId;
        interfaceIds[5] = type(IReEnabler).interfaceId;
        interfaceIds[6] = type(IEnablerV2).interfaceId;
        interfaceIds[7] = type(IEnabler).interfaceId;
        interfaceIds[8] = type(IERC165).interfaceId;
        return interfaceIds;
    }

    // when the interface id is one of the nine advertised ones
    //   [X] it answers true for ICCIPTokenPoolConfigTimelock, IVersioned,
    //       IConfigTimelockBatchQueue, ITimelockBatchQueue, IGracePeriod, IReEnabler,
    //       IEnablerV2, IEnabler and IERC165
    //   [X] it answers false for ICCIPTokenPoolConfig and IConfigOperator
    // The negative half pins that a timelock can never pass another timelock's
    // constructor probe for a config candidate
    function test_whenInterfaceIsSupported() public view {
        assertTrue(
            timelock.supportsInterface(type(ICCIPTokenPoolConfigTimelock).interfaceId),
            "ICCIPTokenPoolConfigTimelock should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(IVersioned).interfaceId),
            "IVersioned should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(IConfigTimelockBatchQueue).interfaceId),
            "IConfigTimelockBatchQueue should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "ITimelockBatchQueue should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(IEnabler).interfaceId),
            "IEnabler should be advertised"
        );
        assertTrue(
            timelock.supportsInterface(type(IERC165).interfaceId),
            "IERC165 should be advertised"
        );

        // The constructor of another timelock demands ICCIPTokenPoolConfig, IConfigOperator and
        // IEnabler together; this policy advertises only the last of the three
        assertFalse(
            timelock.supportsInterface(type(ICCIPTokenPoolConfig).interfaceId),
            "ICCIPTokenPoolConfig should not be advertised"
        );
        assertFalse(
            timelock.supportsInterface(type(IConfigOperator).interfaceId),
            "IConfigOperator should not be advertised"
        );
    }

    // when the interface id is 0xffffffff
    //   [X] it answers false
    // ERC165 conformance: no contract may advertise the invalid id
    function test_whenInterfaceIsInvalid() public view {
        assertFalse(timelock.supportsInterface(0xffffffff), "the invalid id should answer false");
    }

    // when the interface id is any value outside the advertised set
    //   [X] it answers false
    // Fuzzed; vm.assume excludes the nine advertised ids
    function test_whenInterfaceIsUnknown(bytes4 interfaceId_) public view {
        bytes4[] memory advertised = _advertisedInterfaceIds();
        for (uint256 i; i < advertised.length; ++i) {
            vm.assume(interfaceId_ != advertised[i]);
        }

        assertFalse(
            timelock.supportsInterface(interfaceId_),
            "an unadvertised id should answer false"
        );
    }

    // when VERSION is called
    //   [X] it returns major one and minor zero
    function test_version() public view {
        (uint8 major, uint8 minor) = timelock.VERSION();

        assertEq(major, 1, "the major version should be one");
        assertEq(minor, 0, "the minor version should be zero");
    }
}
