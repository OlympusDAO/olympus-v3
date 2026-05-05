// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {EnablerV2TestBase} from "src/test/libraries/EnablerV2/EnablerV2TestBase.sol";

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/interfaces/IEnablerV2.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";

/// @dev Tests for `EnablerV2.supportsInterface`. The base contract is
///      expected to advertise `IERC165`, the legacy `IEnabler`, and
///      `IEnablerV2`, and to return false for any other interface
///      identifier.
contract EnablerV2Tests_SupportsInterface is EnablerV2TestBase {
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

    function test_supportsInterface_returnsFalseForUnknownInterface() external view {
        assertFalse(harness.supportsInterface(bytes4(0xffffffff)), "sentinel must be unsupported");
        assertFalse(harness.supportsInterface(bytes4(0x12345678)), "arbitrary id must be false");
    }
}
