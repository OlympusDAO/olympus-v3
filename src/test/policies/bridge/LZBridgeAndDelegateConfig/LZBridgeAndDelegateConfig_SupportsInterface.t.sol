// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ILZBridgeAndDelegateConfig} from "src/policies/interfaces/ILZBridgeAndDelegateConfig.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

contract LZBridgeAndDelegateConfigTests_SupportsInterface is LZBridgeAndDelegateConfigTestBase {
    function test_supportsInterface_returnsTrueForIERC165() external view {
        assertTrue(
            config.supportsInterface(type(IERC165).interfaceId),
            "Config should advertise IERC165"
        );
    }

    function test_supportsInterface_returnsTrueForIEnabler() external view {
        assertTrue(
            config.supportsInterface(type(IEnabler).interfaceId),
            "Config should advertise IEnabler"
        );
    }

    function test_supportsInterface_returnsTrueForIPolicyAdmin() external view {
        assertTrue(
            config.supportsInterface(type(IPolicyAdmin).interfaceId),
            "Config should advertise IPolicyAdmin"
        );
    }

    function test_supportsInterface_returnsTrueForITimelockBatchQueue() external view {
        assertTrue(
            config.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "Config should advertise ITimelockBatchQueue"
        );
    }

    function test_supportsInterface_returnsTrueForILZBridgeAndDelegateConfig() external view {
        assertTrue(
            config.supportsInterface(type(ILZBridgeAndDelegateConfig).interfaceId),
            "Config should advertise ILZBridgeAndDelegateConfig"
        );
    }

    function test_supportsInterface_returnsTrueForIVersioned() external view {
        assertTrue(
            config.supportsInterface(type(IVersioned).interfaceId),
            "Config should advertise IVersioned"
        );
    }

    function test_supportsInterface_returnsFalseForUnknown() external view {
        assertFalse(config.supportsInterface(bytes4(0xdeadbeef)), "Random selector must not match");
    }
}
