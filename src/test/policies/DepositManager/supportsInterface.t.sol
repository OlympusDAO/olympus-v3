// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract DepositManagerSupportsInterfaceTest is DepositManagerTest {
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

        // Test IAssetManager
        assertEq(
            depositManager.supportsInterface(type(IAssetManager).interfaceId),
            true,
            "IAssetManager mismatch"
        );

        // Test IEnabler
        assertEq(
            depositManager.supportsInterface(type(IEnabler).interfaceId),
            true,
            "IEnabler mismatch"
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
