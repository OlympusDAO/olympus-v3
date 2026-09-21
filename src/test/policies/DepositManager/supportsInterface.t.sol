// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract DepositManagerSupportsInterfaceTest is DepositManagerTest {
    // VERSION
    // given DepositManager deployed
    //  when VERSION is called
    //   then it returns V1.1
    function test_givenDepositManagerDeployed_VERSION_returnsV1_1() public view {
        (uint8 major, uint8 minor) = depositManager.VERSION();

        assertEq(major, 1, "major version mismatch");
        assertEq(minor, 1, "minor version mismatch");
    }

    function test_supportsInterface() public view {
        // Validate ERC165 compliance
        ERC165Helper.validateSupportsInterface(address(depositManager));

        // Test IERC165
        assertEq(
            depositManager.supportsInterface(type(IERC165).interfaceId),
            true,
            "IERC165 mismatch"
        );

        // Test IDepositManager
        assertEq(
            depositManager.supportsInterface(type(IDepositManager).interfaceId),
            true,
            "IDepositManager mismatch"
        );

        // Test IDepositManagerV1_1
        assertEq(
            depositManager.supportsInterface(type(IDepositManagerV1_1).interfaceId),
            true,
            "IDepositManagerV1_1 mismatch"
        );

        // Test IAssetManager
        assertEq(
            depositManager.supportsInterface(type(IAssetManager).interfaceId),
            true,
            "IAssetManager mismatch"
        );

        // Test IAssetManagerV1_1
        assertEq(
            depositManager.supportsInterface(type(IAssetManagerV1_1).interfaceId),
            true,
            "IAssetManagerV1_1 mismatch"
        );

        // Test IEnabler
        assertEq(
            depositManager.supportsInterface(type(IEnabler).interfaceId),
            true,
            "IEnabler mismatch"
        );
        assertTrue(
            depositManager.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 mismatch"
        );
        assertTrue(
            depositManager.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler mismatch"
        );
        assertTrue(
            depositManager.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod mismatch"
        );
        assertTrue(
            depositManager.supportsInterface(type(IConfigOperator).interfaceId),
            "IConfigOperator mismatch"
        );
        assertTrue(
            depositManager.supportsInterface(type(IVersioned).interfaceId),
            "IVersioned mismatch"
        );

        // Test non-implemented interfaces (should be false)
        assertEq(
            depositManager.supportsInterface(type(IERC20).interfaceId),
            false,
            "Should not support IERC20"
        );
        assertEq(
            depositManager.supportsInterface(type(IERC4626).interfaceId),
            false,
            "Should not support IERC4626"
        );
    }
}
