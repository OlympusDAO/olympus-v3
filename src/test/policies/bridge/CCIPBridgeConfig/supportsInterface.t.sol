// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_supportsInterface is CCIPBridgeConfigTest {
    /// @notice The eight interface identifiers the policy advertises.
    function _advertisedInterfaceIds() internal pure returns (bytes4[] memory interfaceIds) {
        interfaceIds = new bytes4[](8);
        interfaceIds[0] = type(ICCIPBridgeConfig).interfaceId;
        interfaceIds[1] = type(IConfigOperator).interfaceId;
        interfaceIds[2] = type(IVersioned).interfaceId;
        interfaceIds[3] = type(IGracePeriod).interfaceId;
        interfaceIds[4] = type(IReEnabler).interfaceId;
        interfaceIds[5] = type(IEnablerV2).interfaceId;
        interfaceIds[6] = type(IEnabler).interfaceId;
        interfaceIds[7] = type(IERC165).interfaceId;
        return interfaceIds;
    }

    // when the interface identifier is one of the advertised eight
    //   [X] it returns true for ICCIPBridgeConfig
    //   [X] it returns true for IConfigOperator
    //   [X] it returns true for IVersioned
    //   [X] it returns true for IGracePeriod
    //   [X] it returns true for IReEnabler
    //   [X] it returns true for IEnablerV2
    //   [X] it returns true for IEnabler
    //   [X] it returns true for IERC165
    function test_whenInterfaceIsAdvertised() public view {
        assertTrue(
            config.supportsInterface(type(ICCIPBridgeConfig).interfaceId),
            "ICCIPBridgeConfig should be advertised"
        );
        assertTrue(
            config.supportsInterface(type(IConfigOperator).interfaceId),
            "IConfigOperator should be advertised"
        );
        assertTrue(
            config.supportsInterface(type(IVersioned).interfaceId),
            "IVersioned should be advertised"
        );
        assertTrue(
            config.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod should be advertised"
        );
        assertTrue(
            config.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler should be advertised"
        );
        assertTrue(
            config.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 should be advertised"
        );
        assertTrue(
            config.supportsInterface(type(IEnabler).interfaceId),
            "IEnabler should be advertised"
        );
        assertTrue(
            config.supportsInterface(type(IERC165).interfaceId),
            "IERC165 should be advertised"
        );
    }

    // when the interface identifier is 0xffffffff
    //   [X] it returns false
    // The ERC165 conformance requirement
    function test_whenInterfaceIdIsInvalid() public view {
        assertFalse(
            config.supportsInterface(0xffffffff),
            "the invalid identifier should answer false"
        );
    }

    // when the interface identifier is any other value
    //   [X] it returns false
    // Fuzzed over bytes4 with the eight advertised identifiers excluded
    function test_whenInterfaceIdIsUnknown(bytes4 interfaceId_) public view {
        bytes4[] memory advertised = _advertisedInterfaceIds();
        for (uint256 i; i < advertised.length; ++i) {
            vm.assume(interfaceId_ != advertised[i]);
        }

        assertFalse(
            config.supportsInterface(interfaceId_),
            "an unadvertised identifier should answer false"
        );
    }

    // [X] the eight advertised identifiers are pairwise distinct
    // [X] type(ICCIPBridgeConfig).interfaceId differs from type(IConfigOperator).interfaceId
    // The Solidity interfaceId covers only the functions declared in the interface itself,
    // not the inherited IConfigOperator ones, which is why both are advertised separately; a
    // collision would silently merge answer classes.
    function test_advertisedInterfaceIdsAreDistinct() public pure {
        bytes4[] memory advertised = _advertisedInterfaceIds();

        for (uint256 i; i < advertised.length; ++i) {
            for (uint256 j = i + 1; j < advertised.length; ++j) {
                assertTrue(
                    advertised[i] != advertised[j],
                    "the advertised identifiers should be pairwise distinct"
                );
            }
        }

        assertTrue(
            type(ICCIPBridgeConfig).interfaceId != type(IConfigOperator).interfaceId,
            "the config and the operator identifiers should differ"
        );
    }

    // given the policy is disabled
    //   [X] it answers the advertised identifiers with true
    // The view carries no lifecycle gate
    function test_givenPolicyDisabled() public view {
        assertFalse(config.isEnabled(), "the policy should be disabled after setUp");

        bytes4[] memory advertised = _advertisedInterfaceIds();
        for (uint256 i; i < advertised.length; ++i) {
            assertTrue(
                config.supportsInterface(advertised[i]),
                "every advertised identifier should answer true while disabled"
            );
        }
    }
}
