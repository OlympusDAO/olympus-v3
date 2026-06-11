// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ReEnablerGracePeriodImmutableTestBase} from "src/test/bases/ReEnablerGracePeriodImmutable/ReEnablerGracePeriodImmutableTestBase.sol";

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";

/// @dev Tests for `ReEnablerGracePeriodImmutable.supportsInterface`. The lock-only
///      override does not affect the interface-detection surface, so the immutable
///      variant must advertise the same identifiers as the mutable parent.
contract ReEnablerGracePeriodImmutableTests_SupportsInterface is
    ReEnablerGracePeriodImmutableTestBase
{
    function test_supportsInterface_validatesIERC165Self() external view {
        ERC165Helper.validateSupportsInterface(address(harness));
    }

    function test_supportsInterface_returnsTrueForIERC165() external view {
        assertTrue(harness.supportsInterface(type(IERC165).interfaceId), "IERC165 not advertised");
    }

    function test_supportsInterface_returnsTrueForIEnabler() external view {
        assertTrue(
            harness.supportsInterface(type(IEnabler).interfaceId),
            "IEnabler not advertised"
        );
    }

    function test_supportsInterface_returnsTrueForIEnablerV2() external view {
        assertTrue(
            harness.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 not advertised"
        );
    }

    function test_supportsInterface_returnsTrueForIReEnabler() external view {
        assertTrue(
            harness.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler not advertised"
        );
    }

    function test_supportsInterface_returnsTrueForIGracePeriod() external view {
        assertTrue(
            harness.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod not advertised"
        );
    }

    function test_supportsInterface_returnsFalseForUnknownInterface() external view {
        assertFalse(harness.supportsInterface(bytes4(0xffffffff)), "sentinel must be unsupported");
        assertFalse(harness.supportsInterface(bytes4(0x12345678)), "arbitrary id must be false");
    }
}
