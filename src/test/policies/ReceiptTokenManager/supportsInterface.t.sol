// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ReceiptTokenManagerTest} from "./ReceiptTokenManagerTest.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC6909, IERC6909Metadata, IERC6909TokenSupply} from "@openzeppelin-5.3.0/interfaces/draft-IERC6909.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract ReceiptTokenManagerSupportsInterfaceTest is ReceiptTokenManagerTest {
    function test_supportsInterface() public view {
        // Validate ERC165 compliance
        ERC165Helper.validateSupportsInterface(address(receiptTokenManager));

        // Test IERC165
        assertEq(
            receiptTokenManager.supportsInterface(type(IERC165).interfaceId),
            true,
            "IERC165 mismatch"
        );

        // Test IReceiptTokenManager
        assertEq(
            receiptTokenManager.supportsInterface(type(IReceiptTokenManager).interfaceId),
            true,
            "IReceiptTokenManager mismatch"
        );

        // Test IERC6909Wrappable
        assertEq(
            receiptTokenManager.supportsInterface(type(IERC6909Wrappable).interfaceId),
            true,
            "IERC6909Wrappable mismatch"
        );

        // Test IERC6909Metadata
        assertEq(
            receiptTokenManager.supportsInterface(type(IERC6909Metadata).interfaceId),
            true,
            "IERC6909Metadata mismatch"
        );

        // Test IERC6909TokenSupply
        assertEq(
            receiptTokenManager.supportsInterface(type(IERC6909TokenSupply).interfaceId),
            true,
            "IERC6909TokenSupply mismatch"
        );

        // Test IERC6909
        assertEq(
            receiptTokenManager.supportsInterface(type(IERC6909).interfaceId),
            true,
            "IERC6909 mismatch"
        );

        // Test non-implemented interfaces (should be false)
        assertEq(
            receiptTokenManager.supportsInterface(type(IERC20).interfaceId),
            false,
            "Should not support IERC20"
        );
    }
}
