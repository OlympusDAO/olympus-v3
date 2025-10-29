// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC721} from "@openzeppelin-5.3.0/interfaces/IERC721.sol";

import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";
import {DEPOSTest} from "./DEPOSTest.sol";

contract DEPOSSupportsInterfaceTest is DEPOSTest {
    function test_supportsInterface() public view {
        // Validate ERC165 compliance
        ERC165Helper.validateSupportsInterface(address(DEPOS));

        // Test IERC165
        assertEq(DEPOS.supportsInterface(type(IERC165).interfaceId), true, "IERC165 mismatch");

        // Test IDepositPositionManager
        assertEq(
            DEPOS.supportsInterface(type(IDepositPositionManager).interfaceId),
            true,
            "IDepositPositionManager mismatch"
        );

        // Test IERC721 (from Solmate)
        assertEq(DEPOS.supportsInterface(type(IERC721).interfaceId), true, "IERC721 mismatch");

        // Test non-implemented interfaces (should be false)
        assertEq(
            DEPOS.supportsInterface(type(IERC20).interfaceId),
            false,
            "Should not support IERC20"
        );
    }
}
