// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {PolicyReEnablerTestBase} from "src/test/policies/utils/PolicyReEnabler/PolicyReEnablerTestBase.sol";

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract PolicyReEnablerTests_SupportsInterface is PolicyReEnablerTestBase {
    function test_supportsInterface_validatesIERC165Self() external view {
        ERC165Helper.validateSupportsInterface(address(policy));
    }

    function test_supportsInterface_returnsTrueForIERC165() external view {
        assertTrue(policy.supportsInterface(type(IERC165).interfaceId), "IERC165 not advertised");
    }

    function test_supportsInterface_returnsTrueForIEnabler() external view {
        assertTrue(policy.supportsInterface(type(IEnabler).interfaceId), "IEnabler not advertised");
    }

    function test_supportsInterface_returnsTrueForIEnablerV2() external view {
        assertTrue(
            policy.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 not advertised"
        );
    }

    function test_supportsInterface_returnsTrueForIReEnabler() external view {
        assertTrue(
            policy.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler not advertised"
        );
    }

    function test_supportsInterface_returnsFalseForUnknownInterface() external view {
        assertFalse(policy.supportsInterface(bytes4(0xffffffff)), "sentinel must be unsupported");
    }
}
